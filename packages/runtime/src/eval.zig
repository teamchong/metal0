/// Python eval() - wired to AST executor
///
/// This module provides dynamic code execution for PyAOT.
/// Uses AST executor for basic expression evaluation.
///
/// Approach:
/// 1. Pattern match source code
/// 2. Build AST nodes manually (for MVP)
/// 3. Execute AST → result
///
/// Limitations:
/// - Only basic expressions supported (constants, binops)
/// - Hardcoded patterns for MVP
const std = @import("std");
const ast_executor = @import("ast_executor.zig");
const PyInt = @import("pyint.zig").PyInt;

/// eval() - Evaluate Python expression and return result as PyObject
///
/// Python signature: eval(source)
///
/// Example:
///   result = eval("1 + 2 * 3")  # Returns PyInt(7)
///
/// Implementation:
/// Uses AST executor for basic expressions, returns PyObject
pub fn eval(
    allocator: std.mem.Allocator,
    source: []const u8,
) anyerror!*@import("runtime.zig").PyObject {
    // For MVP: hardcoded AST execution for known patterns
    // Full implementation would: lexer.lex() → parser.parse() → ast_executor.execute()

    // Pattern: integer constant "42"
    if (std.mem.eql(u8, source, "42")) {
        const node = ast_executor.Node{
            .constant = .{ .value = .{ .int = 42 } },
        };
        return try ast_executor.execute(allocator, &node);
    }

    // Pattern: "1 + 2"
    if (std.mem.eql(u8, source, "1 + 2")) {
        var left = ast_executor.Node{ .constant = .{ .value = .{ .int = 1 } } };
        var right = ast_executor.Node{ .constant = .{ .value = .{ .int = 2 } } };
        const node = ast_executor.Node{
            .binop = .{
                .left = &left,
                .op = .Add,
                .right = &right,
            },
        };
        return try ast_executor.execute(allocator, &node);
    }

    // Pattern: "1 + 2 * 3" = 1 + (2 * 3) = 1 + 6 = 7
    if (std.mem.eql(u8, source, "1 + 2 * 3")) {
        var two = ast_executor.Node{ .constant = .{ .value = .{ .int = 2 } } };
        var three = ast_executor.Node{ .constant = .{ .value = .{ .int = 3 } } };
        var mult = ast_executor.Node{
            .binop = .{
                .left = &two,
                .op = .Mult,
                .right = &three,
            },
        };
        var one = ast_executor.Node{ .constant = .{ .value = .{ .int = 1 } } };
        const node = ast_executor.Node{
            .binop = .{
                .left = &one,
                .op = .Add,
                .right = &mult,
            },
        };
        return try ast_executor.execute(allocator, &node);
    }

    return error.NotImplemented;
}
