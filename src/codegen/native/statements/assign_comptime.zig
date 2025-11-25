/// Comptime assignment helpers - emit optimized compile-time constant assignments
const std = @import("std");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const ComptimeValue = @import("../../../analysis/comptime_eval.zig").ComptimeValue;

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

    // Check if variable has been renamed (e.g., for try/except pointer params)
    const actual_name = self.var_renames.get(var_name) orelse var_name;

    if (is_first_assignment) {
        // Use var for mutable variables, const for immutable
        if (is_mutable) {
            try self.emit("var ");
        } else {
            try self.emit("const ");
        }
    }

    try self.emit(actual_name);

    if (is_first_assignment) {
        // Emit type annotation
        try self.emit(": ");
        switch (value) {
            .int => try self.emit("i64"),
            .float => try self.emit("f64"),
            .bool => try self.emit("bool"),
            .string => try self.emit("[]const u8"),
            .list => |items| {
                if (items.len == 0) {
                    try self.emit("[0]i64"); // Empty list default type
                } else {
                    // Infer element type from first element
                    const elem_type = switch (items[0]) {
                        .int => "i64",
                        .float => "f64",
                        .bool => "bool",
                        .string => "[]const u8",
                        .list => "ComptimeValue", // Nested lists not fully supported
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
        .string => |v| {
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
        .list => |items| {
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
                        .string => |v| try self.output.writer(self.allocator).print("\"{s}\"", .{v}),
                        .list => {
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
        .string => |s| allocator.free(s),
        .list => |items| {
            for (items) |item| {
                freeComptimeValue(allocator, item);
            }
            allocator.free(items);
        },
        else => {}, // int, float, bool don't allocate
    }
}
