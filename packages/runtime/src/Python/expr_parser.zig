/// Runtime expression parser for eval()
/// Lightweight recursive descent parser for Python expressions
/// Compiles directly to bytecode for fast execution
const std = @import("std");
const bytecode = @import("compile.zig");

// Re-export submodules
pub const tokens = @import("expr_parser/tokens.zig");
pub const lexer = @import("expr_parser/lexer.zig");
pub const numeric_utils = @import("expr_parser/numeric_utils.zig");
pub const parser = @import("expr_parser/parser.zig");

// Re-export commonly used types
pub const ParseError = tokens.ParseError;
pub const TokenType = tokens.TokenType;
pub const Token = tokens.Token;
pub const Lexer = lexer.Lexer;
pub const ExprParser = parser.ExprParser;

/// Parse and compile expression to bytecode
pub fn parseExpression(allocator: std.mem.Allocator, source: []const u8) !bytecode.BytecodeProgram {
    var expr_parser = ExprParser.init(allocator, source);
    defer expr_parser.deinit();
    return expr_parser.parse();
}

// Tests
test "parse simple integer" {
    const allocator = std.testing.allocator;
    var program = try parseExpression(allocator, "42");
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 2), program.instructions.len);
    try std.testing.expectEqual(bytecode.OpCode.LoadConst, program.instructions[0].op);
    try std.testing.expectEqual(bytecode.OpCode.Return, program.instructions[1].op);
    try std.testing.expectEqual(@as(i64, 42), program.constants[0].int);
}

test "parse addition" {
    const allocator = std.testing.allocator;
    var program = try parseExpression(allocator, "1 + 2");
    defer program.deinit();

    try std.testing.expectEqual(@as(usize, 4), program.instructions.len);
    try std.testing.expectEqual(bytecode.OpCode.LoadConst, program.instructions[0].op);
    try std.testing.expectEqual(bytecode.OpCode.LoadConst, program.instructions[1].op);
    try std.testing.expectEqual(bytecode.OpCode.Add, program.instructions[2].op);
    try std.testing.expectEqual(bytecode.OpCode.Return, program.instructions[3].op);
}

test "parse precedence" {
    const allocator = std.testing.allocator;
    var program = try parseExpression(allocator, "1 + 2 * 3");
    defer program.deinit();

    // Should be: LOAD 1, LOAD 2, LOAD 3, MUL, ADD, RET
    try std.testing.expectEqual(@as(usize, 6), program.instructions.len);
    try std.testing.expectEqual(bytecode.OpCode.LoadConst, program.instructions[0].op);
    try std.testing.expectEqual(bytecode.OpCode.LoadConst, program.instructions[1].op);
    try std.testing.expectEqual(bytecode.OpCode.LoadConst, program.instructions[2].op);
    try std.testing.expectEqual(bytecode.OpCode.Mult, program.instructions[3].op);
    try std.testing.expectEqual(bytecode.OpCode.Add, program.instructions[4].op);
}
