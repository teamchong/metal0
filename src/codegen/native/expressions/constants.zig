/// Constant value code generation
/// Handles Python literals: int, float, bool, string, none
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

/// Generate constant values (int, float, bool, string, none)
pub fn genConstant(self: *NativeCodegen, constant: ast.Node.Constant) CodegenError!void {
    switch (constant.value) {
        .int => try self.output.writer(self.allocator).print("{d}", .{constant.value.int}),
        .float => |f| {
            // Cast to f64 to avoid comptime_float issues with format strings
            // Use Python-style float formatting (always show .0 for whole numbers)
            if (@mod(f, 1.0) == 0.0) {
                try self.output.writer(self.allocator).print("@as(f64, {d:.1})", .{f});
            } else {
                try self.output.writer(self.allocator).print("@as(f64, {d})", .{f});
            }
        },
        .bool => try self.output.appendSlice(self.allocator, if (constant.value.bool) "true" else "false"),
        .none => try self.output.appendSlice(self.allocator, "null"), // Zig null represents None
        .string => |s| {
            // Strip Python quotes
            const content = if (s.len >= 2) s[1 .. s.len - 1] else s;

            // Escape quotes and backslashes for Zig string literal
            try self.output.appendSlice(self.allocator, "\"");
            for (content) |c| {
                switch (c) {
                    '"' => try self.output.appendSlice(self.allocator, "\\\""),
                    '\\' => try self.output.appendSlice(self.allocator, "\\\\"),
                    '\n' => try self.output.appendSlice(self.allocator, "\\n"),
                    '\r' => try self.output.appendSlice(self.allocator, "\\r"),
                    '\t' => try self.output.appendSlice(self.allocator, "\\t"),
                    else => try self.output.writer(self.allocator).print("{c}", .{c}),
                }
            }
            try self.output.appendSlice(self.allocator, "\"");
        },
    }
}
