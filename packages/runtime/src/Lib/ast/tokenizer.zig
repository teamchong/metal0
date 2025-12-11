//! Python Tokenizer
//! Converts Python source code into tokens.

const std = @import("std");

pub const TokenType = enum {
    // Literals
    Number,
    String,
    Name,
    // Keywords
    KwDef,
    KwClass,
    KwReturn,
    KwIf,
    KwElif,
    KwElse,
    KwFor,
    KwWhile,
    KwBreak,
    KwContinue,
    KwPass,
    KwImport,
    KwFrom,
    KwAs,
    KwTrue,
    KwFalse,
    KwNone,
    KwAnd,
    KwOr,
    KwNot,
    KwIn,
    KwIs,
    KwLambda,
    KwTry,
    KwExcept,
    KwFinally,
    KwRaise,
    KwWith,
    KwAssert,
    KwYield,
    KwGlobal,
    KwNonlocal,
    KwDel,
    KwAsync,
    KwAwait,
    KwMatch,
    KwCase,
    // Operators
    Plus,
    Minus,
    Star,
    Slash,
    DoubleSlash,
    Percent,
    DoubleStar,
    At,
    Ampersand,
    Pipe,
    Caret,
    Tilde,
    LeftShift,
    RightShift,
    // Comparison
    Less,
    Greater,
    LessEqual,
    GreaterEqual,
    EqualEqual,
    NotEqual,
    // Assignment
    Equal,
    PlusEqual,
    MinusEqual,
    StarEqual,
    SlashEqual,
    PercentEqual,
    DoubleStarEqual,
    AmpersandEqual,
    PipeEqual,
    CaretEqual,
    LeftShiftEqual,
    RightShiftEqual,
    DoubleSlashEqual,
    AtEqual,
    ColonEqual,
    // Delimiters
    LeftParen,
    RightParen,
    LeftBracket,
    RightBracket,
    LeftBrace,
    RightBrace,
    Comma,
    Colon,
    Semicolon,
    Dot,
    Arrow,
    Ellipsis,
    // Special
    Newline,
    Indent,
    Dedent,
    Eof,
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: i32,
    column: i32,
};

pub const Tokenizer = struct {
    source: []const u8,
    pos: usize,
    line: i32,
    column: i32,
    allocator: std.mem.Allocator,
    tokens: std.ArrayList(Token),
    indent_stack: std.ArrayList(usize),

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Tokenizer {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 0,
            .allocator = allocator,
            .tokens = std.ArrayList(Token).init(allocator),
            .indent_stack = std.ArrayList(usize).init(allocator),
        };
    }

    pub fn deinit(self: *Tokenizer) void {
        self.tokens.deinit();
        self.indent_stack.deinit();
    }

    fn peek(self: *Tokenizer) ?u8 {
        if (self.pos >= self.source.len) return null;
        return self.source[self.pos];
    }

    fn advance(self: *Tokenizer) ?u8 {
        if (self.pos >= self.source.len) return null;
        const c = self.source[self.pos];
        self.pos += 1;
        self.column += 1;
        if (c == '\n') {
            self.line += 1;
            self.column = 0;
        }
        return c;
    }

    pub fn tokenize(self: *Tokenizer) ![]Token {
        try self.indent_stack.append(0);

        while (self.peek() != null) {
            try self.scanToken();
        }

        // Emit remaining dedents
        while (self.indent_stack.items.len > 1) {
            _ = self.indent_stack.pop();
            try self.tokens.append(.{ .type = .Dedent, .lexeme = "", .line = self.line, .column = self.column });
        }

        try self.tokens.append(.{ .type = .Eof, .lexeme = "", .line = self.line, .column = self.column });
        return self.tokens.items;
    }

    fn scanToken(self: *Tokenizer) !void {
        const c = self.peek() orelse return;

        // Skip whitespace (except newlines)
        if (c == ' ' or c == '\t' or c == '\r') {
            _ = self.advance();
            return;
        }

        // Comments
        if (c == '#') {
            while (self.peek()) |ch| {
                if (ch == '\n') break;
                _ = self.advance();
            }
            return;
        }

        // Newline
        if (c == '\n') {
            _ = self.advance();
            try self.tokens.append(.{ .type = .Newline, .lexeme = "\n", .line = self.line - 1, .column = self.column });
            return;
        }

        // String literals
        if (c == '"' or c == '\'') {
            try self.scanString();
            return;
        }

        // Numbers
        if (std.ascii.isDigit(c)) {
            try self.scanNumber();
            return;
        }

        // Identifiers and keywords
        if (std.ascii.isAlphabetic(c) or c == '_') {
            try self.scanIdentifier();
            return;
        }

        // Operators and delimiters
        try self.scanOperator();
    }

    fn scanString(self: *Tokenizer) !void {
        const quote = self.advance().?;
        const start = self.pos;

        // Check for triple quotes
        var triple = false;
        if (self.peek() == quote) {
            _ = self.advance();
            if (self.peek() == quote) {
                _ = self.advance();
                triple = true;
            } else {
                // Empty string
                try self.tokens.append(.{ .type = .String, .lexeme = "", .line = self.line, .column = self.column });
                return;
            }
        }

        while (self.peek()) |c| {
            if (c == '\\') {
                _ = self.advance();
                _ = self.advance(); // Skip escaped char
            } else if (c == quote) {
                if (triple) {
                    if (self.pos + 2 < self.source.len and
                        self.source[self.pos + 1] == quote and
                        self.source[self.pos + 2] == quote)
                    {
                        const lexeme = self.source[start..self.pos];
                        _ = self.advance();
                        _ = self.advance();
                        _ = self.advance();
                        try self.tokens.append(.{ .type = .String, .lexeme = lexeme, .line = self.line, .column = self.column });
                        return;
                    }
                    _ = self.advance();
                } else {
                    const lexeme = self.source[start..self.pos];
                    _ = self.advance();
                    try self.tokens.append(.{ .type = .String, .lexeme = lexeme, .line = self.line, .column = self.column });
                    return;
                }
            } else {
                _ = self.advance();
            }
        }
    }

    fn scanNumber(self: *Tokenizer) !void {
        const start = self.pos;
        while (self.peek()) |c| {
            if (std.ascii.isDigit(c) or c == '.' or c == 'e' or c == 'E' or c == '+' or c == '-' or c == '_' or c == 'x' or c == 'X' or c == 'o' or c == 'O' or c == 'b' or c == 'B' or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')) {
                _ = self.advance();
            } else {
                break;
            }
        }
        try self.tokens.append(.{ .type = .Number, .lexeme = self.source[start..self.pos], .line = self.line, .column = self.column });
    }

    fn scanIdentifier(self: *Tokenizer) !void {
        const start = self.pos;
        while (self.peek()) |c| {
            if (std.ascii.isAlphanumeric(c) or c == '_') {
                _ = self.advance();
            } else {
                break;
            }
        }
        const lexeme = self.source[start..self.pos];
        const tok_type = getKeywordType(lexeme);
        try self.tokens.append(.{ .type = tok_type, .lexeme = lexeme, .line = self.line, .column = self.column });
    }

    fn getKeywordType(lexeme: []const u8) TokenType {
        const keywords = std.StaticStringMap(TokenType).initComptime(.{
            .{ "def", .KwDef },
            .{ "class", .KwClass },
            .{ "return", .KwReturn },
            .{ "if", .KwIf },
            .{ "elif", .KwElif },
            .{ "else", .KwElse },
            .{ "for", .KwFor },
            .{ "while", .KwWhile },
            .{ "break", .KwBreak },
            .{ "continue", .KwContinue },
            .{ "pass", .KwPass },
            .{ "import", .KwImport },
            .{ "from", .KwFrom },
            .{ "as", .KwAs },
            .{ "True", .KwTrue },
            .{ "False", .KwFalse },
            .{ "None", .KwNone },
            .{ "and", .KwAnd },
            .{ "or", .KwOr },
            .{ "not", .KwNot },
            .{ "in", .KwIn },
            .{ "is", .KwIs },
            .{ "lambda", .KwLambda },
            .{ "try", .KwTry },
            .{ "except", .KwExcept },
            .{ "finally", .KwFinally },
            .{ "raise", .KwRaise },
            .{ "with", .KwWith },
            .{ "assert", .KwAssert },
            .{ "yield", .KwYield },
            .{ "global", .KwGlobal },
            .{ "nonlocal", .KwNonlocal },
            .{ "del", .KwDel },
            .{ "async", .KwAsync },
            .{ "await", .KwAwait },
            .{ "match", .KwMatch },
            .{ "case", .KwCase },
        });
        return keywords.get(lexeme) orelse .Name;
    }

    fn scanOperator(self: *Tokenizer) !void {
        const c = self.advance().?;
        const start_line = self.line;
        const start_col = self.column;

        const tok_type: TokenType = switch (c) {
            '+' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .PlusEqual;
            } else .Plus,
            '-' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .MinusEqual;
            } else if (self.peek() == '>') blk: {
                _ = self.advance();
                break :blk .Arrow;
            } else .Minus,
            '*' => if (self.peek() == '*') blk: {
                _ = self.advance();
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .DoubleStarEqual;
                }
                break :blk .DoubleStar;
            } else if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .StarEqual;
            } else .Star,
            '/' => if (self.peek() == '/') blk: {
                _ = self.advance();
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .DoubleSlashEqual;
                }
                break :blk .DoubleSlash;
            } else if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .SlashEqual;
            } else .Slash,
            '%' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .PercentEqual;
            } else .Percent,
            '=' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .EqualEqual;
            } else .Equal,
            '<' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .LessEqual;
            } else if (self.peek() == '<') blk: {
                _ = self.advance();
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .LeftShiftEqual;
                }
                break :blk .LeftShift;
            } else .Less,
            '>' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .GreaterEqual;
            } else if (self.peek() == '>') blk: {
                _ = self.advance();
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .RightShiftEqual;
                }
                break :blk .RightShift;
            } else .Greater,
            '!' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .NotEqual;
            } else return,
            '&' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .AmpersandEqual;
            } else .Ampersand,
            '|' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .PipeEqual;
            } else .Pipe,
            '^' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .CaretEqual;
            } else .Caret,
            '~' => .Tilde,
            '@' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .AtEqual;
            } else .At,
            '(' => .LeftParen,
            ')' => .RightParen,
            '[' => .LeftBracket,
            ']' => .RightBracket,
            '{' => .LeftBrace,
            '}' => .RightBrace,
            ',' => .Comma,
            ':' => if (self.peek() == '=') blk: {
                _ = self.advance();
                break :blk .ColonEqual;
            } else .Colon,
            ';' => .Semicolon,
            '.' => if (self.peek() == '.') blk: {
                _ = self.advance();
                if (self.peek() == '.') {
                    _ = self.advance();
                    break :blk .Ellipsis;
                }
                break :blk .Dot;
            } else .Dot,
            else => return,
        };

        try self.tokens.append(.{ .type = tok_type, .lexeme = self.source[self.pos - 1 .. self.pos], .line = start_line, .column = start_col });
    }
};
