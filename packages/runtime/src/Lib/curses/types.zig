//! Curses error types and constants
//!
//! Defines error types, color constants, attribute flags, and key codes
//! used throughout the curses module.

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const CursesError = error{
    InitializationFailed,
    NotInitialized,
    InvalidWindow,
    InvalidAttribute,
    IoError,
    UnsupportedPlatform,
};

// ============================================================================
// Constants - Colors
// ============================================================================

pub const COLOR_BLACK = 0;
pub const COLOR_RED = 1;
pub const COLOR_GREEN = 2;
pub const COLOR_YELLOW = 3;
pub const COLOR_BLUE = 4;
pub const COLOR_MAGENTA = 5;
pub const COLOR_CYAN = 6;
pub const COLOR_WHITE = 7;

// ============================================================================
// Constants - Attributes
// ============================================================================

pub const A_NORMAL: u32 = 0;
pub const A_STANDOUT: u32 = 1 << 8;
pub const A_UNDERLINE: u32 = 1 << 9;
pub const A_REVERSE: u32 = 1 << 10;
pub const A_BLINK: u32 = 1 << 11;
pub const A_DIM: u32 = 1 << 12;
pub const A_BOLD: u32 = 1 << 13;
pub const A_ALTCHARSET: u32 = 1 << 14;
pub const A_INVIS: u32 = 1 << 15;
pub const A_PROTECT: u32 = 1 << 16;

// ============================================================================
// Constants - Keys
// ============================================================================

pub const KEY_DOWN = 258;
pub const KEY_UP = 259;
pub const KEY_LEFT = 260;
pub const KEY_RIGHT = 261;
pub const KEY_HOME = 262;
pub const KEY_BACKSPACE = 263;
pub const KEY_F0 = 264;
pub const KEY_DC = 330;
pub const KEY_IC = 331;
pub const KEY_NPAGE = 338;
pub const KEY_PPAGE = 339;
pub const KEY_END = 360;
pub const KEY_ENTER = 343;

/// Get function key code for F1-F12
pub fn KEY_F(n: u32) u32 {
    return KEY_F0 + n;
}

// ============================================================================
// Tests
// ============================================================================

test "color constants" {
    try std.testing.expectEqual(@as(i32, 0), COLOR_BLACK);
    try std.testing.expectEqual(@as(i32, 7), COLOR_WHITE);
}

test "attribute constants" {
    try std.testing.expectEqual(@as(u32, 0), A_NORMAL);
    try std.testing.expect(A_BOLD > 0);
    try std.testing.expect(A_UNDERLINE > 0);
}

test "KEY_F" {
    try std.testing.expectEqual(@as(u32, KEY_F0 + 1), KEY_F(1));
    try std.testing.expectEqual(@as(u32, KEY_F0 + 12), KEY_F(12));
}
