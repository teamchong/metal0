//! Turtle graphics screen management
//! Mirrors: CPython Lib/turtle.py (Screen class)

const std = @import("std");
const types = @import("types.zig");
const turtle_class = @import("turtle_class.zig");

const Color = types.Color;
const Turtle = turtle_class.Turtle;

/// Turtle graphics screen
pub const Screen = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    width: u32 = 800,
    height: u32 = 600,
    bgcolor_color: Color = .{ .r = 1, .g = 1, .b = 1 },
    title_text: []const u8 = "Python Turtle Graphics",
    turtles: std.ArrayList(*Turtle),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .turtles = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.turtles.deinit(self.allocator);
    }

    /// Set screen size
    pub fn setup(self: *Self, w: u32, h: u32) void {
        self.width = w;
        self.height = h;
    }

    /// Set background color
    pub fn bgcolor(self: *Self, r: f64, g: f64, b: f64) void {
        self.bgcolor_color = .{ .r = r, .g = g, .b = b };
    }

    /// Set title
    pub fn title(self: *Self, t: []const u8) void {
        self.title_text = t;
    }

    /// Clear screen
    pub fn clear(self: *Self) void {
        for (self.turtles.items) |turtle| {
            turtle.clear();
        }
    }

    /// Reset screen
    pub fn reset_screen(self: *Self) void {
        for (self.turtles.items) |turtle| {
            turtle.reset_state();
        }
    }

    /// Exit on click
    pub fn exitonclick(self: *Self) void {
        _ = self;
    }

    /// Main loop
    pub fn mainloop(self: *Self) void {
        _ = self;
    }

    /// Bye - close window
    pub fn bye(self: *Self) void {
        _ = self;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Screen init" {
    const allocator = std.testing.allocator;
    var screen = Screen.init(allocator);
    defer screen.deinit();

    try std.testing.expectEqual(@as(u32, 800), screen.width);
    try std.testing.expectEqual(@as(u32, 600), screen.height);
}
