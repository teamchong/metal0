//! CPython source: Lib/webbrowser.py
//!
//! Provides high-level interface to allow displaying web-based documents.
//!
//! Mirrors: CPython Lib/webbrowser.py

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Constants
// ============================================================================

/// Browser open modes
pub const OpenMode = enum(u8) {
    /// Open in same browser window if possible
    same = 0,
    /// Open in new browser window
    new = 1,
    /// Open in new browser tab
    new_tab = 2,
};

// ============================================================================
// Error Types
// ============================================================================

pub const BrowserError = error{
    /// Could not find a suitable browser
    BrowserNotFound,
    /// Failed to open URL
    OpenFailed,
    /// Invalid URL
    InvalidUrl,
};

// ============================================================================
// Browser Base
// ============================================================================

/// Base browser controller
pub const BaseBrowser = struct {
    const Self = @This();

    name: []const u8,
    basename: ?[]const u8,

    pub fn init(name: []const u8) Self {
        return .{
            .name = name,
            .basename = null,
        };
    }

    /// Open a URL
    pub fn open(self: *Self, url: []const u8, new: OpenMode, autoraise: bool) !bool {
        _ = self;
        _ = url;
        _ = new;
        _ = autoraise;
        return false;
    }

    /// Open a new window
    pub fn openNew(self: *Self, url: []const u8) !bool {
        return self.open(url, .new, true);
    }

    /// Open a new tab
    pub fn openNewTab(self: *Self, url: []const u8) !bool {
        return self.open(url, .new_tab, true);
    }
};

// ============================================================================
// Generic Unix Browser
// ============================================================================

/// Generic browser that uses command-line
pub const GenericBrowser = struct {
    const Self = @This();

    base: BaseBrowser,
    args: []const []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, args: []const []const u8) Self {
        return .{
            .base = BaseBrowser.init(name),
            .args = args,
            .allocator = allocator,
        };
    }

    pub fn open(self: *Self, url: []const u8, new: OpenMode, autoraise: bool) !bool {
        _ = autoraise;
        _ = new;

        // Build command
        var argv = std.ArrayList([]const u8).init(self.allocator);
        defer argv.deinit();

        try argv.append(self.base.name);
        for (self.args) |arg| {
            if (std.mem.eql(u8, arg, "%s")) {
                try argv.append(url);
            } else {
                try argv.append(arg);
            }
        }

        var child = std.process.Child.init(argv.items, self.allocator);
        child.spawn() catch return false;
        return true;
    }
};

// ============================================================================
// Background Browser
// ============================================================================

/// Browser that runs in background
pub const BackgroundBrowser = struct {
    const Self = @This();

    base: BaseBrowser,
    command: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, command: []const u8) Self {
        return .{
            .base = BaseBrowser.init(name),
            .command = command,
            .allocator = allocator,
        };
    }

    pub fn open(self: *Self, url: []const u8, new: OpenMode, autoraise: bool) !bool {
        _ = autoraise;
        _ = new;

        var child = std.process.Child.init(&[_][]const u8{ self.command, url }, self.allocator);
        child.spawn() catch return false;
        return true;
    }
};

// ============================================================================
// macOS Browsers
// ============================================================================

/// macOS default browser using 'open' command
pub const MacOSDefaultBrowser = struct {
    const Self = @This();

    base: BaseBrowser,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = BaseBrowser.init("macosx"),
            .allocator = allocator,
        };
    }

    pub fn open(self: *Self, url: []const u8, new: OpenMode, autoraise: bool) !bool {
        _ = autoraise;

        const script = switch (new) {
            .new => &[_][]const u8{ "open", "-n", url },
            .new_tab => &[_][]const u8{ "open", url },
            .same => &[_][]const u8{ "open", url },
        };

        var child = std.process.Child.init(script, self.allocator);
        child.spawn() catch return false;
        return true;
    }
};

// ============================================================================
// Windows Browsers
// ============================================================================

/// Windows default browser
pub const WindowsDefault = struct {
    const Self = @This();

    base: BaseBrowser,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = BaseBrowser.init("windows-default"),
            .allocator = allocator,
        };
    }

    pub fn open(self: *Self, url: []const u8, new: OpenMode, autoraise: bool) !bool {
        _ = new;
        _ = autoraise;

        var child = std.process.Child.init(&[_][]const u8{ "cmd", "/c", "start", url }, self.allocator);
        child.spawn() catch return false;
        return true;
    }
};

// ============================================================================
// Linux/Unix Browsers
// ============================================================================

/// XDG-open browser (Linux)
pub const XdgOpen = struct {
    const Self = @This();

    base: BaseBrowser,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = BaseBrowser.init("xdg-open"),
            .allocator = allocator,
        };
    }

    pub fn open(self: *Self, url: []const u8, new: OpenMode, autoraise: bool) !bool {
        _ = new;
        _ = autoraise;

        var child = std.process.Child.init(&[_][]const u8{ "xdg-open", url }, self.allocator);
        child.spawn() catch return false;
        return true;
    }
};

// ============================================================================
// Chrome Browser
// ============================================================================

/// Google Chrome browser
pub const Chrome = struct {
    const Self = @This();

    base: BaseBrowser,
    command: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, command: []const u8) Self {
        return .{
            .base = BaseBrowser.init("chrome"),
            .command = command,
            .allocator = allocator,
        };
    }

    pub fn open(self: *Self, url: []const u8, new: OpenMode, autoraise: bool) !bool {
        _ = autoraise;

        const args = switch (new) {
            .new => &[_][]const u8{ self.command, "--new-window", url },
            .new_tab => &[_][]const u8{ self.command, url },
            .same => &[_][]const u8{ self.command, url },
        };

        var child = std.process.Child.init(args, self.allocator);
        child.spawn() catch return false;
        return true;
    }
};

// ============================================================================
// Firefox Browser
// ============================================================================

/// Mozilla Firefox browser
pub const Firefox = struct {
    const Self = @This();

    base: BaseBrowser,
    command: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, command: []const u8) Self {
        return .{
            .base = BaseBrowser.init("firefox"),
            .command = command,
            .allocator = allocator,
        };
    }

    pub fn open(self: *Self, url: []const u8, new: OpenMode, autoraise: bool) !bool {
        _ = autoraise;

        const args = switch (new) {
            .new => &[_][]const u8{ self.command, "-new-window", url },
            .new_tab => &[_][]const u8{ self.command, "-new-tab", url },
            .same => &[_][]const u8{ self.command, url },
        };

        var child = std.process.Child.init(args, self.allocator);
        child.spawn() catch return false;
        return true;
    }
};

// ============================================================================
// Safari Browser
// ============================================================================

/// Safari browser (macOS)
pub const Safari = struct {
    const Self = @This();

    base: BaseBrowser,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = BaseBrowser.init("safari"),
            .allocator = allocator,
        };
    }

    pub fn open(self: *Self, url: []const u8, new: OpenMode, autoraise: bool) !bool {
        _ = autoraise;
        _ = new;

        // Use AppleScript for Safari
        const script = "tell application \"Safari\" to open location \"" ++ url ++ "\"";
        _ = script;

        var child = std.process.Child.init(&[_][]const u8{ "open", "-a", "Safari", url }, self.allocator);
        child.spawn() catch return false;
        return true;
    }
};

// ============================================================================
// Browser Registry
// ============================================================================

/// Registered browsers
pub const BrowserEntry = struct {
    name: []const u8,
    klass: BrowserType,
};

pub const BrowserType = union(enum) {
    generic: GenericBrowser,
    background: BackgroundBrowser,
    macos: MacOSDefaultBrowser,
    windows: WindowsDefault,
    xdg: XdgOpen,
    chrome: Chrome,
    firefox: Firefox,
    safari: Safari,
};

var _browsers: ?std.ArrayList(BrowserEntry) = null;
var _default_browser: ?BrowserType = null;

/// Register a browser
pub fn register(name: []const u8, klass: BrowserType, instance: ?BrowserType, update_tryorder: bool) !void {
    _ = instance;
    _ = update_tryorder;

    if (_browsers == null) {
        _browsers = std.ArrayList(BrowserEntry).init(std.heap.page_allocator);
    }

    try _browsers.?.append(.{ .name = name, .klass = klass });
}

/// Get a browser controller by name
pub fn get(using: ?[]const u8) !BrowserType {
    if (using) |name| {
        if (_browsers) |browsers| {
            for (browsers.items) |entry| {
                if (std.mem.eql(u8, entry.name, name)) {
                    return entry.klass;
                }
            }
        }
        return BrowserError.BrowserNotFound;
    }

    // Return default browser
    if (_default_browser) |browser| {
        return browser;
    }

    // Auto-detect default browser
    return getDefaultBrowser();
}

/// Get default browser for current platform
fn getDefaultBrowser() BrowserType {
    return switch (builtin.os.tag) {
        .macos => .{ .macos = MacOSDefaultBrowser.init(std.heap.page_allocator) },
        .windows => .{ .windows = WindowsDefault.init(std.heap.page_allocator) },
        .linux => .{ .xdg = XdgOpen.init(std.heap.page_allocator) },
        else => .{ .xdg = XdgOpen.init(std.heap.page_allocator) },
    };
}

// ============================================================================
// Module-Level Functions
// ============================================================================

/// Open URL in default browser
pub fn open(url: []const u8, new: OpenMode, autoraise: bool) !bool {
    var browser = try get(null);
    return openWithBrowser(&browser, url, new, autoraise);
}

fn openWithBrowser(browser: *BrowserType, url: []const u8, new: OpenMode, autoraise: bool) !bool {
    return switch (browser.*) {
        .generic => |*b| b.open(url, new, autoraise),
        .background => |*b| b.open(url, new, autoraise),
        .macos => |*b| b.open(url, new, autoraise),
        .windows => |*b| b.open(url, new, autoraise),
        .xdg => |*b| b.open(url, new, autoraise),
        .chrome => |*b| b.open(url, new, autoraise),
        .firefox => |*b| b.open(url, new, autoraise),
        .safari => |*b| b.open(url, new, autoraise),
    };
}

/// Open URL in new browser window
pub fn open_new(url: []const u8) !bool {
    return open(url, .new, true);
}

/// Open URL in new browser tab
pub fn open_new_tab(url: []const u8) !bool {
    return open(url, .new_tab, true);
}

// ============================================================================
// Well-Known Browser Commands
// ============================================================================

/// Chrome executable names by platform
pub const CHROME_COMMANDS = switch (builtin.os.tag) {
    .macos => &[_][]const u8{
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "google-chrome",
        "chrome",
        "chromium",
    },
    .windows => &[_][]const u8{
        "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
        "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
        "chrome",
    },
    else => &[_][]const u8{
        "google-chrome",
        "google-chrome-stable",
        "chromium",
        "chromium-browser",
    },
};

/// Firefox executable names by platform
pub const FIREFOX_COMMANDS = switch (builtin.os.tag) {
    .macos => &[_][]const u8{
        "/Applications/Firefox.app/Contents/MacOS/firefox",
        "firefox",
    },
    .windows => &[_][]const u8{
        "C:\\Program Files\\Mozilla Firefox\\firefox.exe",
        "C:\\Program Files (x86)\\Mozilla Firefox\\firefox.exe",
        "firefox",
    },
    else => &[_][]const u8{
        "firefox",
        "firefox-esr",
        "iceweasel",
    },
};

// ============================================================================
// Tests
// ============================================================================

test "OpenMode values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(OpenMode.same));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(OpenMode.new));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(OpenMode.new_tab));
}

test "BaseBrowser init" {
    const browser = BaseBrowser.init("test");
    try std.testing.expectEqualStrings("test", browser.name);
    try std.testing.expect(browser.basename == null);
}

test "getDefaultBrowser returns browser" {
    const browser = getDefaultBrowser();
    _ = browser;
    // Just verify it doesn't error
}

test "Chrome commands exist" {
    try std.testing.expect(CHROME_COMMANDS.len > 0);
}

test "Firefox commands exist" {
    try std.testing.expect(FIREFOX_COMMANDS.len > 0);
}

test "MacOSDefaultBrowser init" {
    const allocator = std.testing.allocator;
    const browser = MacOSDefaultBrowser.init(allocator);
    try std.testing.expectEqualStrings("macosx", browser.base.name);
}

test "XdgOpen init" {
    const allocator = std.testing.allocator;
    const browser = XdgOpen.init(allocator);
    try std.testing.expectEqualStrings("xdg-open", browser.base.name);
}

test "Chrome init" {
    const allocator = std.testing.allocator;
    const browser = Chrome.init(allocator, "google-chrome");
    try std.testing.expectEqualStrings("chrome", browser.base.name);
    try std.testing.expectEqualStrings("google-chrome", browser.command);
}

test "Firefox init" {
    const allocator = std.testing.allocator;
    const browser = Firefox.init(allocator, "firefox");
    try std.testing.expectEqualStrings("firefox", browser.base.name);
}
