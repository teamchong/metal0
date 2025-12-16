/// Comptime assignment helpers - emit optimized compile-time constant assignments
const std = @import("std");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const ComptimeValue = @import("../../../analysis/comptime_eval.zig").ComptimeValue;
const zig_keywords = @import("utils.zig_keywords");

/// Emit assignment with compile-time constant value
/// Generates optimized code like: const x: i64 = 5;
pub fn emitComptimeAssignment(
    self: *NativeCodegen,
    var_name: []const u8,
    value: ComptimeValue,
    is_first_assignment: bool,
    is_mutable: bool,
) CodegenError!void {
    try self.emitIndent();

    // Check if var_name would shadow a module-level import, function, or global var
    // If so, create a prefixed name to avoid Zig's "shadows declaration" error
    // This must happen BEFORE checking var_renames, so the rename gets created
    if (is_first_assignment) {
        const shadows_import = self.imported_modules.contains(var_name);
        const shadows_module_func = self.module_level_funcs.contains(var_name);
        const shadows_global = self.isGlobalVar(var_name);
        // Also check if var_name would shadow a class-level attribute (becomes lazy method)
        const shadows_class_member = if (self.current_class_body) |class_body| blk: {
            for (class_body) |stmt| {
                if (stmt == .assign) {
                    for (stmt.assign.targets) |target| {
                        if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                            break :blk true;
                        }
                    }
                }
            }
            break :blk false;
        } else false;

        const needs_local_rename = shadows_import or shadows_module_func or shadows_global or shadows_class_member;
        const existing_rename = self.var_renames.get(var_name);
        const has_lazy_pattern = if (existing_rename) |r| std.mem.startsWith(u8, r, "(try ") else false;
        if (needs_local_rename and (existing_rename == null or has_lazy_pattern)) {
            // Create a unique prefixed name using NameGen
            const prefixed_name = try self.name_gen.local(var_name);
            try self.var_renames.put(var_name, prefixed_name);
        }
    }

    // Check if variable has been renamed (e.g., for try/except pointer params or shadowing)
    const actual_name = self.var_renames.get(var_name) orelse var_name;

    if (is_first_assignment) {
        // Use var for mutable variables, const for immutable
        if (is_mutable) {
            try self.emit("var ");
        } else {
            try self.emit("const ");
        }
    }

    // Escape Zig reserved keywords (e.g., "false" -> @"false")
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), actual_name);

    if (is_first_assignment) {
        // Emit type annotation
        try self.emit(": ");
        switch (value) {
            .int => try self.emit("i64"),
            .float => try self.emit("f64"),
            .bool => try self.emit("bool"),
            .string, .owned_string => try self.emit("[]const u8"),
            .bytes, .owned_bytes => try self.emit("runtime.builtins.PyBytes"),
            .list, .owned_list => |items| {
                if (items.len == 0) {
                    try self.emit("[0]i64"); // Empty list default type
                } else {
                    // Infer element type from first element
                    const elem_type = switch (items[0]) {
                        .int => "i64",
                        .float => "f64",
                        .bool => "bool",
                        .string, .owned_string => "[]const u8",
                        .bytes, .owned_bytes => "runtime.builtins.PyBytes",
                        .list, .owned_list => "ComptimeValue", // Nested lists not fully supported
                    };
                    try self.output.writer(self.allocator).print("[{d}]{s}", .{ items.len, elem_type });
                }
            },
        }
    }

    try self.emit(" = ");

    // Emit value
    switch (value) {
        .int => |v| try self.output.writer(self.allocator).print("{d}", .{v}),
        .float => |v| {
            // Handle special values first to avoid printing just "inf" or "nan"
            if (std.math.isInf(v)) {
                try self.emit(if (v < 0) "-std.math.inf(f64)" else "std.math.inf(f64)");
            } else if (std.math.isNan(v)) {
                try self.emit("std.math.nan(f64)");
            } else if (@mod(v, 1.0) == 0.0) {
                // Use Python-style float formatting (always show .0 for whole numbers)
                try self.output.writer(self.allocator).print("{d:.1}", .{v});
            } else {
                try self.output.writer(self.allocator).print("{d}", .{v});
            }
        },
        .bool => |v| {
            const bool_str = if (v) "true" else "false";
            try self.emit(bool_str);
        },
        .string, .owned_string => |v| {
            // Escape the string properly
            try self.emit("\"");
            for (v) |c| {
                switch (c) {
                    '\n' => try self.emit("\\n"),
                    '\r' => try self.emit("\\r"),
                    '\t' => try self.emit("\\t"),
                    '\\' => try self.emit("\\\\"),
                    '"' => try self.emit("\\\""),
                    else => try self.output.append(self.allocator, c),
                }
            }
            try self.emit("\"");
        },
        .bytes, .owned_bytes => |v| {
            // Use runtime.builtins.bytesLiteral for Python bytes type
            try self.emit("runtime.builtins.bytesLiteral(\"");
            for (v) |c| {
                switch (c) {
                    '\n' => try self.emit("\\n"),
                    '\r' => try self.emit("\\r"),
                    '\t' => try self.emit("\\t"),
                    '\\' => try self.emit("\\\\"),
                    '"' => try self.emit("\\\""),
                    else => {
                        // For bytes, emit hex for non-printable chars
                        if (c < 0x20 or c >= 0x7f) {
                            try self.output.writer(self.allocator).print("\\x{x:0>2}", .{c});
                        } else {
                            try self.output.append(self.allocator, c);
                        }
                    },
                }
            }
            try self.emit("\")");
        },
        .list, .owned_list => |items| {
            if (items.len == 0) {
                try self.emit(".{}");
            } else {
                try self.emit(".{ ");
                for (items, 0..) |item, i| {
                    if (i > 0) try self.emit(", ");

                    switch (item) {
                        .int => |v| try self.output.writer(self.allocator).print("{d}", .{v}),
                        .float => |v| {
                            // Use Python-style float formatting (always show .0 for whole numbers)
                            if (@mod(v, 1.0) == 0.0) {
                                try self.output.writer(self.allocator).print("{d:.1}", .{v});
                            } else {
                                try self.output.writer(self.allocator).print("{d}", .{v});
                            }
                        },
                        .bool => |v| {
                            const bool_str = if (v) "true" else "false";
                            try self.emit(bool_str);
                        },
                        .string, .owned_string => |v| try self.output.writer(self.allocator).print("\"{s}\"", .{v}),
                        .bytes, .owned_bytes => |v| try self.output.writer(self.allocator).print("runtime.builtins.bytesLiteral(\"{s}\")", .{v}),
                        .list, .owned_list => {
                            // Nested lists not fully supported yet
                            try self.emit(".{}");
                        },
                    }
                }
                try self.emit(" }");
            }
        },
    }

    try self.emit(";\n");
}

/// Free memory allocated for comptime value
pub fn freeComptimeValue(allocator: std.mem.Allocator, value: ComptimeValue) void {
    switch (value) {
        .string, .owned_string => |s| allocator.free(s),
        .bytes, .owned_bytes => |s| allocator.free(s),
        .list, .owned_list => |items| {
            for (items) |item| {
                freeComptimeValue(allocator, item);
            }
            allocator.free(items);
        },
        else => {}, // int, float, bool don't allocate
    }
}
