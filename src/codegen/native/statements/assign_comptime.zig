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

    if (is_first_assignment) {
        // Use var for mutable variables, const for immutable
        if (is_mutable) {
            try self.output.appendSlice(self.allocator, "var ");
        } else {
            try self.output.appendSlice(self.allocator, "const ");
        }
    }

    try self.output.appendSlice(self.allocator, var_name);

    if (is_first_assignment) {
        // Emit type annotation
        try self.output.appendSlice(self.allocator, ": ");
        switch (value) {
            .int => try self.output.appendSlice(self.allocator, "i64"),
            .float => try self.output.appendSlice(self.allocator, "f64"),
            .bool => try self.output.appendSlice(self.allocator, "bool"),
            .string => try self.output.appendSlice(self.allocator, "[]const u8"),
            .list => |items| {
                if (items.len == 0) {
                    try self.output.appendSlice(self.allocator, "[0]i64"); // Empty list default type
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

    try self.output.appendSlice(self.allocator, " = ");

    // Emit value
    switch (value) {
        .int => |v| try self.output.writer(self.allocator).print("{d}", .{v}),
        .float => |v| try self.output.writer(self.allocator).print("{d}", .{v}),
        .bool => |v| {
            const bool_str = if (v) "true" else "false";
            try self.output.appendSlice(self.allocator, bool_str);
        },
        .string => |v| {
            // Escape the string properly
            try self.output.appendSlice(self.allocator, "\"");
            for (v) |c| {
                switch (c) {
                    '\n' => try self.output.appendSlice(self.allocator, "\\n"),
                    '\r' => try self.output.appendSlice(self.allocator, "\\r"),
                    '\t' => try self.output.appendSlice(self.allocator, "\\t"),
                    '\\' => try self.output.appendSlice(self.allocator, "\\\\"),
                    '"' => try self.output.appendSlice(self.allocator, "\\\""),
                    else => try self.output.append(self.allocator, c),
                }
            }
            try self.output.appendSlice(self.allocator, "\"");
        },
        .list => |items| {
            if (items.len == 0) {
                try self.output.appendSlice(self.allocator, ".{}");
            } else {
                try self.output.appendSlice(self.allocator, ".{ ");
                for (items, 0..) |item, i| {
                    if (i > 0) try self.output.appendSlice(self.allocator, ", ");

                    switch (item) {
                        .int => |v| try self.output.writer(self.allocator).print("{d}", .{v}),
                        .float => |v| try self.output.writer(self.allocator).print("{d}", .{v}),
                        .bool => |v| {
                            const bool_str = if (v) "true" else "false";
                            try self.output.appendSlice(self.allocator, bool_str);
                        },
                        .string => |v| try self.output.writer(self.allocator).print("\"{s}\"", .{v}),
                        .list => {
                            // Nested lists not fully supported yet
                            try self.output.appendSlice(self.allocator, ".{}");
                        },
                    }
                }
                try self.output.appendSlice(self.allocator, " }");
            }
        },
    }

    try self.output.appendSlice(self.allocator, ";\n");
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
