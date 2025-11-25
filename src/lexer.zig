const std = @import("std");

/// Token types for Python lexer
pub const TokenType = enum {
    // Keywords
    Def,
    Class,
    If,
    Elif,
    Else,
    For,
    While,
    Return,
    Break,
    Continue,
    Pass,
    Import,
    From,
    As,
    In,
    Not,
    And,
    Or,
    True,
    False,
    None,
    Async,
    Await,
    Assert,
    Try,
    Except,
    Finally,
    Lambda,
    Global,
    With,

    // Literals
    Ident,
    Number,
    ComplexNumber,
    String,
    FString,
    Ellipsis,

    // Operators
    Plus,
    Minus,
    Star,
    Slash,
    DoubleSlash,
    Percent,
    DoubleStar,
    Eq,
    EqEq,
    NotEq,
    Lt,
    LtEq,
    Gt,
    GtEq,
    Ampersand,
    Pipe,
    Caret,
    Tilde,
    PlusEq,
    MinusEq,
    StarEq,
    SlashEq,
    DoubleSlashEq,
    PercentEq,
    StarStarEq,

    // Delimiters
    LParen,
    RParen,
    LBracket,
    RBracket,
    LBrace,
    RBrace,
    Comma,
    Colon,
    Dot,
    Arrow,
    At,

    // Indentation
    Indent,
    Dedent,
    Newline,
    Eof,
};

pub const FStringPart = union(enum) {
    literal: []const u8,
    expr: []const u8,
    format_expr: struct {
        expr: []const u8,
        format_spec: []const u8,
    },
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: usize,
    column: usize,
    fstring_parts: ?[]FStringPart = null,
};

pub const Lexer = struct {
    source: []const u8,
    current: usize,
    line: usize,
    column: usize,
    indent_stack: std.ArrayList(usize),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) !Lexer {
        var indent_stack = std.ArrayList(usize){};
        try indent_stack.append(allocator, 0); // Base indentation

        return Lexer{
            .source = source,
            .current = 0,
            .line = 1,
            .column = 1,
            .indent_stack = indent_stack,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.indent_stack.deinit(self.allocator);
    }

    pub fn tokenize(self: *Lexer) ![]Token {
        var tokens = std.ArrayList(Token){};
        errdefer tokens.deinit(self.allocator);

        var paren_depth: usize = 0; // Track parentheses for newline handling
        var at_line_start = true;

        while (!self.isAtEnd()) {
            // Handle indentation at start of line (skip if inside parens/brackets/braces)
            if (at_line_start and self.peek() != '\n' and paren_depth == 0) {
                const dedents = try self.handleIndentation(&tokens);
                _ = dedents;
                at_line_start = false;
            } else if (at_line_start and self.peek() != '\n') {
                // Inside parens: skip indentation whitespace but don't emit Indent/Dedent
                while (self.peek()) |ws| {
                    if (ws == ' ' or ws == '\t') {
                        _ = self.advance();
                    } else {
                        break;
                    }
                }
                at_line_start = false;
            }

            const start = self.current;
            const start_column = self.column;
            const c = self.peek() orelse break;

            // Skip whitespace (but not newlines)
            if (c == ' ' or c == '\t') {
                _ = self.advance();
                continue;
            }

            // Handle comments
            if (c == '#') {
                self.skipComment();
                continue;
            }

            // Handle newlines
            if (c == '\n') {
                _ = self.advance();
                at_line_start = true;

                // Only emit newline if not inside parens and previous token isn't newline
                if (paren_depth == 0 and tokens.items.len > 0) {
                    const last = tokens.items[tokens.items.len - 1];
                    if (last.type != .Newline) {
                        try tokens.append(self.allocator, Token{
                            .type = .Newline,
                            .lexeme = "\n",
                            .line = self.line - 1,
                            .column = start_column,
                        });
                    }
                }
                continue;
            }

            // F-strings (check before identifiers)
            if (c == 'f' and (self.peekAhead(1) == '"' or self.peekAhead(1) == '\'')) {
                _ = self.advance(); // consume 'f'
                const token = try self.tokenizeFString(start, start_column);
                try tokens.append(self.allocator, token);
                continue;
            }

            // Identifiers and keywords
            if (self.isAlpha(c)) {
                const token = try self.tokenizeIdentifier(start, start_column);
                try tokens.append(self.allocator, token);
                continue;
            }

            // Numbers
            if (self.isDigit(c)) {
                const token = try self.tokenizeNumber(start, start_column);
                try tokens.append(self.allocator, token);
                continue;
            }

            // Strings
            if (c == '"' or c == '\'') {
                const token = try self.tokenizeString(start, start_column);
                try tokens.append(self.allocator, token);
                continue;
            }

            // Operators and delimiters
            const maybe_token = try self.tokenizeOperatorOrDelimiter(start, start_column, &paren_depth);
            if (maybe_token) |token| {
                try tokens.append(self.allocator, token);
                continue;
            }

            // Unknown character
            return error.UnexpectedCharacter;
        }

        // Emit remaining dedents at end of file
        while (self.indent_stack.items.len > 1) {
            _ = self.indent_stack.pop();
            try tokens.append(self.allocator, Token{
                .type = .Dedent,
                .lexeme = "",
                .line = self.line,
                .column = self.column,
            });
        }

        try tokens.append(self.allocator, Token{
            .type = .Eof,
            .lexeme = "",
            .line = self.line,
            .column = self.column,
        });

        return tokens.toOwnedSlice(self.allocator);
    }

    // Import tokenizer functions
    const tokenizer = @import("lexer/tokenizer.zig");
    const handleIndentation = tokenizer.handleIndentation;
    const tokenizeIdentifier = tokenizer.tokenizeIdentifier;
    const tokenizeNumber = tokenizer.tokenizeNumber;
    const tokenizeString = tokenizer.tokenizeString;
    const tokenizeFString = tokenizer.tokenizeFString;
    const tokenizeOperatorOrDelimiter = tokenizer.tokenizeOperatorOrDelimiter;

    pub fn getKeyword(self: *Lexer, lexeme: []const u8) TokenType {
        _ = self;

        const keywords = std.StaticStringMap(TokenType).initComptime(.{
            .{ "def", .Def },
            .{ "class", .Class },
            .{ "if", .If },
            .{ "elif", .Elif },
            .{ "else", .Else },
            .{ "for", .For },
            .{ "while", .While },
            .{ "return", .Return },
            .{ "break", .Break },
            .{ "continue", .Continue },
            .{ "pass", .Pass },
            .{ "import", .Import },
            .{ "from", .From },
            .{ "as", .As },
            .{ "in", .In },
            .{ "not", .Not },
            .{ "and", .And },
            .{ "or", .Or },
            .{ "True", .True },
            .{ "False", .False },
            .{ "None", .None },
            .{ "async", .Async },
            .{ "await", .Await },
            .{ "assert", .Assert },
            .{ "try", .Try },
            .{ "except", .Except },
            .{ "finally", .Finally },
            .{ "lambda", .Lambda },
            .{ "global", .Global },
            .{ "with", .With },
        });

        return keywords.get(lexeme) orelse .Ident;
    }

    pub fn skipComment(self: *Lexer) void {
        while (self.peek() != '\n' and !self.isAtEnd()) {
            _ = self.advance();
        }
    }

    pub fn isAtEnd(self: *Lexer) bool {
        return self.current >= self.source.len;
    }

    pub fn peek(self: *Lexer) ?u8 {
        if (self.current >= self.source.len) return null;
        return self.source[self.current];
    }

    pub fn peekAhead(self: *Lexer, offset: usize) ?u8 {
        const pos = self.current + offset;
        if (pos >= self.source.len) return null;
        return self.source[pos];
    }

    pub fn advance(self: *Lexer) ?u8 {
        if (self.current >= self.source.len) return null;
        const c = self.source[self.current];
        self.current += 1;
        self.column += 1;
        if (c == '\n') {
            self.line += 1;
            self.column = 1;
        }
        return c;
    }

    pub fn isAlpha(self: *Lexer, c: u8) bool {
        _ = self;
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
    }

    pub fn isDigit(self: *Lexer, c: u8) bool {
        _ = self;
        return c >= '0' and c <= '9';
    }

    pub fn isAlphaNumeric(self: *Lexer, c: u8) bool {
        return self.isAlpha(c) or self.isDigit(c);
    }
};
