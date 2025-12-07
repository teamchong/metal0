/// Python-tokenize - Python Tokenizer
/// Mirrors cpython/Python/Python-tokenize.c
///
/// Low-level tokenization of Python source code.
/// Converts source text into a stream of tokens.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Token Types
// ============================================================================

/// Token type enumeration
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
    TSTRING_START = 64, // template string
    TSTRING_MIDDLE = 65,
    TSTRING_END = 66,
    COMMENT = 67,
    NL = 68, // non-terminating newline
    ERRORTOKEN = 69,
    ENCODING = 70,
    N_TOKENS = 71,
};

/// Token structure
pub const Token = struct {
    type_: TokenType,
    start: Position,
    end: Position,
    string: []const u8,
    /// For string/fstring tokens, the string prefix
    prefix: []const u8 = "",
};

/// Source position
pub const Position = struct {
    line: u32 = 1,
    column: u32 = 0,
    offset: usize = 0,
};

// ============================================================================
// Tokenizer State
// ============================================================================

/// Tokenizer state
pub const Tokenizer = struct {
    const Self = @This();

    allocator: Allocator,
    source: []const u8,
    pos: usize = 0,
    line: u32 = 1,
    col: u32 = 0,
    /// Indentation stack
    indent_stack: std.ArrayList(u32),
    /// Pending dedents to emit
    pending_dedents: u32 = 0,
    /// Bracket nesting level
    bracket_level: u32 = 0,
    /// At beginning of line
    at_bol: bool = true,
    /// In f-string
    in_fstring: bool = false,
    /// Error message if any
    error_msg: ?[]const u8 = null,

    pub fn init(allocator: Allocator, source: []const u8) Self {
        var self = Self{
            .allocator = allocator,
            .source = source,
            .indent_stack = std.ArrayList(u32).init(allocator),
        };
        // Start with 0 indentation
        self.indent_stack.append(0) catch {};
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.indent_stack.deinit();
    }

    /// Get next token
    pub fn nextToken(self: *Self) !Token {
        // Emit pending dedents
        if (self.pending_dedents > 0) {
            self.pending_dedents -= 1;
            return Token{
                .type_ = .DEDENT,
                .start = self.currentPos(),
                .end = self.currentPos(),
                .string = "",
            };
        }

        // Skip whitespace and handle indentation at BOL
        if (self.at_bol and self.bracket_level == 0) {
            try self.handleIndentation();
            if (self.pending_dedents > 0) {
                self.pending_dedents -= 1;
                return Token{
                    .type_ = .DEDENT,
                    .start = self.currentPos(),
                    .end = self.currentPos(),
                    .string = "",
                };
            }
        }

        // Skip spaces (not at BOL)
        while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t')) {
            self.advance();
        }

        // End of input
        if (self.pos >= self.source.len) {
            // Emit final dedents
            if (self.indent_stack.items.len > 1) {
                _ = self.indent_stack.pop();
                self.pending_dedents = @intCast(self.indent_stack.items.len - 1);
                if (self.pending_dedents > 0) {
                    self.pending_dedents -= 1;
                    return Token{
                        .type_ = .DEDENT,
                        .start = self.currentPos(),
                        .end = self.currentPos(),
                        .string = "",
                    };
                }
            }
            return Token{
                .type_ = .ENDMARKER,
                .start = self.currentPos(),
                .end = self.currentPos(),
                .string = "",
            };
        }

        const start = self.currentPos();
        const c = self.source[self.pos];

        // Comment
        if (c == '#') {
            const comment_start = self.pos;
            while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                self.advance();
            }
            return Token{
                .type_ = .COMMENT,
                .start = start,
                .end = self.currentPos(),
                .string = self.source[comment_start..self.pos],
            };
        }

        // Newline
        if (c == '\n') {
            self.advance();
            self.at_bol = true;
            if (self.bracket_level > 0) {
                return Token{
                    .type_ = .NL,
                    .start = start,
                    .end = self.currentPos(),
                    .string = "\n",
                };
            }
            return Token{
                .type_ = .NEWLINE,
                .start = start,
                .end = self.currentPos(),
                .string = "\n",
            };
        }

        self.at_bol = false;

        // String
        if (c == '"' or c == '\'') {
            return self.readString(start);
        }

        // String with prefix
        if (isStringPrefix(c)) {
            return self.readPrefixedString(start);
        }

        // Number
        if (std.ascii.isDigit(c)) {
            return self.readNumber(start);
        }

        // Name/keyword
        if (isIdentStart(c)) {
            return self.readName(start);
        }

        // Operators and delimiters
        return self.readOperator(start);
    }

    fn currentPos(self: *const Self) Position {
        return Position{
            .line = self.line,
            .column = self.col,
            .offset = self.pos,
        };
    }

    fn advance(self: *Self) void {
        if (self.pos < self.source.len) {
            if (self.source[self.pos] == '\n') {
                self.line += 1;
                self.col = 0;
            } else {
                self.col += 1;
            }
            self.pos += 1;
        }
    }

    fn peek(self: *const Self, offset: usize) ?u8 {
        const idx = self.pos + offset;
        if (idx < self.source.len) {
            return self.source[idx];
        }
        return null;
    }

    fn handleIndentation(self: *Self) !void {
        var indent: u32 = 0;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ') {
                indent += 1;
                self.advance();
            } else if (c == '\t') {
                indent = (indent + 8) & ~@as(u32, 7);
                self.advance();
            } else {
                break;
            }
        }

        // Skip blank lines and comments
        if (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '\n' or c == '#') {
                return;
            }
        }

        self.at_bol = false;

        const current_indent = self.indent_stack.items[self.indent_stack.items.len - 1];

        if (indent > current_indent) {
            try self.indent_stack.append(indent);
            // Will return INDENT token
        } else if (indent < current_indent) {
            // Calculate dedents
            while (self.indent_stack.items.len > 1) {
                const top = self.indent_stack.items[self.indent_stack.items.len - 1];
                if (indent >= top) break;
                _ = self.indent_stack.pop();
                self.pending_dedents += 1;
            }
        }
    }

    fn readString(self: *Self, start: Position) Token {
        const quote = self.source[self.pos];
        self.advance();

        // Check for triple quote
        const triple = self.peek(0) == quote and self.peek(1) == quote;
        if (triple) {
            self.advance();
            self.advance();
        }

        const str_start = self.pos;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == '\\' and self.pos + 1 < self.source.len) {
                self.advance();
                self.advance();
                continue;
            }
            if (triple) {
                if (c == quote and self.peek(1) == quote and self.peek(2) == quote) {
                    const str_end = self.pos;
                    self.advance();
                    self.advance();
                    self.advance();
                    return Token{
                        .type_ = .STRING,
                        .start = start,
                        .end = self.currentPos(),
                        .string = self.source[str_start..str_end],
                    };
                }
            } else {
                if (c == quote) {
                    const str_end = self.pos;
                    self.advance();
                    return Token{
                        .type_ = .STRING,
                        .start = start,
                        .end = self.currentPos(),
                        .string = self.source[str_start..str_end],
                    };
                }
                if (c == '\n') {
                    return Token{
                        .type_ = .ERRORTOKEN,
                        .start = start,
                        .end = self.currentPos(),
                        .string = "unterminated string",
                    };
                }
            }
            self.advance();
        }

        return Token{
            .type_ = .ERRORTOKEN,
            .start = start,
            .end = self.currentPos(),
            .string = "unterminated string",
        };
    }

    fn readPrefixedString(self: *Self, start: Position) Token {
        const prefix_start = self.pos;
        while (self.pos < self.source.len and isStringPrefix(self.source[self.pos])) {
            self.advance();
        }
        const prefix = self.source[prefix_start..self.pos];

        if (self.pos < self.source.len and (self.source[self.pos] == '"' or self.source[self.pos] == '\'')) {
            var token = self.readString(start);
            token.prefix = prefix;

            // Check for f-string
            for (prefix) |c| {
                if (c == 'f' or c == 'F') {
                    token.type_ = .FSTRING_START;
                    break;
                }
            }
            return token;
        }

        // Not a string, treat as name
        return Token{
            .type_ = .NAME,
            .start = start,
            .end = self.currentPos(),
            .string = prefix,
        };
    }

    fn readNumber(self: *Self, start: Position) Token {
        const num_start = self.pos;

        // Check for hex, octal, binary
        if (self.source[self.pos] == '0' and self.pos + 1 < self.source.len) {
            const next = self.source[self.pos + 1];
            if (next == 'x' or next == 'X') {
                self.advance();
                self.advance();
                while (self.pos < self.source.len and std.ascii.isHex(self.source[self.pos])) {
                    self.advance();
                }
                return Token{
                    .type_ = .NUMBER,
                    .start = start,
                    .end = self.currentPos(),
                    .string = self.source[num_start..self.pos],
                };
            }
            if (next == 'o' or next == 'O') {
                self.advance();
                self.advance();
                while (self.pos < self.source.len and self.source[self.pos] >= '0' and self.source[self.pos] <= '7') {
                    self.advance();
                }
                return Token{
                    .type_ = .NUMBER,
                    .start = start,
                    .end = self.currentPos(),
                    .string = self.source[num_start..self.pos],
                };
            }
            if (next == 'b' or next == 'B') {
                self.advance();
                self.advance();
                while (self.pos < self.source.len and (self.source[self.pos] == '0' or self.source[self.pos] == '1')) {
                    self.advance();
                }
                return Token{
                    .type_ = .NUMBER,
                    .start = start,
                    .end = self.currentPos(),
                    .string = self.source[num_start..self.pos],
                };
            }
        }

        // Integer part
        while (self.pos < self.source.len and (std.ascii.isDigit(self.source[self.pos]) or self.source[self.pos] == '_')) {
            self.advance();
        }

        // Decimal part
        if (self.pos < self.source.len and self.source[self.pos] == '.') {
            if (self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1])) {
                self.advance();
                while (self.pos < self.source.len and (std.ascii.isDigit(self.source[self.pos]) or self.source[self.pos] == '_')) {
                    self.advance();
                }
            }
        }

        // Exponent
        if (self.pos < self.source.len and (self.source[self.pos] == 'e' or self.source[self.pos] == 'E')) {
            self.advance();
            if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
                self.advance();
            }
            while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
                self.advance();
            }
        }

        // Complex suffix
        if (self.pos < self.source.len and (self.source[self.pos] == 'j' or self.source[self.pos] == 'J')) {
            self.advance();
        }

        return Token{
            .type_ = .NUMBER,
            .start = start,
            .end = self.currentPos(),
            .string = self.source[num_start..self.pos],
        };
    }

    fn readName(self: *Self, start: Position) Token {
        const name_start = self.pos;
        while (self.pos < self.source.len and isIdentContinue(self.source[self.pos])) {
            self.advance();
        }
        const name = self.source[name_start..self.pos];

        // Check for async/await
        if (std.mem.eql(u8, name, "async")) {
            return Token{ .type_ = .ASYNC, .start = start, .end = self.currentPos(), .string = name };
        }
        if (std.mem.eql(u8, name, "await")) {
            return Token{ .type_ = .AWAIT, .start = start, .end = self.currentPos(), .string = name };
        }

        return Token{
            .type_ = .NAME,
            .start = start,
            .end = self.currentPos(),
            .string = name,
        };
    }

    fn readOperator(self: *Self, start: Position) Token {
        const c = self.source[self.pos];
        const c2 = self.peek(1);
        const c3 = self.peek(2);

        // Three-character operators
        if (c == '.' and c2 == '.' and c3 == '.') {
            self.advance();
            self.advance();
            self.advance();
            return Token{ .type_ = .ELLIPSIS, .start = start, .end = self.currentPos(), .string = "..." };
        }
        if (c == '<' and c2 == '<' and c3 == '=') {
            self.advance();
            self.advance();
            self.advance();
            return Token{ .type_ = .LEFTSHIFTEQUAL, .start = start, .end = self.currentPos(), .string = "<<=" };
        }
        if (c == '>' and c2 == '>' and c3 == '=') {
            self.advance();
            self.advance();
            self.advance();
            return Token{ .type_ = .RIGHTSHIFTEQUAL, .start = start, .end = self.currentPos(), .string = ">>=" };
        }
        if (c == '*' and c2 == '*' and c3 == '=') {
            self.advance();
            self.advance();
            self.advance();
            return Token{ .type_ = .DOUBLESTAREQUAL, .start = start, .end = self.currentPos(), .string = "**=" };
        }
        if (c == '/' and c2 == '/' and c3 == '=') {
            self.advance();
            self.advance();
            self.advance();
            return Token{ .type_ = .DOUBLESLASHEQUAL, .start = start, .end = self.currentPos(), .string = "//=" };
        }

        // Two-character operators
        const two_char_ops = [_]struct { chars: [2]u8, type_: TokenType }{
            .{ .chars = .{ '=', '=' }, .type_ = .EQEQUAL },
            .{ .chars = .{ '!', '=' }, .type_ = .NOTEQUAL },
            .{ .chars = .{ '<', '=' }, .type_ = .LESSEQUAL },
            .{ .chars = .{ '>', '=' }, .type_ = .GREATEREQUAL },
            .{ .chars = .{ '<', '<' }, .type_ = .LEFTSHIFT },
            .{ .chars = .{ '>', '>' }, .type_ = .RIGHTSHIFT },
            .{ .chars = .{ '*', '*' }, .type_ = .DOUBLESTAR },
            .{ .chars = .{ '/', '/' }, .type_ = .DOUBLESLASH },
            .{ .chars = .{ '+', '=' }, .type_ = .PLUSEQUAL },
            .{ .chars = .{ '-', '=' }, .type_ = .MINEQUAL },
            .{ .chars = .{ '*', '=' }, .type_ = .STAREQUAL },
            .{ .chars = .{ '/', '=' }, .type_ = .SLASHEQUAL },
            .{ .chars = .{ '%', '=' }, .type_ = .PERCENTEQUAL },
            .{ .chars = .{ '&', '=' }, .type_ = .AMPEREQUAL },
            .{ .chars = .{ '|', '=' }, .type_ = .VBAREQUAL },
            .{ .chars = .{ '^', '=' }, .type_ = .CIRCUMFLEXEQUAL },
            .{ .chars = .{ '@', '=' }, .type_ = .ATEQUAL },
            .{ .chars = .{ '-', '>' }, .type_ = .RARROW },
            .{ .chars = .{ ':', '=' }, .type_ = .COLONEQUAL },
        };

        if (c2) |next| {
            for (two_char_ops) |op| {
                if (c == op.chars[0] and next == op.chars[1]) {
                    self.advance();
                    self.advance();
                    return Token{
                        .type_ = op.type_,
                        .start = start,
                        .end = self.currentPos(),
                        .string = self.source[start.offset..self.pos],
                    };
                }
            }
        }

        // Single character operators
        self.advance();
        const type_: TokenType = switch (c) {
            '(' => blk: {
                self.bracket_level += 1;
                break :blk .LPAR;
            },
            ')' => blk: {
                if (self.bracket_level > 0) self.bracket_level -= 1;
                break :blk .RPAR;
            },
            '[' => blk: {
                self.bracket_level += 1;
                break :blk .LSQB;
            },
            ']' => blk: {
                if (self.bracket_level > 0) self.bracket_level -= 1;
                break :blk .RSQB;
            },
            '{' => blk: {
                self.bracket_level += 1;
                break :blk .LBRACE;
            },
            '}' => blk: {
                if (self.bracket_level > 0) self.bracket_level -= 1;
                break :blk .RBRACE;
            },
            ':' => .COLON,
            ',' => .COMMA,
            ';' => .SEMI,
            '+' => .PLUS,
            '-' => .MINUS,
            '*' => .STAR,
            '/' => .SLASH,
            '|' => .VBAR,
            '&' => .AMPER,
            '<' => .LESS,
            '>' => .GREATER,
            '=' => .EQUAL,
            '.' => .DOT,
            '%' => .PERCENT,
            '~' => .TILDE,
            '^' => .CIRCUMFLEX,
            '@' => .AT,
            '!' => .EXCLAMATION,
            else => .ERRORTOKEN,
        };

        return Token{
            .type_ = type_,
            .start = start,
            .end = self.currentPos(),
            .string = self.source[start.offset..self.pos],
        };
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn isStringPrefix(c: u8) bool {
    return c == 'r' or c == 'R' or c == 'b' or c == 'B' or c == 'f' or c == 'F' or c == 'u' or c == 'U';
}

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
