//! test.test_peg_generator.test_tokenizer - Token stream handling tests
//!
//! This module tests the tokenization layer for PEG parsers, including token
//! types, lexer functionality, and token stream operations.

const std = @import("std");

/// Token types for a typical PEG grammar
pub const TokenType = enum {
    // Literals and identifiers
    identifier,
    string_literal,
    number,
    regex,

    // Operators
    arrow, // <-
    slash, // /
    ampersand, // &
    exclamation, // !
    question, // ?
    star, // *
    plus, // +
    dot, // .

    // Grouping
    lparen, // (
    rparen, // )
    lbracket, // [
    rbracket, // ]
    lbrace, // {
    rbrace, // }

    // Special
    colon, // :
    semicolon, // ;
    newline,
    whitespace,
    comment,
    eof,
    invalid,

    pub fn isOperator(self: TokenType) bool {
        return switch (self) {
            .arrow, .slash, .ampersand, .exclamation, .question, .star, .plus, .dot => true,
            else => false,
        };
    }

    pub fn isGrouping(self: TokenType) bool {
        return switch (self) {
            .lparen, .rparen, .lbracket, .rbracket, .lbrace, .rbrace => true,
            else => false,
        };
    }

    pub fn precedence(self: TokenType) u8 {
        return switch (self) {
            .slash => 1, // lowest
            .ampersand, .exclamation => 2,
            .question, .star, .plus => 3, // highest
            else => 0,
        };
    }
};

/// A single token with position information
pub const Token = struct {
    token_type: TokenType,
    lexeme: []const u8,
    line: usize,
    column: usize,
    start_offset: usize,
    end_offset: usize,

    pub fn init(token_type: TokenType, lexeme: []const u8, line: usize, column: usize, start: usize, end: usize) Token {
        return .{
            .token_type = token_type,
            .lexeme = lexeme,
            .line = line,
            .column = column,
            .start_offset = start,
            .end_offset = end,
        };
    }

    pub fn length(self: Token) usize {
        return self.end_offset - self.start_offset;
    }

    pub fn isEof(self: Token) bool {
        return self.token_type == .eof;
    }

    pub fn isValid(self: Token) bool {
        return self.token_type != .invalid;
    }

    pub fn matches(self: Token, expected_type: TokenType) bool {
        return self.token_type == expected_type;
    }

    pub fn matchesLexeme(self: Token, expected: []const u8) bool {
        return std.mem.eql(u8, self.lexeme, expected);
    }
};

/// Lexer for tokenizing PEG grammar input
pub const Lexer = struct {
    source: []const u8,
    position: usize,
    line: usize,
    column: usize,
    tokens: std.ArrayList(Token),
    allocator: std.mem.Allocator,
    skip_whitespace: bool,
    skip_comments: bool,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Lexer {
        return .{
            .source = source,
            .position = 0,
            .line = 1,
            .column = 1,
            .tokens = std.ArrayList(Token).init(allocator),
            .allocator = allocator,
            .skip_whitespace = true,
            .skip_comments = true,
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit();
    }

    pub fn isAtEnd(self: Lexer) bool {
        return self.position >= self.source.len;
    }

    pub fn peek(self: Lexer) ?u8 {
        if (self.isAtEnd()) return null;
        return self.source[self.position];
    }

    pub fn peekNext(self: Lexer) ?u8 {
        if (self.position + 1 >= self.source.len) return null;
        return self.source[self.position + 1];
    }

    pub fn advance(self: *Lexer) ?u8 {
        if (self.isAtEnd()) return null;
        const c = self.source[self.position];
        self.position += 1;
        if (c == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
        return c;
    }

    pub fn match(self: *Lexer, expected: u8) bool {
        if (self.peek() != expected) return false;
        _ = self.advance();
        return true;
    }

    pub fn skipWhitespace(self: *Lexer) void {
        while (self.peek()) |c| {
            if (c == ' ' or c == '\t' or c == '\r') {
                _ = self.advance();
            } else {
                break;
            }
        }
    }

    pub fn skipComment(self: *Lexer) void {
        // Skip # comments to end of line
        if (self.peek() == '#') {
            while (self.peek()) |c| {
                if (c == '\n') break;
                _ = self.advance();
            }
        }
    }

    pub fn scanToken(self: *Lexer) Token {
        if (self.skip_whitespace) {
            self.skipWhitespace();
        }
        if (self.skip_comments) {
            self.skipComment();
            if (self.skip_whitespace) {
                self.skipWhitespace();
            }
        }

        const start = self.position;
        const start_line = self.line;
        const start_col = self.column;

        if (self.isAtEnd()) {
            return Token.init(.eof, "", start_line, start_col, start, start);
        }

        const c = self.advance().?;

        // Single character tokens
        const token_type: TokenType = switch (c) {
            '/' => .slash,
            '&' => .ampersand,
            '!' => .exclamation,
            '?' => .question,
            '*' => .star,
            '+' => .plus,
            '.' => .dot,
            '(' => .lparen,
            ')' => .rparen,
            '[' => .lbracket,
            ']' => .rbracket,
            '{' => .lbrace,
            '}' => .rbrace,
            ':' => .colon,
            ';' => .semicolon,
            '\n' => .newline,
            '<' => blk: {
                if (self.match('-')) break :blk .arrow;
                break :blk .invalid;
            },
            '"', '\'' => blk: {
                const quote = c;
                while (self.peek()) |ch| {
                    if (ch == quote) {
                        _ = self.advance();
                        break :blk .string_literal;
                    }
                    if (ch == '\\' and self.peekNext() != null) {
                        _ = self.advance(); // escape char
                    }
                    _ = self.advance();
                }
                break :blk .invalid; // unterminated string
            },
            else => blk: {
                if (isAlpha(c)) {
                    while (self.peek()) |ch| {
                        if (!isAlphaNumeric(ch)) break;
                        _ = self.advance();
                    }
                    break :blk .identifier;
                }
                if (isDigit(c)) {
                    while (self.peek()) |ch| {
                        if (!isDigit(ch)) break;
                        _ = self.advance();
                    }
                    break :blk .number;
                }
                if (c == ' ' or c == '\t' or c == '\r') {
                    while (self.peek()) |ch| {
                        if (ch != ' ' and ch != '\t' and ch != '\r') break;
                        _ = self.advance();
                    }
                    break :blk .whitespace;
                }
                break :blk .invalid;
            },
        };

        return Token.init(token_type, self.source[start..self.position], start_line, start_col, start, self.position);
    }

    pub fn tokenize(self: *Lexer) ![]const Token {
        while (!self.isAtEnd()) {
            const token = self.scanToken();
            if (token.token_type == .eof) break;
            if (self.skip_whitespace and token.token_type == .whitespace) continue;
            if (self.skip_comments and token.token_type == .comment) continue;
            try self.tokens.append(token);
        }
        try self.tokens.append(Token.init(.eof, "", self.line, self.column, self.position, self.position));
        return self.tokens.items;
    }
};

/// Token stream for parser consumption
pub const TokenStream = struct {
    tokens: []const Token,
    position: usize,
    marks: std.ArrayList(usize),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, tokens: []const Token) TokenStream {
        return .{
            .tokens = tokens,
            .position = 0,
            .marks = std.ArrayList(usize).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TokenStream) void {
        self.marks.deinit();
    }

    pub fn current(self: TokenStream) Token {
        if (self.position >= self.tokens.len) {
            return Token.init(.eof, "", 0, 0, 0, 0);
        }
        return self.tokens[self.position];
    }

    pub fn peek(self: TokenStream) Token {
        return self.current();
    }

    pub fn peekNext(self: TokenStream) Token {
        if (self.position + 1 >= self.tokens.len) {
            return Token.init(.eof, "", 0, 0, 0, 0);
        }
        return self.tokens[self.position + 1];
    }

    pub fn advance(self: *TokenStream) Token {
        const token = self.current();
        if (self.position < self.tokens.len) {
            self.position += 1;
        }
        return token;
    }

    pub fn match(self: *TokenStream, expected: TokenType) bool {
        if (self.current().token_type == expected) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    pub fn expect(self: *TokenStream, expected: TokenType) !Token {
        if (self.current().token_type != expected) {
            return error.UnexpectedToken;
        }
        return self.advance();
    }

    pub fn isAtEnd(self: TokenStream) bool {
        return self.current().token_type == .eof;
    }

    pub fn mark(self: *TokenStream) !void {
        try self.marks.append(self.position);
    }

    pub fn reset(self: *TokenStream) void {
        if (self.marks.popOrNull()) |pos| {
            self.position = pos;
        }
    }

    pub fn commit(self: *TokenStream) void {
        _ = self.marks.popOrNull();
    }

    pub fn remaining(self: TokenStream) usize {
        if (self.position >= self.tokens.len) return 0;
        return self.tokens.len - self.position;
    }
};

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isAlphaNumeric(c: u8) bool {
    return isAlpha(c) or isDigit(c);
}

// Tests
test "token_type_is_operator" {
    try std.testing.expect(TokenType.star.isOperator());
    try std.testing.expect(TokenType.plus.isOperator());
    try std.testing.expect(!TokenType.identifier.isOperator());
    try std.testing.expect(!TokenType.lparen.isOperator());
}

test "token_type_is_grouping" {
    try std.testing.expect(TokenType.lparen.isGrouping());
    try std.testing.expect(TokenType.rbracket.isGrouping());
    try std.testing.expect(!TokenType.star.isGrouping());
}

test "token_type_precedence" {
    try std.testing.expect(TokenType.star.precedence() > TokenType.slash.precedence());
    try std.testing.expect(TokenType.plus.precedence() > TokenType.ampersand.precedence());
}

test "token_init_and_length" {
    const token = Token.init(.identifier, "hello", 1, 5, 4, 9);
    try std.testing.expectEqual(@as(usize, 5), token.length());
    try std.testing.expectEqualStrings("hello", token.lexeme);
}

test "token_matches" {
    const token = Token.init(.identifier, "foo", 1, 1, 0, 3);
    try std.testing.expect(token.matches(.identifier));
    try std.testing.expect(!token.matches(.number));
    try std.testing.expect(token.matchesLexeme("foo"));
    try std.testing.expect(!token.matchesLexeme("bar"));
}

test "token_is_eof" {
    const eof_token = Token.init(.eof, "", 1, 1, 0, 0);
    const id_token = Token.init(.identifier, "x", 1, 1, 0, 1);

    try std.testing.expect(eof_token.isEof());
    try std.testing.expect(!id_token.isEof());
}

test "lexer_single_char_tokens" {
    var lexer = Lexer.init(std.testing.allocator, "()[]{}");
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(@as(usize, 7), tokens.len); // 6 + eof
    try std.testing.expect(tokens[0].token_type == .lparen);
    try std.testing.expect(tokens[1].token_type == .rparen);
    try std.testing.expect(tokens[2].token_type == .lbracket);
    try std.testing.expect(tokens[3].token_type == .rbracket);
    try std.testing.expect(tokens[4].token_type == .lbrace);
    try std.testing.expect(tokens[5].token_type == .rbrace);
}

test "lexer_operators" {
    var lexer = Lexer.init(std.testing.allocator, "/ & ! ? * + .");
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    try std.testing.expect(tokens[0].token_type == .slash);
    try std.testing.expect(tokens[1].token_type == .ampersand);
    try std.testing.expect(tokens[2].token_type == .exclamation);
    try std.testing.expect(tokens[3].token_type == .question);
    try std.testing.expect(tokens[4].token_type == .star);
    try std.testing.expect(tokens[5].token_type == .plus);
    try std.testing.expect(tokens[6].token_type == .dot);
}

test "lexer_arrow" {
    var lexer = Lexer.init(std.testing.allocator, "<-");
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    try std.testing.expect(tokens[0].token_type == .arrow);
}

test "lexer_identifier" {
    var lexer = Lexer.init(std.testing.allocator, "foo bar_baz _test");
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    try std.testing.expect(tokens[0].token_type == .identifier);
    try std.testing.expectEqualStrings("foo", tokens[0].lexeme);
    try std.testing.expect(tokens[1].token_type == .identifier);
    try std.testing.expectEqualStrings("bar_baz", tokens[1].lexeme);
    try std.testing.expect(tokens[2].token_type == .identifier);
    try std.testing.expectEqualStrings("_test", tokens[2].lexeme);
}

test "lexer_number" {
    var lexer = Lexer.init(std.testing.allocator, "123 456");
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    try std.testing.expect(tokens[0].token_type == .number);
    try std.testing.expectEqualStrings("123", tokens[0].lexeme);
    try std.testing.expect(tokens[1].token_type == .number);
}

test "lexer_string_literal" {
    var lexer = Lexer.init(std.testing.allocator, "\"hello\" 'world'");
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    try std.testing.expect(tokens[0].token_type == .string_literal);
    try std.testing.expectEqualStrings("\"hello\"", tokens[0].lexeme);
    try std.testing.expect(tokens[1].token_type == .string_literal);
}

test "lexer_line_tracking" {
    var lexer = Lexer.init(std.testing.allocator, "a\nb\nc");
    defer lexer.deinit();
    lexer.skip_whitespace = false;

    const tokens = try lexer.tokenize();
    try std.testing.expectEqual(@as(usize, 1), tokens[0].line);
    try std.testing.expectEqual(@as(usize, 2), tokens[2].line);
    try std.testing.expectEqual(@as(usize, 3), tokens[4].line);
}

test "token_stream_basic" {
    const tokens = [_]Token{
        Token.init(.identifier, "x", 1, 1, 0, 1),
        Token.init(.plus, "+", 1, 2, 1, 2),
        Token.init(.number, "5", 1, 3, 2, 3),
        Token.init(.eof, "", 1, 4, 3, 3),
    };
    var stream = TokenStream.init(std.testing.allocator, &tokens);
    defer stream.deinit();

    try std.testing.expect(stream.current().token_type == .identifier);
    _ = stream.advance();
    try std.testing.expect(stream.current().token_type == .plus);
}

test "token_stream_match" {
    const tokens = [_]Token{
        Token.init(.identifier, "x", 1, 1, 0, 1),
        Token.init(.eof, "", 1, 2, 1, 1),
    };
    var stream = TokenStream.init(std.testing.allocator, &tokens);
    defer stream.deinit();

    try std.testing.expect(stream.match(.identifier));
    try std.testing.expect(!stream.match(.identifier));
}

test "token_stream_expect" {
    const tokens = [_]Token{
        Token.init(.lparen, "(", 1, 1, 0, 1),
        Token.init(.eof, "", 1, 2, 1, 1),
    };
    var stream = TokenStream.init(std.testing.allocator, &tokens);
    defer stream.deinit();

    const token = try stream.expect(.lparen);
    try std.testing.expect(token.token_type == .lparen);

    try std.testing.expectError(error.UnexpectedToken, stream.expect(.identifier));
}

test "token_stream_mark_reset" {
    const tokens = [_]Token{
        Token.init(.identifier, "a", 1, 1, 0, 1),
        Token.init(.identifier, "b", 1, 2, 1, 2),
        Token.init(.identifier, "c", 1, 3, 2, 3),
        Token.init(.eof, "", 1, 4, 3, 3),
    };
    var stream = TokenStream.init(std.testing.allocator, &tokens);
    defer stream.deinit();

    _ = stream.advance(); // a
    try stream.mark();
    _ = stream.advance(); // b
    _ = stream.advance(); // c

    try std.testing.expectEqualStrings("c", stream.peek().lexeme);
    stream.reset();
    try std.testing.expectEqualStrings("b", stream.peek().lexeme);
}

test "token_stream_commit" {
    const tokens = [_]Token{
        Token.init(.identifier, "x", 1, 1, 0, 1),
        Token.init(.eof, "", 1, 2, 1, 1),
    };
    var stream = TokenStream.init(std.testing.allocator, &tokens);
    defer stream.deinit();

    try stream.mark();
    _ = stream.advance();
    stream.commit();
    stream.reset(); // Should not go back since we committed
    try std.testing.expect(stream.current().token_type == .eof);
}

test "token_stream_remaining" {
    const tokens = [_]Token{
        Token.init(.identifier, "a", 1, 1, 0, 1),
        Token.init(.identifier, "b", 1, 2, 1, 2),
        Token.init(.eof, "", 1, 3, 2, 2),
    };
    var stream = TokenStream.init(std.testing.allocator, &tokens);
    defer stream.deinit();

    try std.testing.expectEqual(@as(usize, 3), stream.remaining());
    _ = stream.advance();
    try std.testing.expectEqual(@as(usize, 2), stream.remaining());
}
