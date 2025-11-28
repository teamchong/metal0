/// Number literal tokenization logic
const Token = @import("../../lexer.zig").Token;
const Lexer = @import("../../lexer.zig").Lexer;

pub fn isHexDigit(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

/// Check if character is part of a numeric literal (digit or underscore separator)
pub fn isNumericChar(c: u8) bool {
    return (c >= '0' and c <= '9') or c == '_';
}

pub fn tokenizeNumber(self: *Lexer, start: usize, start_column: usize) !Token {
    // Check for base prefixes: 0x (hex), 0o (octal), 0b (binary)
    // peek() returns current char (the '0'), peekAhead(1) returns next char (the prefix)
    if (self.peek() == '0' and self.peekAhead(1) != null) {
        const prefix = self.peekAhead(1).?;
        if (prefix == 'x' or prefix == 'X') {
            // Hexadecimal: 0x... (allows underscores like 0xFF_FF)
            _ = self.advance(); // consume '0'
            _ = self.advance(); // consume 'x' or 'X'
            while (self.peek()) |c| {
                if (isHexDigit(c) or c == '_') {
                    _ = self.advance();
                } else {
                    break;
                }
            }
            const lexeme = self.source[start..self.current];
            return Token{
                .type = .Number,
                .lexeme = lexeme,
                .line = self.line,
                .column = start_column,
            };
        } else if (prefix == 'o' or prefix == 'O') {
            // Octal: 0o... (allows underscores like 0o77_77)
            _ = self.advance(); // consume '0'
            _ = self.advance(); // consume 'o' or 'O'
            while (self.peek()) |c| {
                if ((c >= '0' and c <= '7') or c == '_') {
                    _ = self.advance();
                } else {
                    break;
                }
            }
            const lexeme = self.source[start..self.current];
            return Token{
                .type = .Number,
                .lexeme = lexeme,
                .line = self.line,
                .column = start_column,
            };
        } else if (prefix == 'b' or prefix == 'B') {
            // Binary: 0b... (allows underscores like 0b1111_0000)
            _ = self.advance(); // consume '0'
            _ = self.advance(); // consume 'b' or 'B'
            while (self.peek()) |c| {
                if (c == '0' or c == '1' or c == '_') {
                    _ = self.advance();
                } else {
                    break;
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
    }

    // Decimal number (allows underscores like 1_000_000)
    while (self.peek()) |c| {
        if (self.isDigit(c) or c == '_') {
            _ = self.advance();
        } else {
            break;
        }
    }

    // Handle decimal point
    // Python allows: 1.5, 1., .5 - we handle 1.5 and 1. here
    if (self.peek() == '.') {
        const next = self.peekAhead(1);
        // Check it's not an attribute access like 1.bit_length() or ellipsis 1...
        const is_attr_or_ellipsis = if (next) |n| (n >= 'a' and n <= 'z') or (n >= 'A' and n <= 'Z') or n == '_' or n == '.' else false;
        if (!is_attr_or_ellipsis) {
            _ = self.advance(); // consume '.'
            // Consume any fractional digits (optional - 1. is valid)
            while (self.peek()) |c| {
                if (self.isDigit(c) or c == '_') {
                    _ = self.advance();
                } else {
                    break;
                }
            }
        }
    }

    // Handle scientific notation (e.g., 1.23e167, 1e-5, 2E+10)
    if (self.peek()) |c| {
        if (c == 'e' or c == 'E') {
            const after_e = self.peekAhead(1);
            // Check if next is digit, + or -
            if (after_e) |next| {
                if (self.isDigit(next) or next == '+' or next == '-') {
                    _ = self.advance(); // consume 'e' or 'E'
                    // Consume optional sign
                    if (self.peek() == '+' or self.peek() == '-') {
                        _ = self.advance();
                    }
                    // Consume exponent digits
                    while (self.peek()) |d| {
                        if (self.isDigit(d) or d == '_') {
                            _ = self.advance();
                        } else {
                            break;
                        }
                    }
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
