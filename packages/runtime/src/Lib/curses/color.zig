//! Color support for curses
//!
//! Provides color detection, initialization, and color pair management
//! for terminals that support color output.

const std = @import("std");
const types = @import("types.zig");

// ============================================================================
// Color Pair Storage
// ============================================================================

var color_pairs: [256]struct { fg: i16, bg: i16 } = undefined;

// ============================================================================
// Public API
// ============================================================================

/// Check if terminal has colors
pub fn has_colors() bool {
    // Check TERM environment variable for color support
    const term = std.posix.getenv("TERM") orelse return false;
    return std.mem.indexOf(u8, term, "color") != null or
        std.mem.indexOf(u8, term, "256") != null or
        std.mem.eql(u8, term, "xterm") or
        std.mem.eql(u8, term, "screen") or
        std.mem.eql(u8, term, "tmux");
}

/// Start color support - initialize color subsystem
pub fn start_color() void {
    // Initialize all color pairs to default (white on black)
    for (&color_pairs) |*pair| {
        pair.fg = types.COLOR_WHITE;
        pair.bg = types.COLOR_BLACK;
    }
}

/// Initialize a color pair
pub fn init_pair(pair: i16, fg: i16, bg: i16) void {
    if (pair >= 0 and pair < 256) {
        color_pairs[@intCast(pair)] = .{ .fg = fg, .bg = bg };
    }
}

/// Get color pair attribute
pub fn color_pair(n: i16) u32 {
    return @as(u32, @intCast(n)) << 17;
}
