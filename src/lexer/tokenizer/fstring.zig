/// F-string tokenization logic
const std = @import("std");
const Token = @import("../../lexer.zig").Token;
const FStringPart = @import("../../lexer.zig").FStringPart;
const Lexer = @import("../../lexer.zig").Lexer;

pub fn tokenizeFString(self: *Lexer, start: usize, start_column: usize, is_raw: bool) !Token {
    const quote = self.advance().?; // Consume opening quote
    var parts = std.ArrayList(FStringPart){};
    errdefer parts.deinit(self.allocator);

    // Check for triple quotes
    const is_triple = (self.peek() == quote and self.peekAhead(1) == quote);
    if (is_triple) {
        _ = self.advance(); // consume second quote
        _ = self.advance(); // consume third quote
    }

    var literal_start = self.current;

    // Parse f-string content
    while (!self.isAtEnd()) {
        // Check for closing quotes
        if (is_triple) {
            if (self.peek() == quote and self.peekAhead(1) == quote and self.peekAhead(2) == quote) {
                break;
            }
        } else {
            // In raw strings, backslash before quote allows quote to be included (but backslash is preserved)
            // So \' in a single-quoted raw string is NOT the end, but literal backslash + quote
            if (self.peek() == quote) {
                // Check if preceded by odd number of backslashes (escape)
                var backslash_count: usize = 0;
                var pos = self.current;
                while (pos > 0 and self.source[pos - 1] == '\\') {
                    backslash_count += 1;
                    pos -= 1;
                }
                // Odd number of backslashes means quote is escaped (even in raw strings this allows including quotes)
                if (is_raw and backslash_count > 0 and backslash_count % 2 == 1) {
                    // Escaped quote in raw string - advance past quote and continue
                    _ = self.advance();
                    continue;
                }
                break;
            }
        }
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
            var bracket_depth: usize = 0; // Track [] for slice expressions
            var paren_depth: usize = 0; // Track () for function calls
            var in_string: u8 = 0; // Track string delimiters (', ", or 0 if not in string)
            var has_format_spec = false;
            var has_conversion = false;
            var conversion_char: u8 = 0;
            var expr_end: usize = 0;
            var format_spec_start: usize = 0;

            while (brace_depth > 0 and !self.isAtEnd()) {
                const c = self.peek().?;

                // Handle string literals inside expression - ignore braces while in strings
                if (in_string != 0) {
                    if (c == '\\') {
                        // Skip escaped char in string
                        _ = self.advance();
                        if (!self.isAtEnd()) _ = self.advance();
                        continue;
                    } else if (c == in_string) {
                        // Check for triple quote end
                        if (self.peekAhead(1) == in_string and self.peekAhead(2) == in_string) {
                            _ = self.advance();
                            _ = self.advance();
                            _ = self.advance();
                            in_string = 0;
                        } else {
                            _ = self.advance();
                            in_string = 0;
                        }
                        continue;
                    }
                    _ = self.advance();
                    continue;
                }

                // Check for string start
                if (c == '"' or c == '\'') {
                    // Check for triple quote
                    if (self.peekAhead(1) == c and self.peekAhead(2) == c) {
                        in_string = c;
                        _ = self.advance();
                        _ = self.advance();
                        _ = self.advance();
                    } else {
                        in_string = c;
                        _ = self.advance();
                    }
                    continue;
                }

                // Handle # comment inside f-string expression - skip to end of line
                if (c == '#') {
                    while (!self.isAtEnd()) {
                        const ch = self.peek().?;
                        if (ch == '\n') break;
                        _ = self.advance();
                    }
                    continue;
                }

                if (c == '{') {
                    brace_depth += 1;
                } else if (c == '}') {
                    brace_depth -= 1;
                    if (brace_depth == 0) break;
                } else if (c == '[') {
                    bracket_depth += 1;
                    _ = self.advance();
                    continue;
                } else if (c == ']') {
                    if (bracket_depth > 0) bracket_depth -= 1;
                    _ = self.advance();
                    continue;
                } else if (c == '(') {
                    paren_depth += 1;
                    _ = self.advance();
                    continue;
                } else if (c == ')') {
                    if (paren_depth > 0) paren_depth -= 1;
                    _ = self.advance();
                    continue;
                } else if (c == '!' and brace_depth == 1 and bracket_depth == 0 and paren_depth == 0 and !has_conversion and !has_format_spec) {
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
                } else if (c == ':' and brace_depth == 1 and bracket_depth == 0 and paren_depth == 0 and !has_format_spec) {
                    // Format specifier
                    has_format_spec = true;
                    if (!has_conversion) {
                        expr_end = self.current;
                    }
                    _ = self.advance(); // consume ':'
                    format_spec_start = self.current;

                    // Parse format spec until } - but track nested braces!
                    // Format specs like {value:{ width}.{precision}} have nested expressions
                    var format_brace_depth: usize = 0;
                    while (!self.isAtEnd()) {
                        const fc = self.peek().?;
                        if (fc == '{') {
                            format_brace_depth += 1;
                        } else if (fc == '}') {
                            if (format_brace_depth == 0) break;
                            format_brace_depth -= 1;
                        }
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
        } else if (self.peek() == '\\' and !is_raw) {
            // Only process backslash escapes in non-raw f-strings
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

    // Consume closing quote(s)
    if (!self.isAtEnd() and self.peek() == quote) {
        _ = self.advance(); // Consume first closing quote
        if (is_triple) {
            if (self.peek() == quote) _ = self.advance(); // Consume second closing quote
            if (self.peek() == quote) _ = self.advance(); // Consume third closing quote
        }
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
