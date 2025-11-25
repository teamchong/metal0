/// F-string tokenization logic
const std = @import("std");
const Token = @import("../../lexer.zig").Token;
const FStringPart = @import("../../lexer.zig").FStringPart;
const Lexer = @import("../../lexer.zig").Lexer;

pub fn tokenizeFString(self: *Lexer, start: usize, start_column: usize) !Token {
    const quote = self.advance().?; // Consume opening quote
    var parts = std.ArrayList(FStringPart){};
    errdefer parts.deinit(self.allocator);

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
