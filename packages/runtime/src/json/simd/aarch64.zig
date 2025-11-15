/// NEON SIMD implementations for ARM64/AArch64
/// Processes 16 bytes at a time
const std = @import("std");
const scalar = @import("scalar.zig");

/// Find next special JSON character using NEON: { } [ ] : , " \
pub fn findSpecialCharNeon(data: []const u8, offset: usize) ?usize {
    if (data.len - offset < 16) {
        return scalar.findSpecialChar(data, offset);
    }

    var i = offset;
    const end = data.len - 16;

    while (i <= end) : (i += 16) {
        // Load 16 bytes
        const chunk: @Vector(16, u8) = data[i..][0..16].*;

        // Check for each special character
        const is_brace_open = chunk == @as(@Vector(16, u8), @splat('{'));
        const is_brace_close = chunk == @as(@Vector(16, u8), @splat('}'));
        const is_bracket_open = chunk == @as(@Vector(16, u8), @splat('['));
        const is_bracket_close = chunk == @as(@Vector(16, u8), @splat(']'));
        const is_colon = chunk == @as(@Vector(16, u8), @splat(':'));
        const is_comma = chunk == @as(@Vector(16, u8), @splat(','));
        const is_quote = chunk == @as(@Vector(16, u8), @splat('"'));
        const is_backslash = chunk == @as(@Vector(16, u8), @splat('\\'));

        // Combine all special character masks
        const is_special = is_brace_open | is_brace_close |
            is_bracket_open | is_bracket_close |
            is_colon | is_comma |
            is_quote | is_backslash;

        // Check if any special character found
        if (@reduce(.Or, is_special)) {
            // Find exact position within chunk
            for (0..16) |j| {
                if (is_special[j]) {
                    return i + j;
                }
            }
        }
    }

    // Handle remaining bytes with scalar
    return scalar.findSpecialChar(data, i);
}

/// Find closing quote using NEON, handling escapes
pub fn findClosingQuoteNeon(data: []const u8, offset: usize) ?usize {
    if (data.len - offset < 16) {
        return scalar.findClosingQuote(data, offset);
    }

    var i = offset;
    const end = data.len - 16;

    while (i <= end) : (i += 16) {
        const chunk: @Vector(16, u8) = data[i..][0..16].*;

        // Find quotes and backslashes
        const is_quote = chunk == @as(@Vector(16, u8), @splat('"'));
        const is_backslash = chunk == @as(@Vector(16, u8), @splat('\\'));

        // Check for control characters (< 0x20)
        const control_threshold: @Vector(16, u8) = @splat(0x20);
        const is_control = chunk < control_threshold;

        if (@reduce(.Or, is_control)) {
            // Invalid - control character found
            return null;
        }

        if (@reduce(.Or, is_quote | is_backslash)) {
            // Found quote or escape, process carefully
            for (0..16) |j| {
                const pos = i + j;
                const c = data[pos];

                if (c == '"') {
                    return pos;
                } else if (c == '\\') {
                    // Skip escaped character
                    i = pos + 1;
                    if (i >= data.len) return null;
                    break;
                }
            }
        }
    }

    return scalar.findClosingQuote(data, i);
}

/// Validate UTF-8 using NEON
pub fn validateUtf8Neon(data: []const u8) bool {
    if (data.len < 16) {
        return scalar.validateUtf8(data);
    }

    var i: usize = 0;
    const end = data.len - 16;

    while (i <= end) : (i += 16) {
        const chunk: @Vector(16, u8) = data[i..][0..16].*;

        // Fast path: Check if all bytes are ASCII
        const ascii_mask: @Vector(16, u8) = @splat(0x80);
        const has_high_bit = (chunk & ascii_mask) != @as(@Vector(16, u8), @splat(0));

        if (!@reduce(.Or, has_high_bit)) {
            // All ASCII, valid
            continue;
        }

        // Has multi-byte sequences, need careful validation
        // For now, fall back to scalar for this chunk
        if (!scalar.validateUtf8(data[i .. i + 16])) {
            return false;
        }
    }

    // Validate remainder
    return scalar.validateUtf8(data[i..]);
}

/// Count matching characters using NEON
pub fn countMatchingNeon(data: []const u8, target: u8) usize {
    if (data.len < 16) {
        return scalar.countMatching(data, target);
    }

    var count: usize = 0;
    var i: usize = 0;
    const end = data.len - 16;

    const target_vec: @Vector(16, u8) = @splat(target);

    while (i <= end) : (i += 16) {
        const chunk: @Vector(16, u8) = data[i..][0..16].*;
        const matches = chunk == target_vec;

        // Count true values
        for (0..16) |j| {
            if (matches[j]) count += 1;
        }
    }

    // Handle remainder
    count += scalar.countMatching(data[i..], target);

    return count;
}

/// Check if string has escapes using NEON
pub fn hasEscapesNeon(data: []const u8) bool {
    if (data.len < 16) {
        return scalar.hasEscapes(data);
    }

    var i: usize = 0;
    const end = data.len - 16;

    const backslash_vec: @Vector(16, u8) = @splat('\\');

    while (i <= end) : (i += 16) {
        const chunk: @Vector(16, u8) = data[i..][0..16].*;
        const has_backslash = chunk == backslash_vec;

        if (@reduce(.Or, has_backslash)) {
            return true;
        }
    }

    return scalar.hasEscapes(data[i..]);
}

/// Skip whitespace using NEON
pub fn skipWhitespaceNeon(data: []const u8, offset: usize) usize {
    if (data.len - offset < 16) {
        var i = offset;
        while (i < data.len) : (i += 1) {
            const c = data[i];
            if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
                return i;
            }
        }
        return data.len;
    }

    var i = offset;
    const end = data.len - 16;

    while (i <= end) : (i += 16) {
        const chunk: @Vector(16, u8) = data[i..][0..16].*;

        const is_space = chunk == @as(@Vector(16, u8), @splat(' '));
        const is_tab = chunk == @as(@Vector(16, u8), @splat('\t'));
        const is_newline = chunk == @as(@Vector(16, u8), @splat('\n'));
        const is_cr = chunk == @as(@Vector(16, u8), @splat('\r'));

        const is_whitespace = is_space | is_tab | is_newline | is_cr;

        // If any non-whitespace found
        if (!@reduce(.And, is_whitespace)) {
            // Find first non-whitespace
            for (0..16) |j| {
                if (!is_whitespace[j]) {
                    return i + j;
                }
            }
        }
    }

    // Handle remainder
    var pos = i;
    while (pos < data.len) : (pos += 1) {
        const c = data[pos];
        if (c != ' ' and c != '\t' and c != '\n' and c != '\r') {
            return pos;
        }
    }
    return data.len;
}

test "findSpecialCharNeon" {
    const data = "hello world, this is a test {with} special [chars]";
    const result = findSpecialCharNeon(data, 0);
    try std.testing.expectEqual(@as(?usize, 11), result); // comma
}

test "countMatchingNeon" {
    const data = "aaabbbcccaaabbb";
    try std.testing.expectEqual(@as(usize, 6), countMatchingNeon(data, 'a'));
    try std.testing.expectEqual(@as(usize, 6), countMatchingNeon(data, 'b'));
    try std.testing.expectEqual(@as(usize, 3), countMatchingNeon(data, 'c'));
}

test "hasEscapesNeon" {
    try std.testing.expect(!hasEscapesNeon("hello world"));
    try std.testing.expect(hasEscapesNeon("hello\\nworld"));
}
