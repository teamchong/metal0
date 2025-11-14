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

    // Literals
    Ident,
    Number,
    String,

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

    // Indentation
    Indent,
    Dedent,
    Newline,
    Eof,
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: usize,
    column: usize,
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
            // Handle indentation at start of line
            if (at_line_start and self.peek() != '\n') {
                const dedents = try self.handleIndentation(&tokens);
                _ = dedents;
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

    fn handleIndentation(self: *Lexer, tokens: *std.ArrayList(Token)) !usize {
        var indent_level: usize = 0;

        // Count spaces/tabs at start of line
        while (self.peek()) |c| {
            if (c == ' ') {
                indent_level += 1;
                _ = self.advance();
            } else if (c == '\t') {
                indent_level += 4; // Tab = 4 spaces
                _ = self.advance();
            } else {
                break;
            }
        }

        // Skip blank lines
        if (self.peek() == '\n' or self.peek() == '#') {
            return 0;
        }

        const current_indent = self.indent_stack.items[self.indent_stack.items.len - 1];

        if (indent_level > current_indent) {
            // Indent
            try self.indent_stack.append(self.allocator, indent_level);
            try tokens.append(self.allocator, Token{
                .type = .Indent,
                .lexeme = "",
                .line = self.line,
                .column = 1,
            });
            return 1;
        } else if (indent_level < current_indent) {
            // Dedent (possibly multiple levels)
            var dedent_count: usize = 0;
            while (self.indent_stack.items.len > 1) {
                const stack_top = self.indent_stack.items[self.indent_stack.items.len - 1];
                if (stack_top <= indent_level) break;

                _ = self.indent_stack.pop();
                try tokens.append(self.allocator, Token{
                    .type = .Dedent,
                    .lexeme = "",
                    .line = self.line,
                    .column = 1,
                });
                dedent_count += 1;
            }
            return dedent_count;
        }

        return 0;
    }

    fn tokenizeIdentifier(self: *Lexer, start: usize, start_column: usize) !Token {
        while (self.peek()) |c| {
            if (self.isAlphaNumeric(c)) {
                _ = self.advance();
            } else {
                break;
            }
        }

        const lexeme = self.source[start..self.current];
        const token_type = self.getKeyword(lexeme);

        return Token{
            .type = token_type,
            .lexeme = lexeme,
            .line = self.line,
            .column = start_column,
        };
    }

    fn tokenizeNumber(self: *Lexer, start: usize, start_column: usize) !Token {
        while (self.peek()) |c| {
            if (self.isDigit(c)) {
                _ = self.advance();
            } else {
                break;
            }
        }

        // Handle decimal point
        if (self.peek() == '.' and self.peekAhead(1) != null) {
            const next = self.peekAhead(1).?;
            if (self.isDigit(next)) {
                _ = self.advance(); // consume '.'
                while (self.peek()) |c| {
                    if (self.isDigit(c)) {
                        _ = self.advance();
                    } else {
                        break;
                    }
                }
            }
        }

        const lexeme = self.source[start..self.current];
        return Token{
            .type = .Number,
            .lexeme = lexeme,
            .line = self.line,
            .column = start_column,
        };
    }

    fn tokenizeString(self: *Lexer, start: usize, start_column: usize) !Token {
        const quote = self.advance().?; // Consume opening quote

        // Check for triple quotes
        const is_triple = (self.peek() == quote and self.peekAhead(1) == quote);
        if (is_triple) {
            _ = self.advance();
            _ = self.advance();

            // Consume until closing triple quotes
            while (!self.isAtEnd()) {
                if (self.peek() == quote and
                    self.peekAhead(1) == quote and
                    self.peekAhead(2) == quote)
                {
                    _ = self.advance();
                    _ = self.advance();
                    _ = self.advance();
                    break;
                }
                _ = self.advance();
            }
        } else {
            // Single or double quoted string
            while (self.peek() != quote and !self.isAtEnd()) {
                if (self.peek() == '\\') {
                    _ = self.advance(); // Consume backslash
                    _ = self.advance(); // Consume escaped character
                } else {
                    _ = self.advance();
                }
            }

            if (!self.isAtEnd()) {
                _ = self.advance(); // Consume closing quote
            }
        }

        const lexeme = self.source[start..self.current];
        return Token{
            .type = .String,
            .lexeme = lexeme,
            .line = self.line,
            .column = start_column,
        };
    }

    fn tokenizeOperatorOrDelimiter(self: *Lexer, start: usize, start_column: usize, paren_depth: *usize) !?Token {
        const c = self.advance() orelse return null;

        const token_type: TokenType = switch (c) {
            '(' => blk: {
                paren_depth.* += 1;
                break :blk .LParen;
            },
            ')' => blk: {
                if (paren_depth.* > 0) paren_depth.* -= 1;
                break :blk .RParen;
            },
            '[' => blk: {
                paren_depth.* += 1;
                break :blk .LBracket;
            },
            ']' => blk: {
                if (paren_depth.* > 0) paren_depth.* -= 1;
                break :blk .RBracket;
            },
            '{' => blk: {
                paren_depth.* += 1;
                break :blk .LBrace;
            },
            '}' => blk: {
                if (paren_depth.* > 0) paren_depth.* -= 1;
                break :blk .RBrace;
            },
            ',' => .Comma,
            ':' => .Colon,
            '.' => .Dot,
            '+' => .Plus,
            '%' => .Percent,
            '-' => blk: {
                if (self.peek() == '>') {
                    _ = self.advance();
                    break :blk .Arrow;
                }
                break :blk .Minus;
            },
            '*' => blk: {
                if (self.peek() == '*') {
                    _ = self.advance();
                    break :blk .DoubleStar;
                }
                break :blk .Star;
            },
            '/' => blk: {
                if (self.peek() == '/') {
                    _ = self.advance();
                    break :blk .DoubleSlash;
                }
                break :blk .Slash;
            },
            '=' => blk: {
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .EqEq;
                }
                break :blk .Eq;
            },
            '!' => blk: {
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .NotEq;
                }
                return error.UnexpectedCharacter;
            },
            '<' => blk: {
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .LtEq;
                }
                break :blk .Lt;
            },
            '>' => blk: {
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .GtEq;
                }
                break :blk .Gt;
            },
            '&' => .Ampersand,
            '|' => .Pipe,
            '^' => .Caret,
            else => return null,
        };

        const lexeme = self.source[start..self.current];
        return Token{
            .type = token_type,
            .lexeme = lexeme,
            .line = self.line,
            .column = start_column,
        };
    }

    fn getKeyword(self: *Lexer, lexeme: []const u8) TokenType {
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
        });

        return keywords.get(lexeme) orelse .Ident;
    }

    fn skipComment(self: *Lexer) void {
        while (self.peek() != '\n' and !self.isAtEnd()) {
            _ = self.advance();
        }
    }

    fn isAtEnd(self: *Lexer) bool {
        return self.current >= self.source.len;
    }

    fn peek(self: *Lexer) ?u8 {
        if (self.current >= self.source.len) return null;
        return self.source[self.current];
    }

    fn peekAhead(self: *Lexer, offset: usize) ?u8 {
        const pos = self.current + offset;
        if (pos >= self.source.len) return null;
        return self.source[pos];
    }

    fn advance(self: *Lexer) ?u8 {
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

    fn isAlpha(self: *Lexer, c: u8) bool {
        _ = self;
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
    }

    fn isDigit(self: *Lexer, c: u8) bool {
        _ = self;
        return c >= '0' and c <= '9';
    }

    fn isAlphaNumeric(self: *Lexer, c: u8) bool {
        return self.isAlpha(c) or self.isDigit(c);
    }
};
