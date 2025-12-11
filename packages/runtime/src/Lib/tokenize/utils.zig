//! Utility functions for tokenization
//!
//! Module-level helper functions for encoding detection and token manipulation.

const std = @import("std");
const types = @import("types.zig");
const tokenizer_mod = @import("tokenizer.zig");

const TokenInfo = types.TokenInfo;
const Tokenizer = tokenizer_mod.Tokenizer;

// ============================================================================
// Module-Level Functions
// ============================================================================

/// Tokenize source code
pub fn tokenize(allocator: std.mem.Allocator, source: []const u8) ![]TokenInfo {
    var tokenizer = Tokenizer.init(allocator, source);
    defer tokenizer.deinit();

    var tokens: std.ArrayList(TokenInfo) = .{};
    errdefer tokens.deinit(allocator);

    while (tokenizer.next()) |token| {
        try tokens.append(allocator, token);
    }

    return tokens.toOwnedSlice(allocator);
}

/// Generate tokens from readline function
pub fn generate_tokens(allocator: std.mem.Allocator, readline: *const fn () ?[]const u8) ![]TokenInfo {
    var source: std.ArrayList(u8) = .{};
    defer source.deinit(allocator);

    while (readline()) |line| {
        try source.appendSlice(allocator, line);
        try source.append(allocator, '\n');
    }

    return tokenize(allocator, source.items);
}

/// Detect encoding from source
pub fn detect_encoding(source: []const u8) []const u8 {
    // Check for BOM
    if (source.len >= 3 and
        source[0] == 0xEF and source[1] == 0xBB and source[2] == 0xBF)
    {
        return "utf-8-sig";
    }

    // Check for encoding declaration in first two lines
    var line_count: u32 = 0;
    var pos: usize = 0;
    while (pos < source.len and line_count < 2) {
        const line_start = pos;
        while (pos < source.len and source[pos] != '\n') {
            pos += 1;
        }
        const line = source[line_start..pos];

        // Look for coding: or coding=
        if (std.mem.indexOf(u8, line, "coding")) |idx| {
            var enc_start = idx + 6;
            // Skip : or =
            while (enc_start < line.len and (line[enc_start] == ':' or line[enc_start] == '=' or line[enc_start] == ' ')) {
                enc_start += 1;
            }
            var enc_end = enc_start;
            while (enc_end < line.len and (std.ascii.isAlphanumeric(line[enc_end]) or line[enc_end] == '-' or line[enc_end] == '_')) {
                enc_end += 1;
            }
            if (enc_end > enc_start) {
                return line[enc_start..enc_end];
            }
        }

        if (pos < source.len) pos += 1;
        line_count += 1;
    }

    return "utf-8";
}

/// Untokenize tokens back to source
pub fn untokenize(allocator: std.mem.Allocator, tokens: []const TokenInfo) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var prev_row: u32 = 1;
    var prev_col: u32 = 0;

    for (tokens) |token| {
        // Add newlines if needed
        while (prev_row < token.start.line) {
            try result.append(allocator, '\n');
            prev_row += 1;
            prev_col = 0;
        }

        // Add spaces if needed
        while (prev_col < token.start.col) {
            try result.append(allocator, ' ');
            prev_col += 1;
        }

        // Add token string
        try result.appendSlice(allocator, token.string);
        prev_col = token.end.col;
        prev_row = token.end.line;
    }

    return result.toOwnedSlice(allocator);
}

/// Get name of token type
pub fn tok_name(tok_type: types.TokenType) []const u8 {
    return tok_type.name();
}

// ============================================================================
// Tests
// ============================================================================

test "tokenize simple" {
    const allocator = std.testing.allocator;
    const source = "x = 1";
    const tokens = try tokenize(allocator, source);
    defer allocator.free(tokens);

    try std.testing.expect(tokens.len >= 4);
    try std.testing.expectEqual(types.TokenType.NAME, tokens[0].type);
    try std.testing.expectEqualStrings("x", tokens[0].string);
}

test "tokenize string" {
    const allocator = std.testing.allocator;
    const source = "\"hello\"";
    const tokens = try tokenize(allocator, source);
    defer allocator.free(tokens);

    try std.testing.expect(tokens.len >= 1);
    try std.testing.expectEqual(types.TokenType.STRING, tokens[0].type);
}

test "tokenize number" {
    const allocator = std.testing.allocator;
    const source = "42 3.14 0xFF";
    const tokens = try tokenize(allocator, source);
    defer allocator.free(tokens);

    try std.testing.expect(tokens.len >= 3);
    try std.testing.expectEqual(types.TokenType.NUMBER, tokens[0].type);
    try std.testing.expectEqual(types.TokenType.NUMBER, tokens[1].type);
    try std.testing.expectEqual(types.TokenType.NUMBER, tokens[2].type);
}

test "detect_encoding" {
    try std.testing.expectEqualStrings("utf-8", detect_encoding("print('hello')"));
    try std.testing.expectEqualStrings("utf-8-sig", detect_encoding("\xEF\xBB\xBFprint('hello')"));
}

test "TokenType name" {
    try std.testing.expectEqualStrings("NAME", types.TokenType.NAME.name());
    try std.testing.expectEqualStrings("NUMBER", types.TokenType.NUMBER.name());
}
