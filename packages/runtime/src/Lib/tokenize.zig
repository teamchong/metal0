//! Python 'tokenize' module - Tokenizer for Python source
//!
//! Provides a lexical scanner for Python source code.
//!
//! Mirrors: CPython Lib/tokenize.py

const std = @import("std");

// ============================================================================
// Token Types
// ============================================================================

/// Token types matching Python's token module
pub const TokenType = enum(u8) {
    ENDMARKER = 0,
    NAME = 1,
    NUMBER = 2,
    STRING = 3,
    NEWLINE = 4,
    INDENT = 5,
    DEDENT = 6,
    LPAR = 7, // (
    RPAR = 8, // )
    LSQB = 9, // [
    RSQB = 10, // ]
    COLON = 11, // :
    COMMA = 12, // ,
    SEMI = 13, // ;
    PLUS = 14, // +
    MINUS = 15, // -
    STAR = 16, // *
    SLASH = 17, // /
    VBAR = 18, // |
    AMPER = 19, // &
    LESS = 20, // <
    GREATER = 21, // >
    EQUAL = 22, // =
    DOT = 23, // .
    PERCENT = 24, // %
    LBRACE = 25, // {
    RBRACE = 26, // }
    EQEQUAL = 27, // ==
    NOTEQUAL = 28, // !=
    LESSEQUAL = 29, // <=
    GREATEREQUAL = 30, // >=
    TILDE = 31, // ~
    CIRCUMFLEX = 32, // ^
    LEFTSHIFT = 33, // <<
    RIGHTSHIFT = 34, // >>
    DOUBLESTAR = 35, // **
    PLUSEQUAL = 36, // +=
    MINEQUAL = 37, // -=
    STAREQUAL = 38, // *=
    SLASHEQUAL = 39, // /=
    PERCENTEQUAL = 40, // %=
    AMPEREQUAL = 41, // &=
    VBAREQUAL = 42, // |=
    CIRCUMFLEXEQUAL = 43, // ^=
    LEFTSHIFTEQUAL = 44, // <<=
    RIGHTSHIFTEQUAL = 45, // >>=
    DOUBLESTAREQUAL = 46, // **=
    DOUBLESLASH = 47, // //
    DOUBLESLASHEQUAL = 48, // //=
    AT = 49, // @
    ATEQUAL = 50, // @=
    RARROW = 51, // ->
    ELLIPSIS = 52, // ...
    COLONEQUAL = 53, // :=
    EXCLAMATION = 54, // !
    OP = 55,
    AWAIT = 56,
    ASYNC = 57,
    TYPE_IGNORE = 58,
    TYPE_COMMENT = 59,
    SOFT_KEYWORD = 60,
    FSTRING_START = 61,
    FSTRING_MIDDLE = 62,
    FSTRING_END = 63,
    COMMENT = 64,
    NL = 65, // Non-terminating newline
    ERRORTOKEN = 66,
    ENCODING = 67,
    N_TOKENS = 68,

    pub fn name(self: TokenType) []const u8 {
        return @tagName(self);
    }
};

// ============================================================================
// Token Info
// ============================================================================

/// Token position
pub const Position = struct {
    line: u32,
    col: u32,

    pub fn init(line: u32, col: u32) Position {
        return .{ .line = line, .col = col };
    }
};

/// Complete token information
pub const TokenInfo = struct {
    type: TokenType,
    string: []const u8,
    start: Position,
    end: Position,
    line: []const u8,

    pub fn init(
        token_type: TokenType,
        string: []const u8,
        start: Position,
        end: Position,
        line: []const u8,
    ) TokenInfo {
        return .{
            .type = token_type,
            .string = string,
            .start = start,
            .end = end,
            .line = line,
        };
    }

    pub fn exactType(self: *const TokenInfo) TokenType {
        if (self.type == .OP or self.type == .NAME) {
            // Check for exact operator or keyword
            return EXACT_TOKEN_TYPES.get(self.string) orelse self.type;
        }
        return self.type;
    }
};

// ============================================================================
// Exact Token Types Map
// ============================================================================

const ExactTokenMap = std.StaticStringMap(TokenType);

const EXACT_TOKEN_TYPES = ExactTokenMap.initComptime(.{
    .{ "(", .LPAR },
    .{ ")", .RPAR },
    .{ "[", .LSQB },
    .{ "]", .RSQB },
    .{ ":", .COLON },
    .{ ",", .COMMA },
    .{ ";", .SEMI },
    .{ "+", .PLUS },
    .{ "-", .MINUS },
    .{ "*", .STAR },
    .{ "/", .SLASH },
    .{ "|", .VBAR },
    .{ "&", .AMPER },
    .{ "<", .LESS },
    .{ ">", .GREATER },
    .{ "=", .EQUAL },
    .{ ".", .DOT },
    .{ "%", .PERCENT },
    .{ "{", .LBRACE },
    .{ "}", .RBRACE },
    .{ "==", .EQEQUAL },
    .{ "!=", .NOTEQUAL },
    .{ "<=", .LESSEQUAL },
    .{ ">=", .GREATEREQUAL },
    .{ "~", .TILDE },
    .{ "^", .CIRCUMFLEX },
    .{ "<<", .LEFTSHIFT },
    .{ ">>", .RIGHTSHIFT },
    .{ "**", .DOUBLESTAR },
    .{ "+=", .PLUSEQUAL },
    .{ "-=", .MINEQUAL },
    .{ "*=", .STAREQUAL },
    .{ "/=", .SLASHEQUAL },
    .{ "%=", .PERCENTEQUAL },
    .{ "&=", .AMPEREQUAL },
    .{ "|=", .VBAREQUAL },
    .{ "^=", .CIRCUMFLEXEQUAL },
    .{ "<<=", .LEFTSHIFTEQUAL },
    .{ ">>=", .RIGHTSHIFTEQUAL },
    .{ "**=", .DOUBLESTAREQUAL },
    .{ "//", .DOUBLESLASH },
    .{ "//=", .DOUBLESLASHEQUAL },
    .{ "@", .AT },
    .{ "@=", .ATEQUAL },
    .{ "->", .RARROW },
    .{ "...", .ELLIPSIS },
    .{ ":=", .COLONEQUAL },
    .{ "!", .EXCLAMATION },
});

// ============================================================================
// Tokenizer
// ============================================================================

pub const Tokenizer = struct {
    const Self = @This();

    source: []const u8,
    pos: usize,
    line: u32,
    col: u32,
    indent_stack: std.ArrayList(u32),
    allocator: std.mem.Allocator,
    at_bol: bool, // At beginning of line
    pending_dedents: u32,
    encoding: []const u8,
    done: bool,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Self {
        var indent_stack = std.ArrayList(u32).init(allocator);
        indent_stack.append(0) catch {};

        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .col = 0,
            .indent_stack = indent_stack,
            .allocator = allocator,
            .at_bol = true,
            .pending_dedents = 0,
            .encoding = "utf-8",
            .done = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.indent_stack.deinit();
    }

    /// Get the next token
    pub fn next(self: *Self) ?TokenInfo {
        if (self.done) return null;

        // Handle pending dedents
        if (self.pending_dedents > 0) {
            self.pending_dedents -= 1;
            return TokenInfo.init(
                .DEDENT,
                "",
                Position.init(self.line, self.col),
                Position.init(self.line, self.col),
                self.currentLine(),
            );
        }

        // Skip to first non-whitespace at BOL for indent handling
        if (self.at_bol) {
            const indent = self.countIndent();
            self.at_bol = false;

            const current_indent = self.indent_stack.items[self.indent_stack.items.len - 1];
            if (indent > current_indent) {
                self.indent_stack.append(indent) catch {};
                return TokenInfo.init(
                    .INDENT,
                    "",
                    Position.init(self.line, 0),
                    Position.init(self.line, indent),
                    self.currentLine(),
                );
            } else if (indent < current_indent) {
                // Count dedents needed
                while (self.indent_stack.items.len > 1 and
                    self.indent_stack.items[self.indent_stack.items.len - 1] > indent)
                {
                    _ = self.indent_stack.pop();
                    self.pending_dedents += 1;
                }
                if (self.pending_dedents > 0) {
                    self.pending_dedents -= 1;
                    return TokenInfo.init(
                        .DEDENT,
                        "",
                        Position.init(self.line, self.col),
                        Position.init(self.line, self.col),
                        self.currentLine(),
                    );
                }
            }
        }

        // Skip whitespace (not at BOL)
        self.skipWhitespace();

        if (self.pos >= self.source.len) {
            self.done = true;
            return TokenInfo.init(
                .ENDMARKER,
                "",
                Position.init(self.line, self.col),
                Position.init(self.line, self.col),
                "",
            );
        }

        const start_pos = Position.init(self.line, self.col);
        const c = self.source[self.pos];

        // Comment
        if (c == '#') {
            const start = self.pos;
            while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                self.pos += 1;
                self.col += 1;
            }
            return TokenInfo.init(
                .COMMENT,
                self.source[start..self.pos],
                start_pos,
                Position.init(self.line, self.col),
                self.currentLine(),
            );
        }

        // Newline
        if (c == '\n') {
            self.pos += 1;
            self.line += 1;
            self.col = 0;
            self.at_bol = true;
            return TokenInfo.init(
                .NEWLINE,
                "\n",
                start_pos,
                Position.init(self.line, 0),
                self.currentLine(),
            );
        }

        // String
        if (c == '"' or c == '\'') {
            return self.readString(start_pos);
        }

        // Number
        if (std.ascii.isDigit(c)) {
            return self.readNumber(start_pos);
        }

        // Name/Keyword
        if (std.ascii.isAlphabetic(c) or c == '_') {
            return self.readName(start_pos);
        }

        // Operators
        return self.readOperator(start_pos);
    }

    fn countIndent(self: *Self) u32 {
        var indent: u32 = 0;
        while (self.pos < self.source.len) {
            if (self.source[self.pos] == ' ') {
                indent += 1;
                self.pos += 1;
                self.col += 1;
            } else if (self.source[self.pos] == '\t') {
                indent = (indent + 8) & ~@as(u32, 7);
                self.pos += 1;
                self.col += 1;
            } else {
                break;
            }
        }
        return indent;
    }

    fn skipWhitespace(self: *Self) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\r') {
                self.pos += 1;
                self.col += 1;
            } else {
                break;
            }
        }
    }

    fn readString(self: *Self, start_pos: Position) TokenInfo {
        const quote = self.source[self.pos];
        const start = self.pos;
        self.pos += 1;
        self.col += 1;

        // Check for triple quotes
        const triple = if (self.pos + 1 < self.source.len and
            self.source[self.pos] == quote and
            self.source[self.pos + 1] == quote)
        blk: {
            self.pos += 2;
            self.col += 2;
            break :blk true;
        } else false;

        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '\\' and self.pos + 1 < self.source.len) {
                self.pos += 2;
                self.col += 2;
            } else if (c == '\n') {
                if (!triple) break;
                self.pos += 1;
                self.line += 1;
                self.col = 0;
            } else if (c == quote) {
                if (triple) {
                    if (self.pos + 2 < self.source.len and
                        self.source[self.pos + 1] == quote and
                        self.source[self.pos + 2] == quote)
                    {
                        self.pos += 3;
                        self.col += 3;
                        break;
                    }
                } else {
                    self.pos += 1;
                    self.col += 1;
                    break;
                }
                self.pos += 1;
                self.col += 1;
            } else {
                self.pos += 1;
                self.col += 1;
            }
        }

        return TokenInfo.init(
            .STRING,
            self.source[start..self.pos],
            start_pos,
            Position.init(self.line, self.col),
            self.currentLine(),
        );
    }

    fn readNumber(self: *Self, start_pos: Position) TokenInfo {
        const start = self.pos;

        // Handle 0x, 0o, 0b prefixes
        if (self.source[self.pos] == '0' and self.pos + 1 < self.source.len) {
            const next_char = self.source[self.pos + 1];
            if (next_char == 'x' or next_char == 'X' or
                next_char == 'o' or next_char == 'O' or
                next_char == 'b' or next_char == 'B')
            {
                self.pos += 2;
                self.col += 2;
            }
        }

        // Integer or float part
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isAlphanumeric(c) or c == '_' or c == '.') {
                if (c == '.' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '.') {
                    break; // Ellipsis
                }
                self.pos += 1;
                self.col += 1;
            } else {
                break;
            }
        }

        // Exponent
        if (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == 'e' or c == 'E') {
                self.pos += 1;
                self.col += 1;
                if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
                    self.pos += 1;
                    self.col += 1;
                }
                while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
                    self.pos += 1;
                    self.col += 1;
                }
            }
        }

        // Complex suffix
        if (self.pos < self.source.len and (self.source[self.pos] == 'j' or self.source[self.pos] == 'J')) {
            self.pos += 1;
            self.col += 1;
        }

        return TokenInfo.init(
            .NUMBER,
            self.source[start..self.pos],
            start_pos,
            Position.init(self.line, self.col),
            self.currentLine(),
        );
    }

    fn readName(self: *Self, start_pos: Position) TokenInfo {
        const start = self.pos;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isAlphanumeric(c) or c == '_') {
                self.pos += 1;
                self.col += 1;
            } else {
                break;
            }
        }

        return TokenInfo.init(
            .NAME,
            self.source[start..self.pos],
            start_pos,
            Position.init(self.line, self.col),
            self.currentLine(),
        );
    }

    fn readOperator(self: *Self, start_pos: Position) TokenInfo {
        const start = self.pos;

        // Try 3-char operators
        if (self.pos + 2 < self.source.len) {
            const three = self.source[self.pos .. self.pos + 3];
            if (EXACT_TOKEN_TYPES.get(three)) |_| {
                self.pos += 3;
                self.col += 3;
                return TokenInfo.init(
                    .OP,
                    self.source[start..self.pos],
                    start_pos,
                    Position.init(self.line, self.col),
                    self.currentLine(),
                );
            }
        }

        // Try 2-char operators
        if (self.pos + 1 < self.source.len) {
            const two = self.source[self.pos .. self.pos + 2];
            if (EXACT_TOKEN_TYPES.get(two)) |_| {
                self.pos += 2;
                self.col += 2;
                return TokenInfo.init(
                    .OP,
                    self.source[start..self.pos],
                    start_pos,
                    Position.init(self.line, self.col),
                    self.currentLine(),
                );
            }
        }

        // Single char operator
        self.pos += 1;
        self.col += 1;
        return TokenInfo.init(
            .OP,
            self.source[start..self.pos],
            start_pos,
            Position.init(self.line, self.col),
            self.currentLine(),
        );
    }

    fn currentLine(self: *Self) []const u8 {
        // Find start of current line
        var line_start = self.pos;
        while (line_start > 0 and self.source[line_start - 1] != '\n') {
            line_start -= 1;
        }

        // Find end of current line
        var line_end = self.pos;
        while (line_end < self.source.len and self.source[line_end] != '\n') {
            line_end += 1;
        }

        return self.source[line_start..line_end];
    }

    /// Reset tokenizer to beginning
    pub fn reset(self: *Self) void {
        self.pos = 0;
        self.line = 1;
        self.col = 0;
        self.at_bol = true;
        self.pending_dedents = 0;
        self.done = false;
        self.indent_stack.clearRetainingCapacity();
        self.indent_stack.append(0) catch {};
    }
};

// ============================================================================
// Module-Level Functions
// ============================================================================

/// Tokenize source code
pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) ![]TokenInfo {
    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    var tokens = std.ArrayList(TokenInfo).init(allocator);
    errdefer tokens.deinit();

    while (tokenizer.next()) |token| {
        try tokens.append(token);
    }

    return tokens.toOwnedSlice();
}

/// Generate tokens from readline function
pub fn generate_tokens(allocator: std.mem.Allocator, readline: *const fn () ?[]const u8) ![]TokenInfo {
    var source = std.ArrayList(u8).init(allocator);
    defer source.deinit();

    while (readline()) |line| {
        try source.appendSlice(line);
        try source.append('\n');
    }

    return tokenize(allocator, source.items);
}

/// Detect encoding from source
pub fn detect_encoding(source: []const u8) []const u8 {
    // Check for BOM
    if (source.len >= 3 and
        source[0] == 0xEF and source[1] == 0xBB and source[2] == 0xBF)
    {
        return "utf-8-sig";
    }

    // Check for encoding declaration in first two lines
    var line_count: u32 = 0;
    var pos: usize = 0;
    while (pos < source.len and line_count < 2) {
        const line_start = pos;
        while (pos < source.len and source[pos] != '\n') {
            pos += 1;
        }
        const line = source[line_start..pos];

        // Look for coding: or coding=
        if (std.mem.indexOf(u8, line, "coding")) |idx| {
            var enc_start = idx + 6;
            // Skip : or =
            while (enc_start < line.len and (line[enc_start] == ':' or line[enc_start] == '=' or line[enc_start] == ' ')) {
                enc_start += 1;
            }
            var enc_end = enc_start;
            while (enc_end < line.len and (std.ascii.isAlphanumeric(line[enc_end]) or line[enc_end] == '-' or line[enc_end] == '_')) {
                enc_end += 1;
            }
            if (enc_end > enc_start) {
                return line[enc_start..enc_end];
            }
        }

        if (pos < source.len) pos += 1;
        line_count += 1;
    }

    return "utf-8";
}

/// Untokenize tokens back to source
pub fn untokenize(allocator: std.mem.Allocator, tokens: []const TokenInfo) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var prev_row: u32 = 1;
    var prev_col: u32 = 0;

    for (tokens) |token| {
        // Add newlines if needed
        while (prev_row < token.start.line) {
            try result.append('\n');
            prev_row += 1;
            prev_col = 0;
        }

        // Add spaces if needed
        while (prev_col < token.start.col) {
            try result.append(' ');
            prev_col += 1;
        }

        // Add token string
        try result.appendSlice(token.string);
        prev_col = token.end.col;
        prev_row = token.end.line;
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Token Name Functions
// ============================================================================

/// Get name of token type
pub fn tok_name(tok_type: TokenType) []const u8 {
    return tok_type.name();
}

// ============================================================================
// Tests
// ============================================================================

test "tokenize simple" {
    const allocator = std.testing.allocator;
    const source = "x = 1";
    const tokens = try tokenize(allocator, source);
    defer allocator.free(tokens);

    try std.testing.expect(tokens.len >= 4);
    try std.testing.expectEqual(TokenType.NAME, tokens[0].type);
    try std.testing.expectEqualStrings("x", tokens[0].string);
}

test "tokenize string" {
    const allocator = std.testing.allocator;
    const source = "\"hello\"";
    const tokens = try tokenize(allocator, source);
    defer allocator.free(tokens);

    try std.testing.expect(tokens.len >= 1);
    try std.testing.expectEqual(TokenType.STRING, tokens[0].type);
}

test "tokenize number" {
    const allocator = std.testing.allocator;
    const source = "42 3.14 0xFF";
    const tokens = try tokenize(allocator, source);
    defer allocator.free(tokens);

    try std.testing.expect(tokens.len >= 3);
    try std.testing.expectEqual(TokenType.NUMBER, tokens[0].type);
    try std.testing.expectEqual(TokenType.NUMBER, tokens[1].type);
    try std.testing.expectEqual(TokenType.NUMBER, tokens[2].type);
}

test "detect_encoding" {
    try std.testing.expectEqualStrings("utf-8", detect_encoding("print('hello')"));
    try std.testing.expectEqualStrings("utf-8-sig", detect_encoding("\xEF\xBB\xBFprint('hello')"));
}

test "TokenType name" {
    try std.testing.expectEqualStrings("NAME", TokenType.NAME.name());
    try std.testing.expectEqualStrings("NUMBER", TokenType.NUMBER.name());
}
