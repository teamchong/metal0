//! Terminal mode management
//!
//! Handles terminal settings including echo, cbreak, raw mode,
//! and termios configuration for controlling input/output behavior.

const std = @import("std");

// ============================================================================
// Terminal State
// ============================================================================

var original_termios: ?std.posix.termios = null;
var current_termios: ?std.posix.termios = null;

// ============================================================================
// Private Helpers
// ============================================================================

/// Get terminal fd (stdin)
fn getTermFd() std.posix.fd_t {
    return std.io.getStdIn().handle;
}

/// Save original terminal settings
fn saveTermios() void {
    if (original_termios == null) {
        original_termios = std.posix.tcgetattr(getTermFd()) catch null;
        current_termios = original_termios;
    }
}

/// Apply current termios settings
fn applyTermios() void {
    if (current_termios) |*t| {
        std.posix.tcsetattr(getTermFd(), .FLUSH, t.*) catch {};
    }
}

// ============================================================================
// Public API
// ============================================================================

/// Enable echo - characters typed are displayed
pub fn echo() void {
    saveTermios();
    if (current_termios) |*t| {
        t.lflag.ECHO = true;
        applyTermios();
    }
}

/// Disable echo - characters typed are not displayed
pub fn noecho() void {
    saveTermios();
    if (current_termios) |*t| {
        t.lflag.ECHO = false;
        applyTermios();
    }
}

/// Enable cbreak mode - characters available immediately, no line buffering
pub fn cbreak() void {
    saveTermios();
    if (current_termios) |*t| {
        t.lflag.ICANON = false;
        t.cc[@intFromEnum(std.posix.V.MIN)] = 1;
        t.cc[@intFromEnum(std.posix.V.TIME)] = 0;
        applyTermios();
    }
}

/// Disable cbreak mode - restore line buffering
pub fn nocbreak() void {
    saveTermios();
    if (current_termios) |*t| {
        t.lflag.ICANON = true;
        applyTermios();
    }
}

/// Enable raw mode - no processing of input/output
pub fn raw() void {
    saveTermios();
    if (current_termios) |*t| {
        // Disable all input processing
        t.iflag.BRKINT = false;
        t.iflag.ICRNL = false;
        t.iflag.INPCK = false;
        t.iflag.ISTRIP = false;
        t.iflag.IXON = false;
        // Disable output processing
        t.oflag.OPOST = false;
        // Disable canonical mode and signals
        t.lflag.ECHO = false;
        t.lflag.ICANON = false;
        t.lflag.IEXTEN = false;
        t.lflag.ISIG = false;
        t.cc[@intFromEnum(std.posix.V.MIN)] = 1;
        t.cc[@intFromEnum(std.posix.V.TIME)] = 0;
        applyTermios();
    }
}

/// Disable raw mode - restore normal processing
pub fn noraw() void {
    saveTermios();
    if (original_termios) |orig| {
        current_termios = orig;
        applyTermios();
    }
}
