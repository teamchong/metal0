/// Lexer implementation for expression parser
const std = @import("std");
const tokens = @import("tokens.zig");
const TokenType = tokens.TokenType;
const Token = tokens.Token;
const ParseError = tokens.ParseError;

/// Lexer state and scanning methods
pub const Lexer = struct {
    source: []const u8,
    pos: usize,

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .pos = 0,
        };
    }

    pub fn advance(self: *Lexer) !Token {
        self.skipWhitespace();

        if (self.pos >= self.source.len) {
            return Token{ .type = .Eof, .start = self.pos, .end = self.pos };
        }

        const start = self.pos;
        const c = self.source[self.pos];

        // Single character tokens
        switch (c) {
            '+' => {
                self.pos += 1;
                return Token{ .type = .Plus, .start = start, .end = self.pos };
            },
            '-' => {
                self.pos += 1;
                return Token{ .type = .Minus, .start = start, .end = self.pos };
            },
            '*' => {
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '*') {
                    self.pos += 2;
                    return Token{ .type = .DoubleStar, .start = start, .end = self.pos };
                } else {
                    self.pos += 1;
                    return Token{ .type = .Star, .start = start, .end = self.pos };
                }
            },
            '/' => {
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
                    self.pos += 2;
                    return Token{ .type = .DoubleSlash, .start = start, .end = self.pos };
                } else {
                    self.pos += 1;
                    return Token{ .type = .Slash, .start = start, .end = self.pos };
                }
            },
            '%' => {
                self.pos += 1;
                return Token{ .type = .Percent, .start = start, .end = self.pos };
            },
            '~' => {
                self.pos += 1;
                return Token{ .type = .Tilde, .start = start, .end = self.pos };
            },
            '(' => {
                self.pos += 1;
                return Token{ .type = .LParen, .start = start, .end = self.pos };
            },
            ')' => {
                self.pos += 1;
                return Token{ .type = .RParen, .start = start, .end = self.pos };
            },
            '[' => {
                self.pos += 1;
                return Token{ .type = .LBracket, .start = start, .end = self.pos };
            },
            ']' => {
                self.pos += 1;
                return Token{ .type = .RBracket, .start = start, .end = self.pos };
            },
            ',' => {
                self.pos += 1;
                return Token{ .type = .Comma, .start = start, .end = self.pos };
            },
            '=' => {
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '=') {
                    self.pos += 2;
                    return Token{ .type = .Eq, .start = start, .end = self.pos };
                } else {
                    return ParseError.UnexpectedToken;
                }
            },
            '!' => {
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '=') {
                    self.pos += 2;
                    return Token{ .type = .NotEq, .start = start, .end = self.pos };
                } else {
                    return ParseError.UnexpectedToken;
                }
            },
            '<' => {
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '=') {
                    self.pos += 2;
                    return Token{ .type = .LtE, .start = start, .end = self.pos };
                } else {
                    self.pos += 1;
                    return Token{ .type = .Lt, .start = start, .end = self.pos };
                }
            },
            '>' => {
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '=') {
                    self.pos += 2;
                    return Token{ .type = .GtE, .start = start, .end = self.pos };
                } else {
                    self.pos += 1;
                    return Token{ .type = .Gt, .start = start, .end = self.pos };
                }
            },
            '"', '\'' => {
                return try self.scanString(c);
            },
            else => {},
        }

        // Number (including .14 style floats)
        if (std.ascii.isDigit(c) or (c == '.' and self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1]))) {
            return try self.scanNumber();
        }

        // Identifier/keyword
        if (std.ascii.isAlphabetic(c) or c == '_') {
            return try self.scanIdentifier();
        }

        return ParseError.UnexpectedToken;
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.source.len and std.ascii.isWhitespace(self.source[self.pos])) {
            self.pos += 1;
        }
    }

    fn scanNumber(self: *Lexer) !Token {
        const start = self.pos;
        // Check for base prefix: 0b, 0o, 0x
        if (self.pos + 1 < self.source.len and self.source[self.pos] == '0') {
            const prefix = self.source[self.pos + 1];
            if (prefix == 'b' or prefix == 'B' or prefix == 'o' or prefix == 'O' or prefix == 'x' or prefix == 'X') {
                self.pos += 2; // Skip "0x" etc.
                // Scan hex/binary/octal digits plus underscores
                while (self.pos < self.source.len) {
                    const c = self.source[self.pos];
                    if (std.ascii.isAlphanumeric(c) or c == '_') {
                        self.pos += 1;
                    } else {
                        break;
                    }
                }
                return Token{ .type = .Number, .start = start, .end = self.pos };
            }
        }
        // Include digits, underscores (Python 3.6+), decimal point, and scientific notation (e/E)
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isDigit(c) or c == '.' or c == '_') {
                self.pos += 1;
            } else if (c == 'e' or c == 'E') {
                // Scientific notation - include e and optional sign
                self.pos += 1;
                if (self.pos < self.source.len and (self.source[self.pos] == '+' or self.source[self.pos] == '-')) {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
        // Check for complex suffix 'j' or 'J'
        if (self.pos < self.source.len and (self.source[self.pos] == 'j' or self.source[self.pos] == 'J')) {
            self.pos += 1;
            return Token{ .type = .Complex, .start = start, .end = self.pos };
        }
        return Token{ .type = .Number, .start = start, .end = self.pos };
    }

    fn scanString(self: *Lexer, quote: u8) !Token {
        const start = self.pos;
        self.pos += 1; // skip opening quote
        while (self.pos < self.source.len and self.source[self.pos] != quote) {
            if (self.source[self.pos] == '\\' and self.pos + 1 < self.source.len) {
                self.pos += 2; // skip escape
            } else {
                self.pos += 1;
            }
        }
        if (self.pos >= self.source.len) return ParseError.UnclosedString;
        self.pos += 1; // skip closing quote
        return Token{ .type = .String, .start = start, .end = self.pos };
    }

    fn scanIdentifier(self: *Lexer) !Token {
        const start = self.pos;
        while (self.pos < self.source.len and (std.ascii.isAlphanumeric(self.source[self.pos]) or self.source[self.pos] == '_')) {
            self.pos += 1;
        }
        const text = self.source[start..self.pos];

        // Check keywords
        const tok_type: TokenType = if (std.mem.eql(u8, text, "True"))
            .True
        else if (std.mem.eql(u8, text, "False"))
            .False
        else if (std.mem.eql(u8, text, "None"))
            .None
        else
            .Name;

        return Token{ .type = tok_type, .start = start, .end = self.pos };
    }
};
