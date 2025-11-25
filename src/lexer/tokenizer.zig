/// Tokenization logic for Python lexer
const std = @import("std");
const Token = @import("../lexer.zig").Token;
const TokenType = @import("../lexer.zig").TokenType;
const Lexer = @import("../lexer.zig").Lexer;
const FStringPart = @import("../lexer.zig").FStringPart;

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

pub fn tokenizeNumber(self: *Lexer, start: usize, start_column: usize) !Token {
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

    // Handle complex number suffix 'j' or 'J'
    const is_complex = if (self.peek()) |c| (c == 'j' or c == 'J') else false;
    if (is_complex) {
        _ = self.advance(); // consume 'j' or 'J'
    }

    const lexeme = self.source[start..self.current];
    return Token{
        .type = if (is_complex) .ComplexNumber else .Number,
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

pub fn tokenizeFString(self: *Lexer, start: usize, start_column: usize) !Token {
    const quote = self.advance().?; // Consume opening quote
    var parts = std.ArrayList(FStringPart){};

    var literal_start = self.current;

    // Parse f-string content
    while (self.peek() != quote and !self.isAtEnd()) {
        if (self.peek() == '{') {
            // Save any pending literal
            if (self.current > literal_start) {
                const literal_text = self.source[literal_start..self.current];
                try parts.append(self.allocator, .{ .literal = literal_text });
            }

            _ = self.advance(); // consume '{'

            // Check for escaped brace {{
            if (self.peek() == '{') {
                _ = self.advance();
                literal_start = self.current - 1; // Include single '{'
                continue;
            }

            // Parse expression inside {}
            const expr_start = self.current;
            var brace_depth: usize = 1;
            var has_format_spec = false;
            var has_conversion = false;
            var conversion_char: u8 = 0;
            var expr_end: usize = 0;
            var format_spec_start: usize = 0;

            while (brace_depth > 0 and !self.isAtEnd()) {
                const c = self.peek().?;

                if (c == '{') {
                    brace_depth += 1;
                } else if (c == '}') {
                    brace_depth -= 1;
                    if (brace_depth == 0) break;
                } else if (c == '!' and brace_depth == 1 and !has_conversion and !has_format_spec) {
                    // Conversion specifier !r, !s, or !a
                    expr_end = self.current;
                    _ = self.advance(); // consume '!'
                    const conv = self.peek();
                    if (conv == 'r' or conv == 's' or conv == 'a') {
                        has_conversion = true;
                        conversion_char = conv.?;
                        _ = self.advance(); // consume conversion char
                    }
                    // Continue to check for format spec
                } else if (c == ':' and brace_depth == 1 and !has_format_spec) {
                    // Format specifier
                    has_format_spec = true;
                    if (!has_conversion) {
                        expr_end = self.current;
                    }
                    _ = self.advance(); // consume ':'
                    format_spec_start = self.current;

                    // Parse format spec until }
                    while (self.peek() != '}' and !self.isAtEnd()) {
                        _ = self.advance();
                    }

                    const expr_text = self.source[expr_start..expr_end];
                    const format_spec = self.source[format_spec_start..self.current];

                    try parts.append(self.allocator, .{
                        .format_expr = .{
                            .expr = expr_text,
                            .format_spec = format_spec,
                            .conversion = if (has_conversion) conversion_char else null,
                        },
                    });

                    break;
                } else {
                    _ = self.advance();
                }
            }

            if (!has_format_spec) {
                if (!has_conversion) {
                    expr_end = self.current;
                }
                const expr_text = self.source[expr_start..expr_end];
                if (has_conversion) {
                    try parts.append(self.allocator, .{ .conv_expr = .{
                        .expr = expr_text,
                        .conversion = conversion_char,
                    } });
                } else {
                    try parts.append(self.allocator, .{ .expr = expr_text });
                }
            }

            if (self.peek() == '}') {
                _ = self.advance(); // consume '}'
            }

            literal_start = self.current;
        } else if (self.peek() == '\\') {
            _ = self.advance(); // Consume backslash
            if (!self.isAtEnd()) {
                _ = self.advance(); // Consume escaped character
            }
        } else {
            _ = self.advance();
        }
    }

    // Save any remaining literal
    if (self.current > literal_start) {
        const literal_text = self.source[literal_start..self.current];
        try parts.append(self.allocator, .{ .literal = literal_text });
    }

    if (!self.isAtEnd() and self.peek() == quote) {
        _ = self.advance(); // Consume closing quote
    }

    const lexeme = self.source[start..self.current];
    const parts_slice = try parts.toOwnedSlice(self.allocator);

    return Token{
        .type = .FString,
        .lexeme = lexeme,
        .line = self.line,
        .column = start_column,
        .fstring_parts = parts_slice,
    };
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
        '@' => .At,
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
