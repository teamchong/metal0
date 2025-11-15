const std = @import("std");
const ast = @import("../../ast.zig");
const CodegenError = @import("../../codegen.zig").CodegenError;
const ExprResult = @import("../../codegen.zig").ExprResult;
const ZigCodeGenerator = @import("../../codegen.zig").ZigCodeGenerator;
const expressions = @import("../expressions.zig");

pub fn visitClassInstantiation(self: *ZigCodeGenerator, class_name: []const u8, args: []ast.Node) CodegenError!ExprResult {
    var buf = std.ArrayList(u8){};
    try buf.writer(self.temp_allocator).print("{s}.init(", .{class_name});
    for (args, 0..) |arg, i| {
        if (i > 0) try buf.writer(self.temp_allocator).writeAll(", ");
        const arg_result = try expressions.visitExpr(self,arg);
        // Add 'try' if the argument needs it (e.g., PyString.create)
        if (arg_result.needs_try) {
            try buf.writer(self.temp_allocator).print("try {s}", .{arg_result.code});
        } else {
            try buf.writer(self.temp_allocator).writeAll(arg_result.code);
        }
    }
    try buf.writer(self.temp_allocator).writeAll(")");
    return ExprResult{
        .code = try buf.toOwnedSlice(self.temp_allocator),
        .needs_try = false,
    };
}

/// Check if method needs allocator parameter (returns PyObject)

pub fn wrapPrimitiveIfNeeded(self: *ZigCodeGenerator, node: ast.Node, arg_code: []const u8) ![]const u8 {
    switch (node) {
        .constant => |c| {
            switch (c.value) {
                .int => {
                    return try std.fmt.allocPrint(self.temp_allocator,
                        "try runtime.PyInt.create(allocator, {s})", .{arg_code});
                },
                .string => {
                    return try std.fmt.allocPrint(self.temp_allocator,
                        "try runtime.PyString.create(allocator, {s})", .{arg_code});
                },
                .bool => {
                    return try std.fmt.allocPrint(self.temp_allocator,
                        "runtime.PyBool.create({s})", .{arg_code});
                },
                .float => {
                    return try std.fmt.allocPrint(self.temp_allocator,
                        "try runtime.PyFloat.create(allocator, {s})", .{arg_code});
                },
            }
        },
        else => return arg_code,
    }
}

/// Helper function to wrap primitive as PyObject and create temp variable with defer decref
pub fn wrapPrimitiveWithDecref(self: *ZigCodeGenerator, node: ast.Node, arg_result: ExprResult) ![]const u8 {
    const needs_wrap = switch (node) {
        .constant => |c| switch (c.value) {
            .int, .string, .float => true,
            else => false,
        },
        else => false,
    };

    if (needs_wrap) {
        // Create wrapped version WITHOUT 'try' - extractResultToStatement will add it
        var wrapped_code_buf = std.ArrayList(u8){};
        switch (node) {
            .constant => |c| {
                switch (c.value) {
                    .int => try wrapped_code_buf.writer(self.temp_allocator).print("runtime.PyInt.create(allocator, {s})", .{arg_result.code}),
                    .string => try wrapped_code_buf.writer(self.temp_allocator).print("runtime.PyString.create(allocator, {s})", .{arg_result.code}),
                    .float => try wrapped_code_buf.writer(self.temp_allocator).print("runtime.PyFloat.create(allocator, {s})", .{arg_result.code}),
                    else => unreachable,
                }
            },
            else => unreachable,
        }
        const wrapped_code = try wrapped_code_buf.toOwnedSlice(self.temp_allocator);
        const wrapped_result = ExprResult{
            .code = wrapped_code,
            .needs_try = true,
            .needs_decref = true,
        };
        // Extract to statement with defer decref
        return try self.extractResultToStatement(wrapped_result);
    } else {
        // Not a primitive, use as-is
        return arg_result.code;
    }
}
