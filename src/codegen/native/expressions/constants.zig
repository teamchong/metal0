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
        .bool => try self.emit(if (constant.value.bool) "true" else "false"),
        .none => try self.emit("null"), // Zig null represents None
        .string => |s| {
            // Strip Python quotes
            const content = if (s.len >= 2) s[1 .. s.len - 1] else s;

            // Escape quotes and backslashes for Zig string literal
            try self.emit("\"");
            for (content) |c| {
                switch (c) {
                    '"' => try self.emit("\\\""),
                    '\\' => try self.emit("\\\\"),
                    '\n' => try self.emit("\\n"),
                    '\r' => try self.emit("\\r"),
                    '\t' => try self.emit("\\t"),
                    else => try self.output.writer(self.allocator).print("{c}", .{c}),
                }
            }
            try self.emit("\"");
        },
    }
}
