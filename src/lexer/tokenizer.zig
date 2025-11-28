/// Tokenization logic for Python lexer
const std = @import("std");
const Token = @import("../lexer.zig").Token;
const TokenType = @import("../lexer.zig").TokenType;
const Lexer = @import("../lexer.zig").Lexer;

// Import submodules
const fstring = @import("tokenizer/fstring.zig");
const numbers = @import("tokenizer/numbers.zig");

// Re-export functions from submodules
pub const tokenizeFString = fstring.tokenizeFString;
pub const tokenizeNumber = numbers.tokenizeNumber;
pub const isHexDigit = numbers.isHexDigit;

pub fn tokenizeIdentifier(self: *Lexer, start: usize, start_column: usize) !Token {
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

pub const StringKind = enum { regular, byte, raw };

pub fn tokenizePrefixedString(self: *Lexer, start: usize, start_column: usize, kind: StringKind) !Token {
    const quote = self.advance().?; // Consume opening quote
    const process_escapes = kind != .raw;

    // Check for triple quotes
    const is_triple = (self.peek() == quote and self.peekAhead(1) == quote);
    if (is_triple) {
        _ = self.advance();
        _ = self.advance();

        // Consume until closing triple quotes
        while (!self.isAtEnd()) {
            if (self.peek() == quote and self.peekAhead(1) == quote and self.peekAhead(2) == quote) {
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
            if (process_escapes and self.peek() == '\\') {
                _ = self.advance(); // Consume backslash
                _ = self.advance(); // Consume escaped character
            } else {
                _ = self.advance();
            }
        }
        if (!self.isAtEnd()) _ = self.advance(); // Consume closing quote
    }

    const token_type: TokenType = switch (kind) {
        .regular => .String,
        .byte => .ByteString,
        .raw => .RawString,
    };
    return Token{ .type = token_type, .lexeme = self.source[start..self.current], .line = self.line, .column = start_column };
}

// Convenience wrappers for backward compatibility
pub fn tokenizeString(self: *Lexer, start: usize, start_column: usize) !Token {
    return tokenizePrefixedString(self, start, start_column, .regular);
}

pub fn tokenizeByteString(self: *Lexer, start: usize, start_column: usize) !Token {
    return tokenizePrefixedString(self, start, start_column, .byte);
}

pub fn tokenizeRawString(self: *Lexer, start: usize, start_column: usize) !Token {
    return tokenizePrefixedString(self, start, start_column, .raw);
}

pub fn tokenizeRawByteString(self: *Lexer, start: usize, start_column: usize) !Token {
    // Raw byte string (br"" or rb"") - treat as byte string with no escape processing
    return tokenizePrefixedString(self, start, start_column, .byte);
}

pub fn tokenizeOperatorOrDelimiter(self: *Lexer, start: usize, start_column: usize, paren_depth: *usize) !?Token {
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
        ':' => blk: {
            if (self.peek() == '=') {
                _ = self.advance();
                break :blk .ColonEq;
            }
            break :blk .Colon;
        },
        '.' => blk: {
            // Check for ellipsis (...)
            if (self.peek() == '.' and self.peekAhead(1) == '.') {
                _ = self.advance(); // consume second dot
                _ = self.advance(); // consume third dot
                break :blk .Ellipsis;
            }
            break :blk .Dot;
        },
        '+' => blk: {
            if (self.peek() == '=') {
                _ = self.advance();
                break :blk .PlusEq;
            }
            break :blk .Plus;
        },
        '%' => blk: {
            if (self.peek() == '=') {
                _ = self.advance();
                break :blk .PercentEq;
            }
            break :blk .Percent;
        },
        '-' => blk: {
            if (self.peek() == '=') {
                _ = self.advance();
                break :blk .MinusEq;
            } else if (self.peek() == '>') {
                _ = self.advance();
                break :blk .Arrow;
            }
            break :blk .Minus;
        },
        '*' => blk: {
            if (self.peek() == '*') {
                _ = self.advance();
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .StarStarEq;
                }
                break :blk .DoubleStar;
            } else if (self.peek() == '=') {
                _ = self.advance();
                break :blk .StarEq;
            }
            break :blk .Star;
        },
        '/' => blk: {
            if (self.peek() == '/') {
                _ = self.advance();
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .DoubleSlashEq;
                }
                break :blk .DoubleSlash;
            } else if (self.peek() == '=') {
                _ = self.advance();
                break :blk .SlashEq;
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
            std.debug.print("UnexpectedCharacter '!' at line {d}, col {d} (standalone ! not supported, only !=)\n", .{ self.line, start_column });
            return error.UnexpectedCharacter;
        },
        '<' => blk: {
            if (self.peek() == '<') {
                _ = self.advance();
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .LtLtEq;
                }
                break :blk .LtLt;
            } else if (self.peek() == '=') {
                _ = self.advance();
                break :blk .LtEq;
            }
            break :blk .Lt;
        },
        '>' => blk: {
            if (self.peek() == '>') {
                _ = self.advance();
                if (self.peek() == '=') {
                    _ = self.advance();
                    break :blk .GtGtEq;
                }
                break :blk .GtGt;
            } else if (self.peek() == '=') {
                _ = self.advance();
                break :blk .GtEq;
            }
            break :blk .Gt;
        },
        '&' => blk: {
            if (self.peek() == '=') {
                _ = self.advance();
                break :blk .AmpersandEq;
            }
            break :blk .Ampersand;
        },
        '|' => blk: {
            if (self.peek() == '=') {
                _ = self.advance();
                break :blk .PipeEq;
            }
            break :blk .Pipe;
        },
        '^' => blk: {
            if (self.peek() == '=') {
                _ = self.advance();
                break :blk .CaretEq;
            }
            break :blk .Caret;
        },
        '~' => .Tilde,
        '@' => blk: {
            if (self.peek() == '=') {
                _ = self.advance();
                break :blk .AtEq;
            }
            break :blk .At;
        },
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

pub fn handleIndentation(self: *Lexer, tokens: *std.ArrayList(Token)) !usize {
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
