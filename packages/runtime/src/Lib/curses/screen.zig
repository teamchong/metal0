//! Screen initialization and management
//!
//! Handles initialization, teardown, and creation of curses windows.
//! Manages the standard screen (stdscr) and window lifecycle.

const std = @import("std");
const Window = @import("window.zig").Window;

// ============================================================================
// Module State
// ============================================================================

var stdscr: ?*Window = null;
var is_initialized: bool = false;
var _allocator: ?std.mem.Allocator = null;

// ============================================================================
// Public API
// ============================================================================

/// Initialize curses
pub fn initscr(allocator: std.mem.Allocator) !*Window {
    if (is_initialized) return error.InitializationFailed;

    _allocator = allocator;

    // Get terminal size
    const height: u32 = 24;
    const width: u32 = 80;

    stdscr = try allocator.create(Window);
    stdscr.?.* = try Window.init(allocator, height, width, 0, 0);

    is_initialized = true;

    // Clear screen
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll("\x1b[2J\x1b[H") catch {};

    return stdscr.?;
}

/// End curses mode
pub fn endwin() void {
    if (!is_initialized) return;

    // Reset terminal
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll("\x1b[0m\x1b[2J\x1b[H") catch {};

    if (stdscr) |w| {
        var win = w;
        win.deinit();
        if (_allocator) |a| {
            a.destroy(win);
        }
    }
    stdscr = null;
    is_initialized = false;
}

/// Check if curses has been initialized
pub fn isendwin() bool {
    return !is_initialized;
}

/// Create a new window
pub fn newwin(allocator: std.mem.Allocator, height: u32, width: u32, y: u32, x: u32) !*Window {
    const win = try allocator.create(Window);
    win.* = try Window.init(allocator, height, width, y, x);
    return win;
}

/// Delete a window
pub fn delwin(allocator: std.mem.Allocator, win: *Window) void {
    win.deinit();
    allocator.destroy(win);
}

/// Initialize module
pub fn init() void {
    // Called on module import
}

/// Reset module state
pub fn reset() void {
    if (is_initialized) {
        endwin();
    }
}
