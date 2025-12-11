//! Curses window management
//!
//! Provides the Window struct and all window operations including
//! character/string output, cursor movement, attributes, and drawing.

const std = @import("std");
const types = @import("types.zig");

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
    attrs: u32 = types.A_NORMAL,
    /// Window buffer
    buffer: [][]u8,
    /// Keypad mode enabled
    keypad_enabled: bool = false,

    pub fn init(allocator: std.mem.Allocator, height: u32, width: u32, y: u32, x: u32) !Self {
        const buffer = try allocator.alloc([]u8, height);
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
// Tests
// ============================================================================

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
