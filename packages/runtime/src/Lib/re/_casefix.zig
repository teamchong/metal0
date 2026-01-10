//! re._casefix - Case-insensitive regex support
//! Reference: cpython/Lib/re/_casefix.py
//!
//! Internal module for case-insensitive regex matching.
//! Provides Unicode case folding data for regex matching.

const std = @import("std");

/// ASCII case mapping (simple case for ASCII-only patterns)
pub const ASCII_UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
pub const ASCII_LOWER = "abcdefghijklmnopqrstuvwxyz";

/// Case fold a single ASCII character
pub fn casefold_ascii(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') {
        return c + 32; // Convert to lowercase
    }
    return c;
}

/// Case fold a string (ASCII only)
pub fn casefold_ascii_string(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = try allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| {
        result[i] = casefold_ascii(c);
    }
    return result;
}

/// Special case mappings that expand to multiple characters
/// e.g., German sharp s (ß) -> "ss"
pub const CASEFIX_CHARS = struct {
    /// ß (U+00DF) German sharp s
    pub const SHARP_S: u21 = 0x00DF;
    /// ſ (U+017F) Latin small letter long s
    pub const LONG_S: u21 = 0x017F;
    /// İ (U+0130) Latin capital letter I with dot above
    pub const I_DOT: u21 = 0x0130;

    /// Get case-folded expansion for special characters
    pub fn expand(c: u21) ?[]const u8 {
        return switch (c) {
            SHARP_S => "ss",
            LONG_S => "s",
            I_DOT => "i\xcc\x87", // i + combining dot above
            else => null,
        };
    }
};

/// Check if character needs special case handling
pub fn has_special_case(c: u21) bool {
    return CASEFIX_CHARS.expand(c) != null;
}

/// Binary search table for Unicode case folding
/// This is a simplified version - full implementation would include
/// all Unicode case folding rules
pub const CaseFoldEntry = struct {
    from: u21,
    to: u21,
};

/// Simple case fold pairs (subset of Unicode CaseFolding.txt)
pub const CASE_FOLD_TABLE = [_]CaseFoldEntry{
    .{ .from = 'A', .to = 'a' },
    .{ .from = 'B', .to = 'b' },
    .{ .from = 'C', .to = 'c' },
    .{ .from = 'D', .to = 'd' },
    .{ .from = 'E', .to = 'e' },
    .{ .from = 'F', .to = 'f' },
    .{ .from = 'G', .to = 'g' },
    .{ .from = 'H', .to = 'h' },
    .{ .from = 'I', .to = 'i' },
    .{ .from = 'J', .to = 'j' },
    .{ .from = 'K', .to = 'k' },
    .{ .from = 'L', .to = 'l' },
    .{ .from = 'M', .to = 'm' },
    .{ .from = 'N', .to = 'n' },
    .{ .from = 'O', .to = 'o' },
    .{ .from = 'P', .to = 'p' },
    .{ .from = 'Q', .to = 'q' },
    .{ .from = 'R', .to = 'r' },
    .{ .from = 'S', .to = 's' },
    .{ .from = 'T', .to = 't' },
    .{ .from = 'U', .to = 'u' },
    .{ .from = 'V', .to = 'v' },
    .{ .from = 'W', .to = 'w' },
    .{ .from = 'X', .to = 'x' },
    .{ .from = 'Y', .to = 'y' },
    .{ .from = 'Z', .to = 'z' },
};

/// Look up case folding for a character
pub fn case_fold(c: u21) u21 {
    for (CASE_FOLD_TABLE) |entry| {
        if (entry.from == c) return entry.to;
    }
    return c;
}

// ============================================================================
// Tests
// ============================================================================

test "casefold_ascii" {
    try std.testing.expectEqual(@as(u8, 'a'), casefold_ascii('A'));
    try std.testing.expectEqual(@as(u8, 'z'), casefold_ascii('Z'));
    try std.testing.expectEqual(@as(u8, 'a'), casefold_ascii('a'));
    try std.testing.expectEqual(@as(u8, '1'), casefold_ascii('1'));
}

test "casefold_ascii_string" {
    const allocator = std.testing.allocator;
    const result = try casefold_ascii_string(allocator, "Hello World!");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello world!", result);
}

test "case_fold" {
    try std.testing.expectEqual(@as(u21, 'a'), case_fold('A'));
    try std.testing.expectEqual(@as(u21, 'z'), case_fold('Z'));
    try std.testing.expectEqual(@as(u21, '1'), case_fold('1'));
}
