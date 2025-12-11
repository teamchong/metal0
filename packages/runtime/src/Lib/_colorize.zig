/// _colorize - Terminal Color Support
/// Mirrors cpython/Lib/_colorize.py
///
/// Provides ANSI color code support for terminal output.
/// Used by Python's REPL and error messages for syntax highlighting.

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const builtin = @import("builtin");

// ============================================================================
// ANSI Color Codes
// ============================================================================

/// ANSI escape code prefix
pub const ESC: []const u8 = "\x1b[";

/// Reset all attributes
pub const RESET: []const u8 = "\x1b[0m";

/// Text style codes
pub const Style = struct {
    pub const bold: []const u8 = "\x1b[1m";
    pub const dim: []const u8 = "\x1b[2m";
    pub const italic: []const u8 = "\x1b[3m";
    pub const underline: []const u8 = "\x1b[4m";
    pub const blink: []const u8 = "\x1b[5m";
    pub const inverse: []const u8 = "\x1b[7m";
    pub const hidden: []const u8 = "\x1b[8m";
    pub const strikethrough: []const u8 = "\x1b[9m";
};

/// Foreground color codes
pub const Fg = struct {
    pub const black: []const u8 = "\x1b[30m";
    pub const red: []const u8 = "\x1b[31m";
    pub const green: []const u8 = "\x1b[32m";
    pub const yellow: []const u8 = "\x1b[33m";
    pub const blue: []const u8 = "\x1b[34m";
    pub const magenta: []const u8 = "\x1b[35m";
    pub const cyan: []const u8 = "\x1b[36m";
    pub const white: []const u8 = "\x1b[37m";
    pub const default: []const u8 = "\x1b[39m";

    // Bright colors
    pub const bright_black: []const u8 = "\x1b[90m";
    pub const bright_red: []const u8 = "\x1b[91m";
    pub const bright_green: []const u8 = "\x1b[92m";
    pub const bright_yellow: []const u8 = "\x1b[93m";
    pub const bright_blue: []const u8 = "\x1b[94m";
    pub const bright_magenta: []const u8 = "\x1b[95m";
    pub const bright_cyan: []const u8 = "\x1b[96m";
    pub const bright_white: []const u8 = "\x1b[97m";
};

/// Background color codes
pub const Bg = struct {
    pub const black: []const u8 = "\x1b[40m";
    pub const red: []const u8 = "\x1b[41m";
    pub const green: []const u8 = "\x1b[42m";
    pub const yellow: []const u8 = "\x1b[43m";
    pub const blue: []const u8 = "\x1b[44m";
    pub const magenta: []const u8 = "\x1b[45m";
    pub const cyan: []const u8 = "\x1b[46m";
    pub const white: []const u8 = "\x1b[47m";
    pub const default: []const u8 = "\x1b[49m";

    // Bright backgrounds
    pub const bright_black: []const u8 = "\x1b[100m";
    pub const bright_red: []const u8 = "\x1b[101m";
    pub const bright_green: []const u8 = "\x1b[102m";
    pub const bright_yellow: []const u8 = "\x1b[103m";
    pub const bright_blue: []const u8 = "\x1b[104m";
    pub const bright_magenta: []const u8 = "\x1b[105m";
    pub const bright_cyan: []const u8 = "\x1b[106m";
    pub const bright_white: []const u8 = "\x1b[107m";
};

// ============================================================================
// Color Enum
// ============================================================================

/// Standard colors enum
pub const Color = enum(u8) {
    black = 0,
    red = 1,
    green = 2,
    yellow = 3,
    blue = 4,
    magenta = 5,
    cyan = 6,
    white = 7,

    pub fn toFgCode(self: Color) u8 {
        return 30 + @intFromEnum(self);
    }

    pub fn toBgCode(self: Color) u8 {
        return 40 + @intFromEnum(self);
    }

    pub fn toBrightFgCode(self: Color) u8 {
        return 90 + @intFromEnum(self);
    }

    pub fn toBrightBgCode(self: Color) u8 {
        return 100 + @intFromEnum(self);
    }
};

// ============================================================================
// Theme Colors (Python-style)
// ============================================================================

/// Theme colors for syntax highlighting (matching Python's REPL)
pub const Theme = struct {
    /// Keyword color (def, class, if, for, etc.)
    keyword: []const u8 = Fg.magenta,
    /// Builtin function color (print, len, etc.)
    builtin: []const u8 = Fg.cyan,
    /// String literal color
    string: []const u8 = Fg.green,
    /// Number literal color
    number: []const u8 = Fg.blue,
    /// Comment color
    comment: []const u8 = Fg.bright_black,
    /// Operator color
    operator: []const u8 = Fg.yellow,
    /// Error/exception color
    @"error": []const u8 = Fg.red,
    /// Warning color
    warning: []const u8 = Fg.yellow,
    /// Success color
    success: []const u8 = Fg.green,
    /// Prompt color
    prompt: []const u8 = Fg.bright_green,
    /// Reset
    reset: []const u8 = RESET,
};

/// Default theme
pub const default_theme = Theme{};

// ============================================================================
// Color Detection
// ============================================================================

/// Check if the terminal supports colors
pub fn canUseColor() bool {
    // Check NO_COLOR environment variable
    if (std.process.hasEnvVar("NO_COLOR")) return false;

    // Check FORCE_COLOR environment variable
    if (std.process.hasEnvVar("FORCE_COLOR")) return true;

    // Check if stdout is a TTY
    const stdout = std.io.getStdOut();
    if (!stdout.isTty()) return false;

    // Check TERM environment variable
    if (std.process.getEnvVarOwned(allocator_helper.fast_allocator, "TERM")) |term| {
        defer allocator_helper.fast_allocator.free(term);
        if (std.mem.eql(u8, term, "dumb")) return false;
    } else |_| {}

    return true;
}

/// Check if stderr supports colors
pub fn canUseColorStderr() bool {
    if (std.process.hasEnvVar("NO_COLOR")) return false;
    if (std.process.hasEnvVar("FORCE_COLOR")) return true;

    const stderr = std.io.getStdErr();
    return stderr.isTty();
}

// ============================================================================
// Colorize Functions
// ============================================================================

/// Colorize a string with the given color code
pub fn colorize(allocator: std.mem.Allocator, text: []const u8, color: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ color, text, RESET });
}

/// Colorize only if terminal supports colors
pub fn maybeColorize(allocator: std.mem.Allocator, text: []const u8, color: []const u8) ![]u8 {
    if (canUseColor()) {
        return colorize(allocator, text, color);
    }
    return allocator.dupe(u8, text);
}

/// Print colored text to stdout
pub fn printColored(text: []const u8, color: []const u8) void {
    if (canUseColor()) {
        std.debug.print("{s}{s}{s}", .{ color, text, RESET });
    } else {
        std.debug.print("{s}", .{text});
    }
}

// ============================================================================
// 256 Color Support
// ============================================================================

/// Generate 256-color foreground code
pub fn fg256(color: u8) [11]u8 {
    var buf: [11]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "\x1b[38;5;{d}m", .{color}) catch {};
    return buf;
}

/// Generate 256-color background code
pub fn bg256(color: u8) [11]u8 {
    var buf: [11]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "\x1b[48;5;{d}m", .{color}) catch {};
    return buf;
}

// ============================================================================
// RGB Color Support
// ============================================================================

/// Generate RGB foreground code
pub fn fgRgb(r: u8, g: u8, b: u8) [19]u8 {
    var buf: [19]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "\x1b[38;2;{d};{d};{d}m", .{ r, g, b }) catch {};
    return buf;
}

/// Generate RGB background code
pub fn bgRgb(r: u8, g: u8, b: u8) [19]u8 {
    var buf: [19]u8 = undefined;
    _ = std.fmt.bufPrint(&buf, "\x1b[48;2;{d};{d};{d}m", .{ r, g, b }) catch {};
    return buf;
}

// ============================================================================
// Strip Colors
// ============================================================================

/// Strip ANSI escape codes from a string
pub fn stripColors(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;

    while (i < text.len) {
        if (text[i] == '\x1b' and i + 1 < text.len and text[i + 1] == '[') {
            // Skip escape sequence
            i += 2;
            while (i < text.len and text[i] != 'm') {
                i += 1;
            }
            if (i < text.len) i += 1; // Skip 'm'
        } else {
            try result.append(text[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var colors_enabled: ?bool = null;

/// Initialize the _colorize module
pub fn init() void {
    if (initialized) return;
    initialized = true;
    colors_enabled = canUseColor();
}

/// Check if colors are enabled
pub fn isEnabled() bool {
    if (colors_enabled) |enabled| return enabled;
    return canUseColor();
}

/// Force enable/disable colors
pub fn setEnabled(enabled: bool) void {
    colors_enabled = enabled;
}

/// Reset module state
pub fn reset() void {
    colors_enabled = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "color codes" {
    try std.testing.expectEqualStrings("\x1b[31m", Fg.red);
    try std.testing.expectEqualStrings("\x1b[42m", Bg.green);
    try std.testing.expectEqualStrings("\x1b[0m", RESET);
}

test "style codes" {
    try std.testing.expectEqualStrings("\x1b[1m", Style.bold);
    try std.testing.expectEqualStrings("\x1b[4m", Style.underline);
}

test "color enum" {
    try std.testing.expectEqual(@as(u8, 31), Color.red.toFgCode());
    try std.testing.expectEqual(@as(u8, 44), Color.blue.toBgCode());
    try std.testing.expectEqual(@as(u8, 92), Color.green.toBrightFgCode());
}

test "colorize" {
    const allocator = std.testing.allocator;
    const result = try colorize(allocator, "hello", Fg.red);
    defer allocator.free(result);

    try std.testing.expect(std.mem.startsWith(u8, result, "\x1b[31m"));
    try std.testing.expect(std.mem.endsWith(u8, result, "\x1b[0m"));
    try std.testing.expect(std.mem.indexOf(u8, result, "hello") != null);
}

test "strip colors" {
    const allocator = std.testing.allocator;
    const colored = "\x1b[31mhello\x1b[0m \x1b[32mworld\x1b[0m";
    const stripped = try stripColors(allocator, colored);
    defer allocator.free(stripped);

    try std.testing.expectEqualStrings("hello world", stripped);
}

test "theme" {
    const theme = default_theme;
    try std.testing.expectEqualStrings(Fg.magenta, theme.keyword);
    try std.testing.expectEqualStrings(Fg.green, theme.string);
}
