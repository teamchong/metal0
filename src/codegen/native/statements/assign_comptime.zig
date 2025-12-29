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
    // Check if var_name would shadow a module-level import, function, or global var
    // If so, create a prefixed name to avoid Zig's "shadows declaration" error
    // This must happen BEFORE checking var_renames, so the rename gets created
    if (is_first_assignment) {
        const shadows_import = self.imported_modules.contains(var_name);
        const shadows_module_func = self.module_level_funcs.contains(var_name);
        const shadows_global = self.isGlobalVar(var_name);
        // Check if var_name would shadow a vararg or kwarg parameter (e.g., *args or **kwargs)
        const shadows_vararg_param = self.vararg_params.contains(var_name) or self.kwarg_params.contains(var_name);
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

        const needs_local_rename = shadows_import or shadows_module_func or shadows_global or shadows_class_member or shadows_vararg_param;
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

    const b = try self.getBuilder();
    try b.writeIndent();

    // Check if target variable is a UnifiedInt that needs wrapping
    // For reassignments (not first assignment), check symbol_table or type_inferrer
    const is_unified_int_target = if (!is_first_assignment) blk: {
        // Check symbol_table first
        if (self.symbol_table.getType(var_name)) |declared_type| {
            break :blk (declared_type == .unified_int);
        }
        // Fall back to type_inferrer.var_types for module-level vars
        if (self.type_inferrer.var_types.get(var_name)) |inferred_type| {
            break :blk (inferred_type == .unified_int);
        }
        break :blk false;
    } else false;

    if (is_first_assignment) {
        // Use var for mutable variables, const for immutable
        if (is_mutable) {
            try b.emitRaw("var ");
        } else {
            try b.emitRaw("const ");
        }
    }

    // Escape Zig reserved keywords (e.g., "false" -> @"false")
    try zig_keywords.writeEscapedIdent(b.body.writer(b.allocator), actual_name);

    if (is_first_assignment) {
        // Emit type annotation
        try b.emitRaw(": ");
        switch (value) {
            .int => try b.emitRaw("i64"),
            .float => try b.emitRaw("f64"),
            .bool => try b.emitRaw("bool"),
            .string, .owned_string => try b.emitRaw("[]const u8"),
            .bytes, .owned_bytes => try b.emitRaw("runtime.builtins.PyBytes"),
            .list, .owned_list => |items| {
                if (items.len == 0) {
                    try b.emitRaw("[0]i64"); // Empty list default type
                } else {
                    // Check if any element exceeds i32 range - if so, use UnifiedInt
                    var has_large_int = false;
                    for (items) |item| {
                        if (item == .int) {
                            const v = item.int;
                            if (v > std.math.maxInt(i32) or v < std.math.minInt(i32)) {
                                has_large_int = true;
                                break;
                            }
                        }
                    }
                    // Infer element type from first element
                    const elem_type: []const u8 = if (has_large_int and items[0] == .int)
                        "runtime.UnifiedInt"
                    else switch (items[0]) {
                        .int => "i64",
                        .float => "f64",
                        .bool => "bool",
                        .string, .owned_string => "[]const u8",
                        .bytes, .owned_bytes => "runtime.builtins.PyBytes",
                        .list, .owned_list => "ComptimeValue", // Nested lists not fully supported
                    };
                    try b.writeFmt("[{d}]{s}", .{ items.len, elem_type });
                }
            },
        }
    }

    try b.emitRaw(" = ");

    // Emit value
    const writer = b.body.writer(b.allocator);
    switch (value) {
        .int => |v| {
            // Wrap in UnifiedInt.fromI64() if target is UnifiedInt
            if (is_unified_int_target) {
                try b.writeFmt("runtime.UnifiedInt.fromI64({d})", .{v});
            } else {
                try b.writeFmt("{d}", .{v});
            }
        },
        .float => |v| {
            // Handle special values first to avoid printing just "inf" or "nan"
            if (std.math.isInf(v)) {
                try b.emitRaw(if (v < 0) "-std.math.inf(f64)" else "std.math.inf(f64)");
            } else if (std.math.isNan(v)) {
                try b.emitRaw("std.math.nan(f64)");
            } else if (@mod(v, 1.0) == 0.0) {
                // Use Python-style float formatting (always show .0 for whole numbers)
                try b.writeFmt("{d:.1}", .{v});
            } else {
                try b.writeFmt("{d}", .{v});
            }
        },
        .bool => |v| {
            const bool_str = if (v) "true" else "false";
            try b.emitRaw(bool_str);
        },
        .string, .owned_string => |v| {
            // Use shared Python string escape handling from constants module
            // This properly interprets Python escape sequences like \n -> newline
            const constants = @import("../expressions/constants.zig");
            // Flush builder buffer first, then emit string, then reopen builder
            const output = try b.getBodyDupe();
            try self.output.appendSlice(self.allocator, output);
            try self.emit("\"");
            try constants.emitZigStringContent(self, v, constants.StringContext.default);
            try self.emit("\"");
        },
        .bytes, .owned_bytes => |v| {
            // Use runtime.builtins.bytesLiteral for Python bytes type
            try b.emitRaw("runtime.builtins.bytesLiteral(\"");
            for (v) |c| {
                switch (c) {
                    '\n' => try b.emitRaw("\\n"),
                    '\r' => try b.emitRaw("\\r"),
                    '\t' => try b.emitRaw("\\t"),
                    '\\' => try b.emitRaw("\\\\"),
                    '"' => try b.emitRaw("\\\""),
                    else => {
                        // For bytes, emit hex for non-printable chars
                        if (c < 0x20 or c >= 0x7f) {
                            try b.writeFmt("\\x{x:0>2}", .{c});
                        } else {
                            try writer.writeByte(c);
                        }
                    },
                }
            }
            try b.emitRaw("\")");
        },
        .list, .owned_list => |items| {
            // Check if list elements should be wrapped as UnifiedInt
            // This happens when the list contains mixed integer sizes (e.g., [324, 2**31])
            const list_elem_is_unified_int = blk: {
                // Check if the target variable's list element type is unified_int
                if (self.symbol_table.getType(var_name)) |declared_type| {
                    if (declared_type == .list) {
                        break :blk (declared_type.list.* == .unified_int);
                    }
                }
                if (self.type_inferrer.var_types.get(var_name)) |inferred_type| {
                    if (inferred_type == .list) {
                        break :blk (inferred_type.list.* == .unified_int);
                    }
                }
                // Check if any item is a large int (e.g., 2**31 produces bigint comptime)
                // If so, treat the whole list as UnifiedInt
                for (items) |item| {
                    if (item == .int) {
                        const v = item.int;
                        // If value exceeds i32 range, it's likely from a large computation
                        if (v > std.math.maxInt(i32) or v < std.math.minInt(i32)) {
                            break :blk true;
                        }
                    }
                }
                break :blk false;
            };

            if (items.len == 0) {
                try b.emitRaw(".{}");
            } else {
                try b.emitRaw(".{ ");
                for (items, 0..) |item, i| {
                    if (i > 0) try b.emitRaw(", ");

                    switch (item) {
                        .int => |v| {
                            if (list_elem_is_unified_int) {
                                try b.writeFmt("runtime.UnifiedInt.fromI64({d})", .{v});
                            } else {
                                try b.writeFmt("{d}", .{v});
                            }
                        },
                        .float => |v| {
                            // Use Python-style float formatting (always show .0 for whole numbers)
                            if (@mod(v, 1.0) == 0.0) {
                                try b.writeFmt("{d:.1}", .{v});
                            } else {
                                try b.writeFmt("{d}", .{v});
                            }
                        },
                        .bool => |v| {
                            const bool_str = if (v) "true" else "false";
                            try b.emitRaw(bool_str);
                        },
                        .string, .owned_string => |v| try b.writeFmt("\"{s}\"", .{v}),
                        .bytes, .owned_bytes => |v| try b.writeFmt("runtime.builtins.bytesLiteral(\"{s}\")", .{v}),
                        .list, .owned_list => {
                            // Nested lists not fully supported yet
                            try b.emitRaw(".{}");
                        },
                    }
                }
                try b.emitRaw(" }");
            }
        },
    }

    try b.emitRaw(";\n");
    const output = try b.getBodyDupe();
    try self.output.appendSlice(self.allocator, output);
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
