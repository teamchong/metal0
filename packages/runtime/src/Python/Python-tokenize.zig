/// Python-tokenize - Python Tokenizer
/// Mirrors cpython/Python/Python-tokenize.c
///
/// Low-level tokenization of Python source code.
/// Converts source text into a stream of tokens.

const std = @import("std");

// Re-export core types
pub const types = @import("Python-tokenize/types.zig");
pub const TokenType = types.TokenType;
pub const Token = types.Token;
pub const Position = types.Position;

// Re-export tokenizer
const tokenizer_impl = @import("Python-tokenize/tokenizer.zig");
pub const Tokenizer = tokenizer_impl.Tokenizer;

// Re-export helpers (for testing/internal use)
pub const helpers = @import("Python-tokenize/helpers.zig");
pub const string_reader = @import("Python-tokenize/string_reader.zig");
pub const number_reader = @import("Python-tokenize/number_reader.zig");
pub const operator_reader = @import("Python-tokenize/operator_reader.zig");

// ============================================================================
// Module Initialization
// ============================================================================

var initialized: bool = false;

/// Initialize the Python-tokenize module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "tokenize simple expression" {
    const allocator = std.testing.allocator;
    const source = "1 + 2";

    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const t1 = try tokenizer.nextToken();
    try std.testing.expectEqual(TokenType.NUMBER, t1.type_);
    try std.testing.expectEqualStrings("1", t1.string);

    const t2 = try tokenizer.nextToken();
    try std.testing.expectEqual(TokenType.PLUS, t2.type_);

    const t3 = try tokenizer.nextToken();
    try std.testing.expectEqual(TokenType.NUMBER, t3.type_);
    try std.testing.expectEqualStrings("2", t3.string);

    const t4 = try tokenizer.nextToken();
    try std.testing.expectEqual(TokenType.NEWLINE, t4.type_);
}

test "tokenize string" {
    const allocator = std.testing.allocator;
    const source = "\"hello\"";

    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const t1 = try tokenizer.nextToken();
    try std.testing.expectEqual(TokenType.STRING, t1.type_);
    try std.testing.expectEqualStrings("hello", t1.string);
}

test "tokenize name" {
    const allocator = std.testing.allocator;
    const source = "foo_bar";

    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const t1 = try tokenizer.nextToken();
    try std.testing.expectEqual(TokenType.NAME, t1.type_);
    try std.testing.expectEqualStrings("foo_bar", t1.string);
}

test "tokenize operators" {
    const allocator = std.testing.allocator;
    const source = "== != <= >=";

    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    try std.testing.expectEqual(TokenType.EQEQUAL, (try tokenizer.nextToken()).type_);
    try std.testing.expectEqual(TokenType.NOTEQUAL, (try tokenizer.nextToken()).type_);
    try std.testing.expectEqual(TokenType.LESSEQUAL, (try tokenizer.nextToken()).type_);
    try std.testing.expectEqual(TokenType.GREATEREQUAL, (try tokenizer.nextToken()).type_);
}

test "tokenize hex number" {
    const allocator = std.testing.allocator;
    const source = "0xff";

    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    const t1 = try tokenizer.nextToken();
    try std.testing.expectEqual(TokenType.NUMBER, t1.type_);
    try std.testing.expectEqualStrings("0xff", t1.string);
}

test "bracket level tracking" {
    const allocator = std.testing.allocator;
    const source = "(1 +\n2)";

    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    _ = try tokenizer.nextToken(); // (
    _ = try tokenizer.nextToken(); // 1
    _ = try tokenizer.nextToken(); // +

    const nl = try tokenizer.nextToken();
    try std.testing.expectEqual(TokenType.NL, nl.type_); // NL, not NEWLINE

    _ = try tokenizer.nextToken(); // 2
    _ = try tokenizer.nextToken(); // )
}
