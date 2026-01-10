//! re._constants - Regular expression constants
//! Reference: cpython/Lib/re/_constants.py
//!
//! Internal constants used by the regex compiler and engine.

const std = @import("std");

/// Magic number for compiled pattern format
pub const MAGIC: u32 = 20220318;

/// Maximum repeat count
pub const MAXREPEAT: u32 = 2147483647;

/// Minimum repeat count
pub const MINREPEAT: u32 = 0;

/// Maximum groups
pub const MAXGROUPS: u32 = 100;

/// Opcode names (for debugging)
pub const OPCODES = [_][]const u8{
    "FAILURE",
    "SUCCESS",
    "ANY",
    "ANY_ALL",
    "ASSERT",
    "ASSERT_NOT",
    "AT",
    "BRANCH",
    "CALL",
    "CATEGORY",
    "CHARSET",
    "BIGCHARSET",
    "GROUPREF",
    "GROUPREF_EXISTS",
    "IN",
    "INFO",
    "JUMP",
    "LITERAL",
    "MARK",
    "MAX_UNTIL",
    "MIN_UNTIL",
    "NOT_LITERAL",
    "NEGATE",
    "RANGE",
    "REPEAT",
    "REPEAT_ONE",
    "SUBPATTERN",
    "MIN_REPEAT_ONE",
    "ATOMIC_GROUP",
    "POSSESSIVE_REPEAT",
    "POSSESSIVE_REPEAT_ONE",
};

/// AT opcodes (anchors)
pub const AT = struct {
    pub const BEGINNING: u8 = 0; // ^
    pub const BEGINNING_LINE: u8 = 1; // ^ (MULTILINE)
    pub const BEGINNING_STRING: u8 = 2; // \A
    pub const BOUNDARY: u8 = 3; // \b
    pub const NON_BOUNDARY: u8 = 4; // \B
    pub const END: u8 = 5; // $
    pub const END_LINE: u8 = 6; // $ (MULTILINE)
    pub const END_STRING: u8 = 7; // \Z
    pub const LOC_BOUNDARY: u8 = 8; // \b (locale)
    pub const LOC_NON_BOUNDARY: u8 = 9; // \B (locale)
    pub const UNI_BOUNDARY: u8 = 10; // \b (unicode)
    pub const UNI_NON_BOUNDARY: u8 = 11; // \B (unicode)
};

/// CATEGORY opcodes (character classes)
pub const CATEGORY = struct {
    pub const DIGIT: u8 = 0; // \d
    pub const NOT_DIGIT: u8 = 1; // \D
    pub const SPACE: u8 = 2; // \s
    pub const NOT_SPACE: u8 = 3; // \S
    pub const WORD: u8 = 4; // \w
    pub const NOT_WORD: u8 = 5; // \W
    pub const LINEBREAK: u8 = 6; // line break
    pub const NOT_LINEBREAK: u8 = 7; // not line break
    pub const LOC_WORD: u8 = 8; // \w (locale)
    pub const LOC_NOT_WORD: u8 = 9; // \W (locale)
    pub const UNI_DIGIT: u8 = 10; // \d (unicode)
    pub const UNI_NOT_DIGIT: u8 = 11; // \D (unicode)
    pub const UNI_SPACE: u8 = 12; // \s (unicode)
    pub const UNI_NOT_SPACE: u8 = 13; // \S (unicode)
    pub const UNI_WORD: u8 = 14; // \w (unicode)
    pub const UNI_NOT_WORD: u8 = 15; // \W (unicode)
    pub const UNI_LINEBREAK: u8 = 16; // unicode line break
    pub const UNI_NOT_LINEBREAK: u8 = 17; // not unicode line break
};

/// Character set for \d (digits)
pub const DIGITS = "0123456789";

/// Character set for \s (whitespace)
pub const WHITESPACE = " \t\n\r\x0b\x0c";

/// Character set for \w (word characters)
pub const WORD_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_";

/// SRE_FLAG values (mirror Python's re module flags)
pub const SRE_FLAG = struct {
    pub const TEMPLATE: u32 = 1; // Deprecated
    pub const IGNORECASE: u32 = 2; // re.I
    pub const LOCALE: u32 = 4; // re.L
    pub const MULTILINE: u32 = 8; // re.M
    pub const DOTALL: u32 = 16; // re.S
    pub const UNICODE: u32 = 32; // re.U (default in Python 3)
    pub const VERBOSE: u32 = 64; // re.X
    pub const DEBUG: u32 = 128; // Debug mode
    pub const ASCII: u32 = 256; // re.A
};

/// SRE_INFO flags (pattern info)
pub const SRE_INFO = struct {
    pub const PREFIX: u32 = 1; // Has prefix
    pub const LITERAL: u32 = 2; // Literal pattern
    pub const CHARSET: u32 = 4; // Has charset
};

/// Error codes
pub const SRE_ERROR = struct {
    pub const ILLEGAL: i32 = -1;
    pub const STATE: i32 = -2;
    pub const RECURSION_LIMIT: i32 = -3;
    pub const MEMORY: i32 = -4;
    pub const INTERRUPTED: i32 = -5;
};

/// Get opcode name for debugging
pub fn getOpcodeName(opcode: u8) []const u8 {
    if (opcode < OPCODES.len) {
        return OPCODES[opcode];
    }
    return "UNKNOWN";
}

// ============================================================================
// Tests
// ============================================================================

test "AT constants" {
    try std.testing.expectEqual(@as(u8, 0), AT.BEGINNING);
    try std.testing.expectEqual(@as(u8, 3), AT.BOUNDARY);
}

test "CATEGORY constants" {
    try std.testing.expectEqual(@as(u8, 0), CATEGORY.DIGIT);
    try std.testing.expectEqual(@as(u8, 4), CATEGORY.WORD);
}

test "SRE_FLAG values" {
    try std.testing.expectEqual(@as(u32, 2), SRE_FLAG.IGNORECASE);
    try std.testing.expectEqual(@as(u32, 8), SRE_FLAG.MULTILINE);
}

test "getOpcodeName" {
    try std.testing.expectEqualStrings("FAILURE", getOpcodeName(0));
    try std.testing.expectEqualStrings("SUCCESS", getOpcodeName(1));
}
