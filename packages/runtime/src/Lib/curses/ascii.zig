//! curses.ascii - ASCII character classification
//! Reference: cpython/Lib/curses/ascii.py
//!
//! CPython __all__: NUL, SOH, STX, ETX, EOT, ENQ, ACK, BEL, BS, TAB, HT, LF, NL,
//!                  VT, FF, CR, SO, SI, DLE, DC1, DC2, DC3, DC4, NAK, SYN, ETB,
//!                  CAN, EM, SUB, ESC, FS, GS, RS, US, SP, DEL,
//!                  controlnames, isalnum, isalpha, isascii, isblank, iscntrl,
//!                  isdigit, isgraph, islower, isprint, ispunct, isspace,
//!                  isupper, isxdigit, isctrl, ismeta, ascii, ctrl, alt, unctrl
//!
//! ASCII character classification functions.

const std = @import("std");

// ============================================================================
// Control character constants
// ============================================================================

pub const NUL: u8 = 0x00;
pub const SOH: u8 = 0x01;
pub const STX: u8 = 0x02;
pub const ETX: u8 = 0x03;
pub const EOT: u8 = 0x04;
pub const ENQ: u8 = 0x05;
pub const ACK: u8 = 0x06;
pub const BEL: u8 = 0x07;
pub const BS: u8 = 0x08;
pub const TAB: u8 = 0x09;
pub const HT: u8 = 0x09;
pub const LF: u8 = 0x0A;
pub const NL: u8 = 0x0A;
pub const VT: u8 = 0x0B;
pub const FF: u8 = 0x0C;
pub const CR: u8 = 0x0D;
pub const SO: u8 = 0x0E;
pub const SI: u8 = 0x0F;
pub const DLE: u8 = 0x10;
pub const DC1: u8 = 0x11;
pub const DC2: u8 = 0x12;
pub const DC3: u8 = 0x13;
pub const DC4: u8 = 0x14;
pub const NAK: u8 = 0x15;
pub const SYN: u8 = 0x16;
pub const ETB: u8 = 0x17;
pub const CAN: u8 = 0x18;
pub const EM: u8 = 0x19;
pub const SUB: u8 = 0x1A;
pub const ESC: u8 = 0x1B;
pub const FS: u8 = 0x1C;
pub const GS: u8 = 0x1D;
pub const RS: u8 = 0x1E;
pub const US: u8 = 0x1F;
pub const SP: u8 = 0x20;
pub const DEL: u8 = 0x7F;

/// Control character names
pub const controlnames = [_][]const u8{
    "NUL", "SOH", "STX", "ETX", "EOT", "ENQ", "ACK", "BEL",
    "BS",  "HT",  "LF",  "VT",  "FF",  "CR",  "SO",  "SI",
    "DLE", "DC1", "DC2", "DC3", "DC4", "NAK", "SYN", "ETB",
    "CAN", "EM",  "SUB", "ESC", "FS",  "GS",  "RS",  "US",
    "SP",
};

// ============================================================================
// Character classification functions
// ============================================================================

/// Check if character is alphanumeric
pub fn isalnum(c: u8) bool {
    return std.ascii.isAlphanumeric(c);
}

/// Check if character is alphabetic
pub fn isalpha(c: u8) bool {
    return std.ascii.isAlphabetic(c);
}

/// Check if character is ASCII (0-127)
pub fn isascii(c: u8) bool {
    return c <= 127;
}

/// Check if character is blank (space or tab)
pub fn isblank(c: u8) bool {
    return c == ' ' or c == '\t';
}

/// Check if character is a control character
pub fn iscntrl(c: u8) bool {
    return c < 32 or c == 127;
}

/// Check if character is a digit
pub fn isdigit(c: u8) bool {
    return std.ascii.isDigit(c);
}

/// Check if character is graphical (printable except space)
pub fn isgraph(c: u8) bool {
    return c > 32 and c < 127;
}

/// Check if character is lowercase
pub fn islower(c: u8) bool {
    return std.ascii.isLower(c);
}

/// Check if character is printable
pub fn isprint(c: u8) bool {
    return c >= 32 and c < 127;
}

/// Check if character is punctuation
pub fn ispunct(c: u8) bool {
    return isgraph(c) and !isalnum(c);
}

/// Check if character is whitespace
pub fn isspace(c: u8) bool {
    return std.ascii.isWhitespace(c);
}

/// Check if character is uppercase
pub fn isupper(c: u8) bool {
    return std.ascii.isUpper(c);
}

/// Check if character is hexadecimal digit
pub fn isxdigit(c: u8) bool {
    return std.ascii.isHex(c);
}

/// Check if character is a control character (alias)
pub fn isctrl(c: u8) bool {
    return iscntrl(c);
}

/// Check if character has the meta bit set (bit 7)
pub fn ismeta(c: u8) bool {
    return c > 127;
}

// ============================================================================
// Character transformation functions
// ============================================================================

/// Strip the high bit from a character
pub fn ascii(c: u8) u8 {
    return c & 0x7F;
}

/// Convert to control character
pub fn ctrl(c: u8) u8 {
    return c & 0x1F;
}

/// Set the meta (high) bit
pub fn alt(c: u8) u8 {
    return c | 0x80;
}

/// Return a printable representation of a control character
pub fn unctrl(c: u8) []const u8 {
    if (c == DEL) {
        return "^?";
    } else if (iscntrl(c)) {
        return &[_]u8{ '^', c + 64 };
    } else if (isprint(c)) {
        return &[_]u8{c};
    } else {
        // Meta character
        return "!";
    }
}

// ============================================================================
// Tests
// ============================================================================

test "control character constants" {
    try std.testing.expectEqual(@as(u8, 0), NUL);
    try std.testing.expectEqual(@as(u8, 7), BEL);
    try std.testing.expectEqual(@as(u8, 9), TAB);
    try std.testing.expectEqual(@as(u8, 10), LF);
    try std.testing.expectEqual(@as(u8, 13), CR);
    try std.testing.expectEqual(@as(u8, 27), ESC);
    try std.testing.expectEqual(@as(u8, 32), SP);
    try std.testing.expectEqual(@as(u8, 127), DEL);
}

test "isalnum" {
    try std.testing.expect(isalnum('a'));
    try std.testing.expect(isalnum('Z'));
    try std.testing.expect(isalnum('5'));
    try std.testing.expect(!isalnum(' '));
    try std.testing.expect(!isalnum('!'));
}

test "isascii" {
    try std.testing.expect(isascii(0));
    try std.testing.expect(isascii(127));
    try std.testing.expect(!isascii(128));
    try std.testing.expect(!isascii(255));
}

test "iscntrl" {
    try std.testing.expect(iscntrl(0));
    try std.testing.expect(iscntrl(31));
    try std.testing.expect(iscntrl(127));
    try std.testing.expect(!iscntrl(32));
    try std.testing.expect(!iscntrl('A'));
}

test "isprint" {
    try std.testing.expect(isprint(' '));
    try std.testing.expect(isprint('A'));
    try std.testing.expect(isprint('~'));
    try std.testing.expect(!isprint(0));
    try std.testing.expect(!isprint(127));
}

test "ctrl and alt" {
    try std.testing.expectEqual(@as(u8, 1), ctrl('A'));
    try std.testing.expectEqual(@as(u8, 3), ctrl('C'));
    try std.testing.expectEqual(@as(u8, 0xC1), alt('A'));
}

test "ascii" {
    try std.testing.expectEqual(@as(u8, 'A'), ascii('A'));
    try std.testing.expectEqual(@as(u8, 'A'), ascii(0xC1)); // Strip high bit
}
