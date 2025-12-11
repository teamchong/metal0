//! Curses utility functions
//!
//! Miscellaneous utility functions including cursor visibility,
//! audio/visual alerts (beep, flash), and other helper functions.

const std = @import("std");

// ============================================================================
// Public API
// ============================================================================

/// Set cursor visibility
pub fn curs_set(visibility: u8) void {
    const stdout = std.io.getStdOut().writer();
    if (visibility == 0) {
        stdout.writeAll("\x1b[?25l") catch {};
    } else {
        stdout.writeAll("\x1b[?25h") catch {};
    }
}

/// Ring the bell
pub fn beep() void {
    const stdout = std.io.getStdOut().writer();
    stdout.writeByte(0x07) catch {};
}

/// Flash the screen
pub fn flash() void {
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll("\x1b[?5h") catch {};
    std.time.sleep(100 * std.time.ns_per_ms);
    stdout.writeAll("\x1b[?5l") catch {};
}
