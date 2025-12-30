//! SQL Lexer - tokenizes SQL strings into tokens.
//!
//! Supports the SQL subset needed for LanceQL:
//! SELECT, FROM, WHERE, GROUP BY, HAVING, ORDER BY, LIMIT, ASC, DESC,
//! AND, OR, NOT, aggregate functions, comparison operators.

const std = @import("std");

/// Token types for SQL lexing.
pub const TokenType = enum {
    // Keywords
    select,
    from,
    where,
    group,
    by,
    having,
    order,
    limit,
    offset,
    asc,
    desc,
    and_,
    or_,
    not,
    as,
    distinct,
    is,
    null_,
    true_,
    false_,
    in_,
    between,

    // Literals
    integer,
    float,
    string,
    identifier,

    // Operators
    star, // *
    comma, // ,
    dot, // .
    lparen, // (
    rparen, // )
    eq, // =
    ne, // != or <>
    lt, // <
    le, // <=
    gt, // >
    ge, // >=
    plus, // +
    minus, // -
    slash, // /

    // End
    eof,
    invalid,
};

/// A token with its type and value.
pub const Token = struct {
    type: TokenType,
    value: []const u8,
    pos: usize,

    pub fn format(
        self: Token,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}({s})", .{ @tagName(self.type), self.value });
    }
};

/// SQL Lexer.
pub const Lexer = struct {
    input: []const u8,
    pos: usize = 0,

    const Self = @This();

    pub fn init(input: []const u8) Self {
        return .{ .input = input };
    }

    /// Get the next token.
    pub fn next(self: *Self) Token {
        self.skipWhitespace();

        if (self.pos >= self.input.len) {
            return .{ .type = .eof, .value = "", .pos = self.pos };
        }

        const start = self.pos;
        const c = self.input[self.pos];

        // Single character tokens
        switch (c) {
            '*' => return self.singleChar(.star),
            ',' => return self.singleChar(.comma),
            '.' => return self.singleChar(.dot),
            '(' => return self.singleChar(.lparen),
            ')' => return self.singleChar(.rparen),
            '+' => return self.singleChar(.plus),
            '-' => {
                // Check for negative number
                if (self.pos + 1 < self.input.len and std.ascii.isDigit(self.input[self.pos + 1])) {
                    return self.scanNumber();
                }
                return self.singleChar(.minus);
            },
            '/' => return self.singleChar(.slash),
            '=' => return self.singleChar(.eq),
            '<' => {
                if (self.peek(1) == '=') {
                    self.pos += 2;
                    return .{ .type = .le, .value = "<=", .pos = start };
                } else if (self.peek(1) == '>') {
                    self.pos += 2;
                    return .{ .type = .ne, .value = "<>", .pos = start };
                }
                return self.singleChar(.lt);
            },
            '>' => {
                if (self.peek(1) == '=') {
                    self.pos += 2;
                    return .{ .type = .ge, .value = ">=", .pos = start };
                }
                return self.singleChar(.gt);
            },
            '!' => {
                if (self.peek(1) == '=') {
                    self.pos += 2;
                    return .{ .type = .ne, .value = "!=", .pos = start };
                }
                self.pos += 1;
                return .{ .type = .invalid, .value = self.input[start..self.pos], .pos = start };
            },
            '\'' => return self.scanString(),
            '"' => return self.scanQuotedIdentifier(),
            else => {},
        }

        // Numbers
        if (std.ascii.isDigit(c)) {
            return self.scanNumber();
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(c) or c == '_') {
            return self.scanIdentifier();
        }

        // Unknown character
        self.pos += 1;
        return .{ .type = .invalid, .value = self.input[start..self.pos], .pos = start };
    }

    /// Peek at a character at offset from current position.
    fn peek(self: *Self, offset: usize) u8 {
        const idx = self.pos + offset;
        if (idx >= self.input.len) return 0;
        return self.input[idx];
    }

    fn singleChar(self: *Self, token_type: TokenType) Token {
        const start = self.pos;
        self.pos += 1;
        return .{ .type = token_type, .value = self.input[start..self.pos], .pos = start };
    }

    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.input.len and std.ascii.isWhitespace(self.input[self.pos])) {
            self.pos += 1;
        }
    }

    fn scanNumber(self: *Self) Token {
        const start = self.pos;
        var is_float = false;

        // Handle negative sign
        if (self.input[self.pos] == '-') {
            self.pos += 1;
        }

        // Integer part
        while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) {
            self.pos += 1;
        }

        // Decimal part
        if (self.pos < self.input.len and self.input[self.pos] == '.') {
            is_float = true;
            self.pos += 1;
            while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) {
                self.pos += 1;
            }
        }

        // Exponent part
        if (self.pos < self.input.len and (self.input[self.pos] == 'e' or self.input[self.pos] == 'E')) {
            is_float = true;
            self.pos += 1;
            if (self.pos < self.input.len and (self.input[self.pos] == '+' or self.input[self.pos] == '-')) {
                self.pos += 1;
            }
            while (self.pos < self.input.len and std.ascii.isDigit(self.input[self.pos])) {
                self.pos += 1;
            }
        }

        return .{
            .type = if (is_float) .float else .integer,
            .value = self.input[start..self.pos],
            .pos = start,
        };
    }

    fn scanString(self: *Self) Token {
        const start = self.pos;
        self.pos += 1; // Skip opening quote

        while (self.pos < self.input.len) {
            if (self.input[self.pos] == '\'') {
                // Check for escaped quote ''
                if (self.pos + 1 < self.input.len and self.input[self.pos + 1] == '\'') {
                    self.pos += 2;
                    continue;
                }
                self.pos += 1;
                break;
            }
            self.pos += 1;
        }

        // Return without quotes
        return .{
            .type = .string,
            .value = self.input[start + 1 .. self.pos - 1],
            .pos = start,
        };
    }

    fn scanQuotedIdentifier(self: *Self) Token {
        const start = self.pos;
        self.pos += 1; // Skip opening quote

        while (self.pos < self.input.len and self.input[self.pos] != '"') {
            self.pos += 1;
        }

        if (self.pos < self.input.len) {
            self.pos += 1; // Skip closing quote
        }

        // Return without quotes
        return .{
            .type = .identifier,
            .value = self.input[start + 1 .. self.pos - 1],
            .pos = start,
        };
    }

    fn scanIdentifier(self: *Self) Token {
        const start = self.pos;

        while (self.pos < self.input.len) {
            const ch = self.input[self.pos];
            if (std.ascii.isAlphanumeric(ch) or ch == '_') {
                self.pos += 1;
            } else {
                break;
            }
        }

        const value = self.input[start..self.pos];
        const token_type = getKeyword(value) orelse .identifier;

        return .{ .type = token_type, .value = value, .pos = start };
    }

    fn getKeyword(value: []const u8) ?TokenType {
        const keywords = std.StaticStringMap(TokenType).initComptime(.{
            .{ "SELECT", .select },
            .{ "FROM", .from },
            .{ "WHERE", .where },
            .{ "GROUP", .group },
            .{ "BY", .by },
            .{ "HAVING", .having },
            .{ "ORDER", .order },
            .{ "LIMIT", .limit },
            .{ "OFFSET", .offset },
            .{ "ASC", .asc },
            .{ "DESC", .desc },
            .{ "AND", .and_ },
            .{ "OR", .or_ },
            .{ "NOT", .not },
            .{ "AS", .as },
            .{ "DISTINCT", .distinct },
            .{ "IS", .is },
            .{ "NULL", .null_ },
            .{ "TRUE", .true_ },
            .{ "FALSE", .false_ },
            .{ "IN", .in_ },
            .{ "BETWEEN", .between },
        });

        // Convert to uppercase for case-insensitive matching
        var upper_buf: [32]u8 = undefined;
        if (value.len > upper_buf.len) return null;

        for (value, 0..) |c, i| {
            upper_buf[i] = std.ascii.toUpper(c);
        }

        return keywords.get(upper_buf[0..value.len]);
    }

    /// Peek at the next token without consuming it.
    pub fn peekToken(self: *Self) Token {
        const saved_pos = self.pos;
        const token = self.next();
        self.pos = saved_pos;
        return token;
    }

    /// Check if at end of input.
    pub fn isEof(self: *Self) bool {
        self.skipWhitespace();
        return self.pos >= self.input.len;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Lexer basic tokens" {
    var lexer = Lexer.init("SELECT * FROM t");

    var tok = lexer.next();
    try std.testing.expectEqual(tok.type, .select);

    tok = lexer.next();
    try std.testing.expectEqual(tok.type, .star);

    tok = lexer.next();
    try std.testing.expectEqual(tok.type, .from);

    tok = lexer.next();
    try std.testing.expectEqual(tok.type, .identifier);
    try std.testing.expectEqualStrings("t", tok.value);

    tok = lexer.next();
    try std.testing.expectEqual(tok.type, .eof);
}

test "Lexer numbers" {
    var lexer = Lexer.init("42 3.14 -10 1e5");

    var tok = lexer.next();
    try std.testing.expectEqual(tok.type, .integer);
    try std.testing.expectEqualStrings("42", tok.value);

    tok = lexer.next();
    try std.testing.expectEqual(tok.type, .float);
    try std.testing.expectEqualStrings("3.14", tok.value);

    tok = lexer.next();
    try std.testing.expectEqual(tok.type, .integer);
    try std.testing.expectEqualStrings("-10", tok.value);

    tok = lexer.next();
    try std.testing.expectEqual(tok.type, .float);
    try std.testing.expectEqualStrings("1e5", tok.value);
}

test "Lexer strings" {
    var lexer = Lexer.init("'hello' 'world''s'");

    var tok = lexer.next();
    try std.testing.expectEqual(tok.type, .string);
    try std.testing.expectEqualStrings("hello", tok.value);

    tok = lexer.next();
    try std.testing.expectEqual(tok.type, .string);
    try std.testing.expectEqualStrings("world''s", tok.value);
}

test "Lexer operators" {
    var lexer = Lexer.init("= != <> < <= > >= + - * /");

    try std.testing.expectEqual(lexer.next().type, .eq);
    try std.testing.expectEqual(lexer.next().type, .ne);
    try std.testing.expectEqual(lexer.next().type, .ne);
    try std.testing.expectEqual(lexer.next().type, .lt);
    try std.testing.expectEqual(lexer.next().type, .le);
    try std.testing.expectEqual(lexer.next().type, .gt);
    try std.testing.expectEqual(lexer.next().type, .ge);
    try std.testing.expectEqual(lexer.next().type, .plus);
    try std.testing.expectEqual(lexer.next().type, .minus);
    try std.testing.expectEqual(lexer.next().type, .star);
    try std.testing.expectEqual(lexer.next().type, .slash);
}

test "Lexer case insensitive keywords" {
    var lexer = Lexer.init("select SELECT Select");

    try std.testing.expectEqual(lexer.next().type, .select);
    try std.testing.expectEqual(lexer.next().type, .select);
    try std.testing.expectEqual(lexer.next().type, .select);
}

test "Lexer full query" {
    var lexer = Lexer.init("SELECT id, COUNT(*) FROM users WHERE age > 18 GROUP BY id LIMIT 10");

    const expected = [_]TokenType{
        .select,     .identifier, .comma,  .identifier, .lparen,
        .star,       .rparen,     .from,   .identifier, .where,
        .identifier, .gt,         .integer, .group,      .by,
        .identifier, .limit,      .integer, .eof,
    };

    for (expected) |exp| {
        const tok = lexer.next();
        try std.testing.expectEqual(exp, tok.type);
    }
}
