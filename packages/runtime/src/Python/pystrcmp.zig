/// pystrcmp - Python String Comparison
/// Mirrors cpython/Python/pystrcmp.c
///
/// This module provides locale-independent string comparison:
/// - ASCII case-insensitive comparison
/// - Natural ordering comparison
/// - Prefix/suffix matching

const std = @import("std");

// ============================================================================
// ASCII Case Conversion
// ============================================================================

/// Convert ASCII character to lowercase
pub fn asciiLower(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') {
        return c + ('a' - 'A');
    }
    return c;
}

/// Convert ASCII character to uppercase
pub fn asciiUpper(c: u8) u8 {
    if (c >= 'a' and c <= 'z') {
        return c - ('a' - 'A');
    }
    return c;
}

// ============================================================================
// Case-Insensitive Comparison
// ============================================================================

/// Compare two strings case-insensitively (ASCII only)
/// Returns:
///   < 0 if s1 < s2
///   = 0 if s1 == s2
///   > 0 if s1 > s2
pub fn PyOS_stricmp(s1: []const u8, s2: []const u8) i32 {
    const min_len = @min(s1.len, s2.len);

    for (0..min_len) |i| {
        const c1 = asciiLower(s1[i]);
        const c2 = asciiLower(s2[i]);

        if (c1 != c2) {
            return @as(i32, c1) - @as(i32, c2);
        }
    }

    // Strings match up to min_len, compare lengths
    if (s1.len < s2.len) return -1;
    if (s1.len > s2.len) return 1;
    return 0;
}

/// Compare n characters case-insensitively
pub fn PyOS_strnicmp(s1: []const u8, s2: []const u8, n: usize) i32 {
    const max_len = @min(n, @min(s1.len, s2.len));

    for (0..max_len) |i| {
        const c1 = asciiLower(s1[i]);
        const c2 = asciiLower(s2[i]);

        if (c1 != c2) {
            return @as(i32, c1) - @as(i32, c2);
        }
    }

    // Compare remaining length within n
    const s1_remaining = @min(n, s1.len) - max_len;
    const s2_remaining = @min(n, s2.len) - max_len;

    if (s1_remaining < s2_remaining) return -1;
    if (s1_remaining > s2_remaining) return 1;
    return 0;
}

// ============================================================================
// Equality Checks
// ============================================================================

/// Check if strings are equal (case-sensitive)
pub fn strEqual(s1: []const u8, s2: []const u8) bool {
    return std.mem.eql(u8, s1, s2);
}

/// Check if strings are equal case-insensitively
pub fn strEqualFold(s1: []const u8, s2: []const u8) bool {
    return PyOS_stricmp(s1, s2) == 0;
}

/// Check if s1 starts with prefix (case-sensitive)
pub fn startsWith(s: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, s, prefix);
}

/// Check if s1 starts with prefix (case-insensitive)
pub fn startsWithFold(s: []const u8, prefix: []const u8) bool {
    if (s.len < prefix.len) return false;
    return PyOS_strnicmp(s, prefix, prefix.len) == 0;
}

/// Check if s ends with suffix (case-sensitive)
pub fn endsWith(s: []const u8, suffix: []const u8) bool {
    return std.mem.endsWith(u8, s, suffix);
}

/// Check if s ends with suffix (case-insensitive)
pub fn endsWithFold(s: []const u8, suffix: []const u8) bool {
    if (s.len < suffix.len) return false;
    return PyOS_strnicmp(s[s.len - suffix.len ..], suffix, suffix.len) == 0;
}

// ============================================================================
// Natural Ordering
// ============================================================================

/// Compare strings with natural ordering (numbers sorted numerically)
/// "file2" < "file10"
pub fn naturalCompare(s1: []const u8, s2: []const u8) i32 {
    var i1: usize = 0;
    var i2: usize = 0;

    while (i1 < s1.len and i2 < s2.len) {
        const c1 = s1[i1];
        const c2 = s2[i2];

        // Both are digits - compare numerically
        if (isDigit(c1) and isDigit(c2)) {
            // Skip leading zeros
            while (i1 < s1.len and s1[i1] == '0') i1 += 1;
            while (i2 < s2.len and s2[i2] == '0') i2 += 1;

            // Count digits
            var len1: usize = 0;
            var len2: usize = 0;
            while (i1 + len1 < s1.len and isDigit(s1[i1 + len1])) len1 += 1;
            while (i2 + len2 < s2.len and isDigit(s2[i2 + len2])) len2 += 1;

            // Different number of digits
            if (len1 != len2) {
                return if (len1 < len2) @as(i32, -1) else @as(i32, 1);
            }

            // Same number of digits - compare lexicographically
            for (0..len1) |j| {
                const d1 = s1[i1 + j];
                const d2 = s2[i2 + j];
                if (d1 != d2) {
                    return @as(i32, d1) - @as(i32, d2);
                }
            }

            i1 += len1;
            i2 += len2;
        } else {
            // Compare characters
            if (c1 != c2) {
                return @as(i32, c1) - @as(i32, c2);
            }
            i1 += 1;
            i2 += 1;
        }
    }

    // Compare remaining length
    if (i1 < s1.len) return 1;
    if (i2 < s2.len) return -1;
    return 0;
}

/// Natural compare case-insensitive
pub fn naturalCompareFold(s1: []const u8, s2: []const u8) i32 {
    var i1: usize = 0;
    var i2: usize = 0;

    while (i1 < s1.len and i2 < s2.len) {
        const c1 = asciiLower(s1[i1]);
        const c2 = asciiLower(s2[i2]);

        if (isDigit(c1) and isDigit(c2)) {
            // Skip leading zeros
            while (i1 < s1.len and s1[i1] == '0') i1 += 1;
            while (i2 < s2.len and s2[i2] == '0') i2 += 1;

            var len1: usize = 0;
            var len2: usize = 0;
            while (i1 + len1 < s1.len and isDigit(s1[i1 + len1])) len1 += 1;
            while (i2 + len2 < s2.len and isDigit(s2[i2 + len2])) len2 += 1;

            if (len1 != len2) {
                return if (len1 < len2) @as(i32, -1) else @as(i32, 1);
            }

            for (0..len1) |j| {
                const d1 = s1[i1 + j];
                const d2 = s2[i2 + j];
                if (d1 != d2) {
                    return @as(i32, d1) - @as(i32, d2);
                }
            }

            i1 += len1;
            i2 += len2;
        } else {
            if (c1 != c2) {
                return @as(i32, c1) - @as(i32, c2);
            }
            i1 += 1;
            i2 += 1;
        }
    }

    if (i1 < s1.len) return 1;
    if (i2 < s2.len) return -1;
    return 0;
}

// ============================================================================
// Helper Functions
// ============================================================================

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

/// Find first occurrence of needle in haystack (case-sensitive)
pub fn strstr(haystack: []const u8, needle: []const u8) ?usize {
    return std.mem.indexOf(u8, haystack, needle);
}

/// Find first occurrence of needle in haystack (case-insensitive)
pub fn stristr(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (needle.len > haystack.len) return null;

    const end = haystack.len - needle.len + 1;
    for (0..end) |i| {
        if (PyOS_strnicmp(haystack[i..], needle, needle.len) == 0) {
            return i;
        }
    }
    return null;
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "stricmp" {
    try std.testing.expectEqual(@as(i32, 0), PyOS_stricmp("hello", "HELLO"));
    try std.testing.expectEqual(@as(i32, 0), PyOS_stricmp("ABC", "abc"));
    try std.testing.expect(PyOS_stricmp("abc", "abd") < 0);
    try std.testing.expect(PyOS_stricmp("abd", "abc") > 0);
    try std.testing.expect(PyOS_stricmp("abc", "abcd") < 0);
}

test "strnicmp" {
    try std.testing.expectEqual(@as(i32, 0), PyOS_strnicmp("hello", "HELLO", 5));
    try std.testing.expectEqual(@as(i32, 0), PyOS_strnicmp("helloworld", "HELLO", 5));
    try std.testing.expect(PyOS_strnicmp("abc", "abd", 3) < 0);
}

test "strEqual" {
    try std.testing.expect(strEqual("hello", "hello"));
    try std.testing.expect(!strEqual("hello", "HELLO"));
}

test "strEqualFold" {
    try std.testing.expect(strEqualFold("hello", "HELLO"));
    try std.testing.expect(strEqualFold("HeLLo", "hElLO"));
}

test "startsWith" {
    try std.testing.expect(startsWith("hello world", "hello"));
    try std.testing.expect(!startsWith("hello world", "world"));
}

test "startsWithFold" {
    try std.testing.expect(startsWithFold("Hello World", "HELLO"));
    try std.testing.expect(!startsWithFold("hello", "helloworld"));
}

test "endsWith" {
    try std.testing.expect(endsWith("hello world", "world"));
    try std.testing.expect(!endsWith("hello world", "hello"));
}

test "endsWithFold" {
    try std.testing.expect(endsWithFold("Hello World", "WORLD"));
}

test "natural compare" {
    try std.testing.expect(naturalCompare("file2", "file10") < 0);
    try std.testing.expect(naturalCompare("file10", "file2") > 0);
    try std.testing.expectEqual(@as(i32, 0), naturalCompare("file10", "file10"));
    try std.testing.expect(naturalCompare("file1", "file1b") < 0);
}

test "stristr" {
    try std.testing.expectEqual(@as(?usize, 6), stristr("Hello WORLD", "world"));
    try std.testing.expectEqual(@as(?usize, 0), stristr("Hello", "HELLO"));
    try std.testing.expect(stristr("hello", "xyz") == null);
}
