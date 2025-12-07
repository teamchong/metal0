/// pyctype - Locale-independent Character Type Functions
/// Mirrors cpython/Python/pyctype.c
///
/// This module provides locale-independent character classification
/// functions for ASCII characters, used internally by Python.

const std = @import("std");

// ============================================================================
// Character Type Flags
// ============================================================================

/// Character type flags
pub const CTF_LOWER: u32 = 0x01;
pub const CTF_UPPER: u32 = 0x02;
pub const CTF_ALPHA: u32 = CTF_LOWER | CTF_UPPER;
pub const CTF_DIGIT: u32 = 0x04;
pub const CTF_ALNUM: u32 = CTF_ALPHA | CTF_DIGIT;
pub const CTF_SPACE: u32 = 0x08;
pub const CTF_XDIGIT: u32 = 0x10;

// ============================================================================
// Character Type Table
// ============================================================================

/// Character type lookup table (256 entries for all byte values)
pub const ctype_table: [256]u32 = init: {
    var table: [256]u32 = [_]u32{0} ** 256;

    // Whitespace characters: \t \n \v \f \r and space
    table[0x09] = CTF_SPACE; // \t
    table[0x0a] = CTF_SPACE; // \n
    table[0x0b] = CTF_SPACE; // \v
    table[0x0c] = CTF_SPACE; // \f
    table[0x0d] = CTF_SPACE; // \r
    table[0x20] = CTF_SPACE; // space

    // Digits 0-9 (also hex digits)
    for ('0'..'9' + 1) |c| {
        table[c] = CTF_DIGIT | CTF_XDIGIT;
    }

    // Uppercase A-F (also hex digits)
    for ('A'..'F' + 1) |c| {
        table[c] = CTF_UPPER | CTF_XDIGIT;
    }

    // Uppercase G-Z
    for ('G'..'Z' + 1) |c| {
        table[c] = CTF_UPPER;
    }

    // Lowercase a-f (also hex digits)
    for ('a'..'f' + 1) |c| {
        table[c] = CTF_LOWER | CTF_XDIGIT;
    }

    // Lowercase g-z
    for ('g'..'z' + 1) |c| {
        table[c] = CTF_LOWER;
    }

    break :init table;
};

// ============================================================================
// Tolower Table
// ============================================================================

/// Character to lowercase lookup table
pub const ctype_tolower: [256]u8 = init: {
    var table: [256]u8 = undefined;

    // Initialize with identity mapping
    for (0..256) |i| {
        table[i] = @intCast(i);
    }

    // Map uppercase to lowercase
    for ('A'..'Z' + 1) |c| {
        table[c] = @intCast(c + 32); // 'a' - 'A' = 32
    }

    break :init table;
};

// ============================================================================
// Toupper Table
// ============================================================================

/// Character to uppercase lookup table
pub const ctype_toupper: [256]u8 = init: {
    var table: [256]u8 = undefined;

    // Initialize with identity mapping
    for (0..256) |i| {
        table[i] = @intCast(i);
    }

    // Map lowercase to uppercase
    for ('a'..'z' + 1) |c| {
        table[c] = @intCast(c - 32); // 'A' - 'a' = -32
    }

    break :init table;
};

// ============================================================================
// Character Classification Functions
// ============================================================================

/// Check if character is lowercase
pub fn isLower(c: u8) bool {
    return ctype_table[c] & CTF_LOWER != 0;
}

/// Check if character is uppercase
pub fn isUpper(c: u8) bool {
    return ctype_table[c] & CTF_UPPER != 0;
}

/// Check if character is alphabetic
pub fn isAlpha(c: u8) bool {
    return ctype_table[c] & CTF_ALPHA != 0;
}

/// Check if character is a digit
pub fn isDigit(c: u8) bool {
    return ctype_table[c] & CTF_DIGIT != 0;
}

/// Check if character is alphanumeric
pub fn isAlnum(c: u8) bool {
    return ctype_table[c] & CTF_ALNUM != 0;
}

/// Check if character is whitespace
pub fn isSpace(c: u8) bool {
    return ctype_table[c] & CTF_SPACE != 0;
}

/// Check if character is a hex digit
pub fn isXdigit(c: u8) bool {
    return ctype_table[c] & CTF_XDIGIT != 0;
}

/// Convert character to lowercase
pub fn toLower(c: u8) u8 {
    return ctype_tolower[c];
}

/// Convert character to uppercase
pub fn toUpper(c: u8) u8 {
    return ctype_toupper[c];
}

// ============================================================================
// Additional Python-compatible Functions
// ============================================================================

/// Check if character is ASCII
pub fn isAscii(c: u8) bool {
    return c < 128;
}

/// Check if character is printable
pub fn isPrint(c: u8) bool {
    return c >= 0x20 and c < 0x7f;
}

/// Check if character is a control character
pub fn isControl(c: u8) bool {
    return c < 0x20 or c == 0x7f;
}

/// Check if character is a blank (space or tab)
pub fn isBlank(c: u8) bool {
    return c == ' ' or c == '\t';
}

/// Check if character is a valid identifier start (Python rules)
pub fn isIdentifierStart(c: u8) bool {
    return isAlpha(c) or c == '_';
}

/// Check if character is a valid identifier continuation
pub fn isIdentifierContinue(c: u8) bool {
    return isAlnum(c) or c == '_';
}

// ============================================================================
// String Functions
// ============================================================================

/// Convert string to lowercase (in-place)
pub fn strToLower(str: []u8) void {
    for (str) |*c| {
        c.* = toLower(c.*);
    }
}

/// Convert string to uppercase (in-place)
pub fn strToUpper(str: []u8) void {
    for (str) |*c| {
        c.* = toUpper(c.*);
    }
}

/// Compare strings case-insensitively
pub fn strCaseCmp(a: []const u8, b: []const u8) i32 {
    const len = @min(a.len, b.len);
    for (0..len) |i| {
        const ca = toLower(a[i]);
        const cb = toLower(b[i]);
        if (ca != cb) {
            return @as(i32, ca) - @as(i32, cb);
        }
    }
    if (a.len < b.len) return -1;
    if (a.len > b.len) return 1;
    return 0;
}

/// Check if string is all lowercase
pub fn strIsLower(str: []const u8) bool {
    var has_cased = false;
    for (str) |c| {
        if (isUpper(c)) return false;
        if (isLower(c)) has_cased = true;
    }
    return has_cased;
}

/// Check if string is all uppercase
pub fn strIsUpper(str: []const u8) bool {
    var has_cased = false;
    for (str) |c| {
        if (isLower(c)) return false;
        if (isUpper(c)) has_cased = true;
    }
    return has_cased;
}

/// Check if string is all digits
pub fn strIsDigit(str: []const u8) bool {
    if (str.len == 0) return false;
    for (str) |c| {
        if (!isDigit(c)) return false;
    }
    return true;
}

/// Check if string is all whitespace
pub fn strIsSpace(str: []const u8) bool {
    if (str.len == 0) return false;
    for (str) |c| {
        if (!isSpace(c)) return false;
    }
    return true;
}

/// Check if string is all alphanumeric
pub fn strIsAlnum(str: []const u8) bool {
    if (str.len == 0) return false;
    for (str) |c| {
        if (!isAlnum(c)) return false;
    }
    return true;
}

/// Check if string is all alphabetic
pub fn strIsAlpha(str: []const u8) bool {
    if (str.len == 0) return false;
    for (str) |c| {
        if (!isAlpha(c)) return false;
    }
    return true;
}

// ============================================================================
// Digit Value Functions
// ============================================================================

/// Get numeric value of a digit character (0-9)
pub fn digitValue(c: u8) ?u8 {
    if (c >= '0' and c <= '9') {
        return c - '0';
    }
    return null;
}

/// Get numeric value of a hex digit character
pub fn hexDigitValue(c: u8) ?u8 {
    if (c >= '0' and c <= '9') {
        return c - '0';
    } else if (c >= 'a' and c <= 'f') {
        return c - 'a' + 10;
    } else if (c >= 'A' and c <= 'F') {
        return c - 'A' + 10;
    }
    return null;
}

/// Digit value table for bases 2-36
pub const digit_value: [256]u8 = init: {
    var table: [256]u8 = [_]u8{255} ** 256; // 255 = invalid

    // Digits 0-9
    for ('0'..'9' + 1) |c| {
        table[c] = @intCast(c - '0');
    }

    // Lowercase a-z (values 10-35)
    for ('a'..'z' + 1) |c| {
        table[c] = @intCast(c - 'a' + 10);
    }

    // Uppercase A-Z (values 10-35)
    for ('A'..'Z' + 1) |c| {
        table[c] = @intCast(c - 'A' + 10);
    }

    break :init table;
};

/// Get value of digit in given base
pub fn digitValueBase(c: u8, base: u8) ?u8 {
    const val = digit_value[c];
    if (val < base) {
        return val;
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

test "is lower" {
    try std.testing.expect(isLower('a'));
    try std.testing.expect(isLower('z'));
    try std.testing.expect(!isLower('A'));
    try std.testing.expect(!isLower('0'));
}

test "is upper" {
    try std.testing.expect(isUpper('A'));
    try std.testing.expect(isUpper('Z'));
    try std.testing.expect(!isUpper('a'));
    try std.testing.expect(!isUpper('0'));
}

test "is digit" {
    try std.testing.expect(isDigit('0'));
    try std.testing.expect(isDigit('9'));
    try std.testing.expect(!isDigit('a'));
    try std.testing.expect(!isDigit('A'));
}

test "is space" {
    try std.testing.expect(isSpace(' '));
    try std.testing.expect(isSpace('\t'));
    try std.testing.expect(isSpace('\n'));
    try std.testing.expect(!isSpace('a'));
}

test "is xdigit" {
    try std.testing.expect(isXdigit('0'));
    try std.testing.expect(isXdigit('9'));
    try std.testing.expect(isXdigit('a'));
    try std.testing.expect(isXdigit('f'));
    try std.testing.expect(isXdigit('A'));
    try std.testing.expect(isXdigit('F'));
    try std.testing.expect(!isXdigit('g'));
    try std.testing.expect(!isXdigit('G'));
}

test "to lower" {
    try std.testing.expectEqual(@as(u8, 'a'), toLower('A'));
    try std.testing.expectEqual(@as(u8, 'z'), toLower('Z'));
    try std.testing.expectEqual(@as(u8, 'a'), toLower('a'));
    try std.testing.expectEqual(@as(u8, '0'), toLower('0'));
}

test "to upper" {
    try std.testing.expectEqual(@as(u8, 'A'), toUpper('a'));
    try std.testing.expectEqual(@as(u8, 'Z'), toUpper('z'));
    try std.testing.expectEqual(@as(u8, 'A'), toUpper('A'));
    try std.testing.expectEqual(@as(u8, '0'), toUpper('0'));
}

test "str case cmp" {
    try std.testing.expectEqual(@as(i32, 0), strCaseCmp("hello", "HELLO"));
    try std.testing.expectEqual(@as(i32, 0), strCaseCmp("ABC", "abc"));
    try std.testing.expect(strCaseCmp("abc", "abd") < 0);
    try std.testing.expect(strCaseCmp("abd", "abc") > 0);
}

test "digit value" {
    try std.testing.expectEqual(@as(?u8, 0), digitValue('0'));
    try std.testing.expectEqual(@as(?u8, 9), digitValue('9'));
    try std.testing.expectEqual(@as(?u8, null), digitValue('a'));
}

test "hex digit value" {
    try std.testing.expectEqual(@as(?u8, 0), hexDigitValue('0'));
    try std.testing.expectEqual(@as(?u8, 10), hexDigitValue('a'));
    try std.testing.expectEqual(@as(?u8, 15), hexDigitValue('F'));
    try std.testing.expectEqual(@as(?u8, null), hexDigitValue('g'));
}

test "digit value base" {
    try std.testing.expectEqual(@as(?u8, 7), digitValueBase('7', 10));
    try std.testing.expectEqual(@as(?u8, null), digitValueBase('8', 8));
    try std.testing.expectEqual(@as(?u8, 15), digitValueBase('f', 16));
    try std.testing.expectEqual(@as(?u8, 35), digitValueBase('z', 36));
}
