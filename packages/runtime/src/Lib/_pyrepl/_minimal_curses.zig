//! _pyrepl._minimal_curses - Minimal curses interface for pyrepl
//! Reference: cpython/Lib/_pyrepl/_minimal_curses.py
//!
//! Minimal '_curses' module based on terminfo.
//! This provides just enough curses functionality for the REPL.

const std = @import("std");

// ============================================================================
// Error type
// ============================================================================

pub const CursesError = error{
    SetupTermFailed,
    TparmFailed,
    LibraryNotFound,
};

// ============================================================================
// Constants
// ============================================================================

pub const OK: i32 = 0;
pub const ERR: i32 = -1;

// ============================================================================
// Terminal capabilities (terminfo strings)
// ============================================================================

/// Common terminal capability names
pub const Capability = enum {
    // Cursor movement
    cuu1, // cursor up
    cud1, // cursor down
    cuf1, // cursor forward
    cub1, // cursor back
    home, // cursor home
    cup, // cursor position

    // Clear
    clear, // clear screen
    el, // clear to end of line
    ed, // clear to end of display

    // Attributes
    bold, // bold mode
    sgr0, // reset attributes
    smul, // underline mode
    rmul, // end underline

    // Colors
    setaf, // set foreground
    setab, // set background

    // Keypad
    smkx, // enable keypad
    rmkx, // disable keypad

    pub fn toString(self: Capability) []const u8 {
        return @tagName(self);
    }
};

// ============================================================================
// Terminfo interface
// ============================================================================

var term_initialized: bool = false;

/// Initialize terminal (setupterm equivalent)
pub fn setupterm(term: ?[]const u8, fd: i32) !void {
    _ = term;
    _ = fd;
    // In AOT context, we assume terminal is already set up
    term_initialized = true;
}

/// Get terminal capability string (tigetstr equivalent)
pub fn tigetstr(cap: []const u8) ?[]const u8 {
    // Return common ANSI escape sequences
    const map = std.StaticStringMap([]const u8).initComptime(.{
        .{ "cuu1", "\x1b[A" },
        .{ "cud1", "\x1b[B" },
        .{ "cuf1", "\x1b[C" },
        .{ "cub1", "\x1b[D" },
        .{ "home", "\x1b[H" },
        .{ "clear", "\x1b[2J\x1b[H" },
        .{ "el", "\x1b[K" },
        .{ "ed", "\x1b[J" },
        .{ "bold", "\x1b[1m" },
        .{ "sgr0", "\x1b[0m" },
        .{ "smul", "\x1b[4m" },
        .{ "rmul", "\x1b[24m" },
        .{ "smkx", "\x1b[?1h\x1b=" },
        .{ "rmkx", "\x1b[?1l\x1b>" },
    });
    return map.get(cap);
}

/// Parameterized terminal capability (tparm equivalent)
pub fn tparm(allocator: std.mem.Allocator, str: []const u8, args: []const i32) ![]const u8 {
    // For simple cases, just return the string
    // For setaf/setab, format with the color number
    if (std.mem.indexOf(u8, str, "%p1%d")) |_| {
        if (args.len > 0) {
            return std.fmt.allocPrint(allocator, "\x1b[{d}m", .{args[0]});
        }
    }
    return allocator.dupe(u8, str);
}

// ============================================================================
// Tests
// ============================================================================

test "tigetstr" {
    try std.testing.expect(tigetstr("cuu1") != null);
    try std.testing.expect(tigetstr("unknown") == null);
}

test "setupterm" {
    try setupterm(null, 1);
    try std.testing.expect(term_initialized);
}
