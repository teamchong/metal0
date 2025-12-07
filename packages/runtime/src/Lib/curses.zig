//! Python 'curses' module - Terminal handling for character-cell displays
//!
//! Provides an interface to the curses library for terminal control.
//!
//! Mirrors: CPython Lib/curses/

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

// Function keys
pub fn KEY_F(n: u32) u32 {
    return KEY_F0 + n;
}

// ============================================================================
// Window
// ============================================================================

/// A curses window
pub const Window = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Window dimensions
    height: u32,
    width: u32,
    /// Window position
    y: u32,
    x: u32,
    /// Cursor position
    cur_y: u32 = 0,
    cur_x: u32 = 0,
    /// Current attributes
    attrs: u32 = A_NORMAL,
    /// Window buffer
    buffer: [][]u8,
    /// Keypad mode enabled
    keypad_enabled: bool = false,

    pub fn init(allocator: std.mem.Allocator, height: u32, width: u32, y: u32, x: u32) !Self {
        var buffer = try allocator.alloc([]u8, height);
        for (buffer, 0..) |*row, i| {
            _ = i;
            row.* = try allocator.alloc(u8, width);
            @memset(row.*, ' ');
        }

        return Self{
            .allocator = allocator,
            .height = height,
            .width = width,
            .y = y,
            .x = x,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.buffer) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.buffer);
    }

    /// Clear the window
    pub fn clear(self: *Self) void {
        for (self.buffer) |row| {
            @memset(row, ' ');
        }
        self.cur_y = 0;
        self.cur_x = 0;
    }

    /// Clear to end of line
    pub fn clrtoeol(self: *Self) void {
        if (self.cur_y < self.height) {
            @memset(self.buffer[self.cur_y][self.cur_x..], ' ');
        }
    }

    /// Move cursor
    pub fn move(self: *Self, y: u32, x: u32) void {
        self.cur_y = @min(y, self.height - 1);
        self.cur_x = @min(x, self.width - 1);
    }

    /// Add a character
    pub fn addch(self: *Self, ch: u8) void {
        if (self.cur_y < self.height and self.cur_x < self.width) {
            self.buffer[self.cur_y][self.cur_x] = ch;
            self.cur_x += 1;
            if (self.cur_x >= self.width) {
                self.cur_x = 0;
                self.cur_y += 1;
            }
        }
    }

    /// Add a string
    pub fn addstr(self: *Self, s: []const u8) void {
        for (s) |ch| {
            self.addch(ch);
        }
    }

    /// Add a string at position
    pub fn mvaddstr(self: *Self, y: u32, x: u32, s: []const u8) void {
        self.move(y, x);
        self.addstr(s);
    }

    /// Get a character
    pub fn getch(self: *Self) !i32 {
        _ = self;
        const stdin = std.io.getStdIn();
        var buf: [1]u8 = undefined;
        const n = try stdin.read(&buf);
        if (n == 0) return -1;
        return buf[0];
    }

    /// Refresh the window
    pub fn refresh(self: *Self) void {
        const stdout = std.io.getStdOut().writer();

        // Move to window position and output buffer
        for (self.buffer, 0..) |row, y| {
            stdout.print("\x1b[{d};{d}H", .{ self.y + y + 1, self.x + 1 }) catch {};
            stdout.writeAll(row) catch {};
        }

        // Move cursor to current position
        stdout.print("\x1b[{d};{d}H", .{ self.y + self.cur_y + 1, self.x + self.cur_x + 1 }) catch {};
    }

    /// Enable/disable keypad
    pub fn keypad(self: *Self, enable: bool) void {
        self.keypad_enabled = enable;
    }

    /// Get window dimensions
    pub fn getmaxyx(self: *const Self) struct { y: u32, x: u32 } {
        return .{ .y = self.height, .x = self.width };
    }

    /// Get cursor position
    pub fn getyx(self: *const Self) struct { y: u32, x: u32 } {
        return .{ .y = self.cur_y, .x = self.cur_x };
    }

    /// Set attributes
    pub fn attron(self: *Self, attrs: u32) void {
        self.attrs |= attrs;
    }

    /// Clear attributes
    pub fn attroff(self: *Self, attrs: u32) void {
        self.attrs &= ~attrs;
    }

    /// Set attribute to exact value
    pub fn attrset(self: *Self, attrs: u32) void {
        self.attrs = attrs;
    }

    /// Draw a box
    pub fn box(self: *Self, verch: u8, horch: u8) void {
        const v = if (verch == 0) '|' else verch;
        const h = if (horch == 0) '-' else horch;

        // Top border
        self.buffer[0][0] = '+';
        for (self.buffer[0][1 .. self.width - 1]) |*c| {
            c.* = h;
        }
        self.buffer[0][self.width - 1] = '+';

        // Side borders
        for (self.buffer[1 .. self.height - 1]) |row| {
            row[0] = v;
            row[self.width - 1] = v;
        }

        // Bottom border
        self.buffer[self.height - 1][0] = '+';
        for (self.buffer[self.height - 1][1 .. self.width - 1]) |*c| {
            c.* = h;
        }
        self.buffer[self.height - 1][self.width - 1] = '+';
    }

    /// Draw a border
    pub fn border(self: *Self, ls: u8, rs: u8, ts: u8, bs: u8, tl: u8, tr: u8, bl: u8, br: u8) void {
        _ = ls;
        _ = rs;
        _ = ts;
        _ = bs;
        _ = tl;
        _ = tr;
        _ = bl;
        _ = br;
        self.box(0, 0);
    }
};

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

/// Enable echo
pub fn echo() void {
    // Would enable input echo
}

/// Disable echo
pub fn noecho() void {
    // Would disable input echo
}

/// Enable cbreak mode
pub fn cbreak() void {
    // Would enable cbreak mode
}

/// Disable cbreak mode
pub fn nocbreak() void {
    // Would disable cbreak mode
}

/// Enable raw mode
pub fn raw() void {
    // Would enable raw mode
}

/// Disable raw mode
pub fn noraw() void {
    // Would disable raw mode
}

/// Check if terminal has colors
pub fn has_colors() bool {
    return true;
}

/// Start color support
pub fn start_color() void {
    // Would initialize color pairs
}

/// Initialize a color pair
pub fn init_pair(pair: i16, fg: i16, bg: i16) void {
    _ = pair;
    _ = fg;
    _ = bg;
    // Would set up color pair
}

/// Get color pair attribute
pub fn color_pair(n: i16) u32 {
    return @as(u32, @intCast(n)) << 17;
}

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

// ============================================================================
// Init/Reset
// ============================================================================

pub fn init() void {
    // Called on module import
}

pub fn reset() void {
    if (is_initialized) {
        endwin();
    }
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

test "Window init and deinit" {
    const allocator = std.testing.allocator;
    var win = try Window.init(allocator, 10, 20, 0, 0);
    defer win.deinit();

    try std.testing.expectEqual(@as(u32, 10), win.height);
    try std.testing.expectEqual(@as(u32, 20), win.width);
}

test "Window clear" {
    const allocator = std.testing.allocator;
    var win = try Window.init(allocator, 5, 5, 0, 0);
    defer win.deinit();

    win.addstr("test");
    win.clear();

    try std.testing.expectEqual(@as(u32, 0), win.cur_y);
    try std.testing.expectEqual(@as(u32, 0), win.cur_x);
}

test "Window move" {
    const allocator = std.testing.allocator;
    var win = try Window.init(allocator, 10, 10, 0, 0);
    defer win.deinit();

    win.move(5, 3);
    try std.testing.expectEqual(@as(u32, 5), win.cur_y);
    try std.testing.expectEqual(@as(u32, 3), win.cur_x);
}

test "Window getmaxyx" {
    const allocator = std.testing.allocator;
    var win = try Window.init(allocator, 24, 80, 0, 0);
    defer win.deinit();

    const dims = win.getmaxyx();
    try std.testing.expectEqual(@as(u32, 24), dims.y);
    try std.testing.expectEqual(@as(u32, 80), dims.x);
}
