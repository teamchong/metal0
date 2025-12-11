//! Python 'idlelib' module - IDLE development environment support
//!
//! IDLE (Integrated Development and Learning Environment) is Python's
//! integrated development environment built with Tkinter.
//!
//! Mirrors: CPython Lib/idlelib/

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const IdlelibError = error{
    TkNotAvailable,
    ConfigError,
    ExtensionError,
    OutOfMemory,
};

// ============================================================================
// Configuration
// ============================================================================

/// IDLE configuration options
pub const Config = struct {
    /// Editor settings
    font_name: []const u8 = "TkFixedFont",
    font_size: u32 = 10,
    tab_width: u32 = 4,
    use_spaces: bool = true,

    /// Color theme
    theme: []const u8 = "IDLE Classic",

    /// Shell settings
    auto_squeeze: bool = false,
    max_squeeze_lines: u32 = 50,

    /// General settings
    startup_edit: bool = true,
    autosave: bool = false,
};

/// Color scheme
pub const ColorScheme = struct {
    name: []const u8,
    foreground: []const u8 = "#000000",
    background: []const u8 = "#ffffff",
    keyword: []const u8 = "#ff7700",
    builtin: []const u8 = "#900090",
    comment: []const u8 = "#dd0000",
    string: []const u8 = "#00aa00",
    definition: []const u8 = "#0000ff",
    error_color: []const u8 = "#ff0000",
};

/// Default color schemes
pub const schemes = struct {
    pub const classic = ColorScheme{
        .name = "IDLE Classic",
        .foreground = "#000000",
        .background = "#ffffff",
    };

    pub const dark = ColorScheme{
        .name = "IDLE Dark",
        .foreground = "#ffffff",
        .background = "#1e1e1e",
        .keyword = "#569cd6",
        .builtin = "#dcdcaa",
        .comment = "#6a9955",
        .string = "#ce9178",
    };

    pub const new = ColorScheme{
        .name = "IDLE New",
        .foreground = "#000000",
        .background = "#ffffff",
        .keyword = "#0000ff",
        .builtin = "#7f007f",
        .comment = "#007f00",
        .string = "#00007f",
    };
};

// ============================================================================
// Key Bindings
// ============================================================================

/// Key binding configuration
pub const KeyBinding = struct {
    event: []const u8,
    keys: []const u8,
};

/// Default key bindings
pub const default_bindings = &[_]KeyBinding{
    .{ .event = "<<run-module>>", .keys = "<F5>" },
    .{ .event = "<<check-module>>", .keys = "<Alt-x>" },
    .{ .event = "<<new-file>>", .keys = "<Control-n>" },
    .{ .event = "<<open-file>>", .keys = "<Control-o>" },
    .{ .event = "<<save-file>>", .keys = "<Control-s>" },
    .{ .event = "<<save-as-file>>", .keys = "<Control-Shift-s>" },
    .{ .event = "<<close-file>>", .keys = "<Control-w>" },
    .{ .event = "<<cut>>", .keys = "<Control-x>" },
    .{ .event = "<<copy>>", .keys = "<Control-c>" },
    .{ .event = "<<paste>>", .keys = "<Control-v>" },
    .{ .event = "<<undo>>", .keys = "<Control-z>" },
    .{ .event = "<<redo>>", .keys = "<Control-y>" },
    .{ .event = "<<find>>", .keys = "<Control-f>" },
    .{ .event = "<<find-again>>", .keys = "<Control-g>" },
    .{ .event = "<<replace>>", .keys = "<Control-h>" },
    .{ .event = "<<goto-line>>", .keys = "<Control-l>" },
    .{ .event = "<<indent>>", .keys = "<Tab>" },
    .{ .event = "<<dedent>>", .keys = "<Shift-Tab>" },
    .{ .event = "<<toggle-comment>>", .keys = "<Alt-3>" },
    .{ .event = "<<restart-shell>>", .keys = "<Control-F6>" },
};

// ============================================================================
// Extensions
// ============================================================================

/// Extension information
pub const Extension = struct {
    name: []const u8,
    enabled: bool = true,
    config: ?*anyopaque = null,
};

/// Built-in extensions
pub const builtin_extensions = &[_][]const u8{
    "AutoComplete",
    "AutoExpand",
    "CallTips",
    "CodeContext",
    "FormatParagraph",
    "ParenMatch",
    "ScriptBinding",
    "ZoomHeight",
};

// ============================================================================
// IDLE Info
// ============================================================================

/// IDLE version info
pub const IDLE_VERSION = "3.12";
pub const IDLE_NAME = "IDLE";
pub const IDLE_DESCRIPTION = "Integrated Development and Learning Environment";

/// Check if IDLE is available by looking for Tk/Tcl libraries
pub fn isAvailable() bool {
    const builtin = @import("builtin");

    // Check for Tk library in common locations
    const tk_paths = switch (builtin.os.tag) {
        .macos => &[_][]const u8{
            "/System/Library/Frameworks/Tk.framework",
            "/Library/Frameworks/Tk.framework",
            "/opt/homebrew/lib/libtk8.6.dylib",
            "/usr/local/lib/libtk8.6.dylib",
        },
        .linux => &[_][]const u8{
            "/usr/lib/x86_64-linux-gnu/libtk8.6.so",
            "/usr/lib/libtk8.6.so",
            "/usr/lib64/libtk8.6.so",
        },
        .windows => &[_][]const u8{
            "C:\\Python312\\tcl\\tk8.6",
            "C:\\Python312\\DLLs\\tk86t.dll",
        },
        else => &[_][]const u8{},
    };

    for (tk_paths) |path| {
        if (std.fs.cwd().access(path, .{})) |_| {
            return true;
        } else |_| {}
    }

    // Also check DISPLAY on Unix (X11 required for Tk)
    if (builtin.os.tag != .windows) {
        if (std.posix.getenv("DISPLAY") == null) {
            // No display = can't run Tk GUI
            return false;
        }
    }

    return false;
}

/// Get IDLE version
pub fn getVersion() []const u8 {
    return IDLE_VERSION;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var current_config: ?Config = null;

pub fn init() void {
    if (initialized) return;
    current_config = Config{};
    initialized = true;
}

pub fn reset() void {
    current_config = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "Config defaults" {
    const config = Config{};
    try std.testing.expectEqual(@as(u32, 10), config.font_size);
    try std.testing.expectEqual(@as(u32, 4), config.tab_width);
    try std.testing.expect(config.use_spaces);
}

test "ColorScheme classic" {
    try std.testing.expectEqualStrings("IDLE Classic", schemes.classic.name);
    try std.testing.expectEqualStrings("#000000", schemes.classic.foreground);
}

test "ColorScheme dark" {
    try std.testing.expectEqualStrings("IDLE Dark", schemes.dark.name);
    try std.testing.expectEqualStrings("#1e1e1e", schemes.dark.background);
}

test "default_bindings" {
    try std.testing.expect(default_bindings.len > 0);
    try std.testing.expectEqualStrings("<<run-module>>", default_bindings[0].event);
    try std.testing.expectEqualStrings("<F5>", default_bindings[0].keys);
}

test "builtin_extensions" {
    try std.testing.expect(builtin_extensions.len > 0);
    try std.testing.expectEqualStrings("AutoComplete", builtin_extensions[0]);
}

test "isAvailable" {
    // Should return false in test environment
    try std.testing.expect(!isAvailable());
}

test "getVersion" {
    try std.testing.expectEqualStrings("3.12", getVersion());
}
