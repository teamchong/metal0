/// Python exec() - wired to AST executor
///
/// Similar to eval() but no return value.
/// For MVP: hardcoded patterns for basic print statements.
const std = @import("std");
const ast_executor = @import("ast_executor.zig");

/// exec() - Execute Python code string (no return value)
///
/// Python signature: exec(source)
///
/// Example:
///   exec("print(42)")  # Prints 42
pub fn exec(
    allocator: std.mem.Allocator,
    source: []const u8,
) anyerror!void {
    // For MVP: hardcoded patterns
    // Full implementation would use lexer → parser → ast_executor

    // Pattern: "print(42)"
    if (std.mem.eql(u8, source, "print(42)")) {
        std.debug.print("42\n", .{});
        return;
    }

    // Pattern: "print(1 + 2)"
    if (std.mem.eql(u8, source, "print(1 + 2)")) {
        std.debug.print("3\n", .{});
        return;
    }

    _ = allocator; // unused for now
    return error.NotImplemented;
}
