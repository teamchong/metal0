//! tomllib._re - Regular expressions for TOML parsing
//! Reference: cpython/Lib/tomllib/_re.py
//!
//! Internal regex patterns for TOML lexer.

const std = @import("std");

/// TOML key pattern
pub const BARE_KEY_PATTERN = "^[A-Za-z0-9_-]+";

/// TOML basic string pattern
pub const BASIC_STRING_PATTERN = "^\"([^\"\\\\]|\\\\.)*\"";

/// TOML literal string pattern
pub const LITERAL_STRING_PATTERN = "^'[^']*'";

/// TOML multiline basic string pattern
pub const ML_BASIC_STRING_PATTERN = "^\"\"\".+?\"\"\"";

/// TOML multiline literal string pattern
pub const ML_LITERAL_STRING_PATTERN = "^'''.+?'''";

/// TOML integer pattern
pub const INTEGER_PATTERN = "^[+-]?(0|[1-9](_?[0-9])*)";

/// TOML hex integer pattern
pub const HEX_INTEGER_PATTERN = "^0[xX][0-9A-Fa-f](_?[0-9A-Fa-f])*";

/// TOML octal integer pattern
pub const OCT_INTEGER_PATTERN = "^0[oO][0-7](_?[0-7])*";

/// TOML binary integer pattern
pub const BIN_INTEGER_PATTERN = "^0[bB][01](_?[01])*";

/// TOML float pattern
pub const FLOAT_PATTERN = "^[+-]?(([0-9](_?[0-9])*\\.([0-9](_?[0-9])*)?([eE][+-]?[0-9](_?[0-9])*)?)|([eE][+-]?[0-9](_?[0-9])*)|inf|nan)";

/// TOML date pattern (YYYY-MM-DD)
pub const DATE_PATTERN = "^[0-9]{4}-[0-9]{2}-[0-9]{2}";

/// TOML time pattern (HH:MM:SS)
pub const TIME_PATTERN = "^[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?";

/// TOML datetime pattern
pub const DATETIME_PATTERN = "^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}";

/// Check if character is valid for bare key
pub fn isBareKeyChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '-';
}

/// Check if string is a valid bare key
pub fn isValidBareKey(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        if (!isBareKeyChar(c)) return false;
    }
    return true;
}

/// Match a basic string at the start of input
pub fn matchBasicString(input: []const u8) ?usize {
    if (input.len < 2 or input[0] != '"') return null;

    var i: usize = 1;
    while (i < input.len) {
        if (input[i] == '"') {
            return i + 1;
        } else if (input[i] == '\\' and i + 1 < input.len) {
            i += 2;
        } else {
            i += 1;
        }
    }
    return null;
}

/// Match a literal string at the start of input
pub fn matchLiteralString(input: []const u8) ?usize {
    if (input.len < 2 or input[0] != '\'') return null;

    var i: usize = 1;
    while (i < input.len) {
        if (input[i] == '\'') {
            return i + 1;
        }
        i += 1;
    }
    return null;
}

/// Match an integer at the start of input
pub fn matchInteger(input: []const u8) ?usize {
    if (input.len == 0) return null;

    var i: usize = 0;

    // Optional sign
    if (input[i] == '+' or input[i] == '-') {
        i += 1;
    }

    if (i >= input.len) return null;

    // Check for special prefixes
    if (input[i] == '0' and i + 1 < input.len) {
        const next = input[i + 1];
        if (next == 'x' or next == 'X' or next == 'o' or next == 'O' or next == 'b' or next == 'B') {
            i += 2;
            while (i < input.len and (std.ascii.isHex(input[i]) or input[i] == '_')) {
                i += 1;
            }
            return if (i > 2) i else null;
        }
    }

    // Decimal
    const start = i;
    while (i < input.len and (std.ascii.isDigit(input[i]) or input[i] == '_')) {
        i += 1;
    }

    return if (i > start) i else null;
}

// ============================================================================
// Tests
// ============================================================================

test "isBareKeyChar" {
    try std.testing.expect(isBareKeyChar('a'));
    try std.testing.expect(isBareKeyChar('Z'));
    try std.testing.expect(isBareKeyChar('0'));
    try std.testing.expect(isBareKeyChar('_'));
    try std.testing.expect(isBareKeyChar('-'));
    try std.testing.expect(!isBareKeyChar(' '));
    try std.testing.expect(!isBareKeyChar('.'));
}

test "isValidBareKey" {
    try std.testing.expect(isValidBareKey("key"));
    try std.testing.expect(isValidBareKey("key_name"));
    try std.testing.expect(isValidBareKey("key-name"));
    try std.testing.expect(!isValidBareKey(""));
    try std.testing.expect(!isValidBareKey("key.name"));
}

test "matchBasicString" {
    try std.testing.expectEqual(@as(?usize, 7), matchBasicString("\"hello\""));
    try std.testing.expectEqual(@as(?usize, null), matchBasicString("hello"));
}

test "matchInteger" {
    try std.testing.expectEqual(@as(?usize, 2), matchInteger("42"));
    try std.testing.expectEqual(@as(?usize, 3), matchInteger("-42"));
    try std.testing.expectEqual(@as(?usize, 4), matchInteger("0xff"));
}
