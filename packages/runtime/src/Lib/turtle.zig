//! CPython source: Lib/turtle.py
//!
//! Turtle graphics implementation for educational programming.
//! Uses a metaphor of a "turtle" that moves around the screen drawing lines.
//!
//! Mirrors: CPython Lib/turtle.py

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const TurtleError = error{
    NoScreen,
    InvalidColor,
    InvalidShape,
    OutOfMemory,
};

// ============================================================================
// Types
// ============================================================================

/// Point in 2D space
pub const Point = struct {
    x: f64 = 0,
    y: f64 = 0,
};

/// RGB Color
pub const Color = struct {
    r: f64 = 0,
    g: f64 = 0,
    b: f64 = 0,
};

/// Line segment
pub const Line = struct {
    start: Point,
    end: Point,
    color: Color,
    width: f64,
};

// ============================================================================
// Turtle
// ============================================================================

/// Turtle graphics object
pub const Turtle = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    // Position and heading
    position: Point = .{ .x = 0, .y = 0 },
    heading: f64 = 0, // Degrees, 0 = east, 90 = north

    // Pen state
    pen_down: bool = true,
    pen_color: Color = .{ .r = 0, .g = 0, .b = 0 },
    pen_size: f64 = 1,
    fill_color: Color = .{ .r = 0, .g = 0, .b = 0 },
    filling: bool = false,

    // Movement
    speed: u32 = 3,

    // Visibility
    visible: bool = true,
    shape: []const u8 = "classic",

    // Drawing history
    lines: std.ArrayList(Line),
    fill_points: std.ArrayList(Point),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .lines = std.ArrayList(Line).init(allocator),
            .fill_points = std.ArrayList(Point).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.lines.deinit();
        self.fill_points.deinit();
    }

    // ========================================================================
    // Movement
    // ========================================================================

    /// Move forward by distance
    pub fn forward(self: *Self, distance: f64) !void {
        const rad = self.heading * std.math.pi / 180.0;
        const new_x = self.position.x + distance * @cos(rad);
        const new_y = self.position.y + distance * @sin(rad);

        if (self.pen_down) {
            try self.lines.append(.{
                .start = self.position,
                .end = .{ .x = new_x, .y = new_y },
                .color = self.pen_color,
                .width = self.pen_size,
            });
        }

        if (self.filling) {
            try self.fill_points.append(.{ .x = new_x, .y = new_y });
        }

        self.position.x = new_x;
        self.position.y = new_y;
    }

    /// Alias for forward
    pub fn fd(self: *Self, distance: f64) !void {
        try self.forward(distance);
    }

    /// Move backward by distance
    pub fn backward(self: *Self, distance: f64) !void {
        try self.forward(-distance);
    }

    /// Alias for backward
    pub fn bk(self: *Self, distance: f64) !void {
        try self.backward(distance);
    }

    /// Alias for backward
    pub fn back(self: *Self, distance: f64) !void {
        try self.backward(distance);
    }

    /// Turn right by angle degrees
    pub fn right(self: *Self, angle: f64) void {
        self.heading = @mod(self.heading - angle, 360.0);
    }

    /// Alias for right
    pub fn rt(self: *Self, angle: f64) void {
        self.right(angle);
    }

    /// Turn left by angle degrees
    pub fn left(self: *Self, angle: f64) void {
        self.heading = @mod(self.heading + angle, 360.0);
    }

    /// Alias for left
    pub fn lt(self: *Self, angle: f64) void {
        self.left(angle);
    }

    /// Go to absolute position
    pub fn goto(self: *Self, x: f64, y: f64) !void {
        const new_pos = Point{ .x = x, .y = y };

        if (self.pen_down) {
            try self.lines.append(.{
                .start = self.position,
                .end = new_pos,
                .color = self.pen_color,
                .width = self.pen_size,
            });
        }

        if (self.filling) {
            try self.fill_points.append(new_pos);
        }

        self.position = new_pos;
    }

    /// Alias for goto
    pub fn setpos(self: *Self, x: f64, y: f64) !void {
        try self.goto(x, y);
    }

    /// Alias for goto
    pub fn setposition(self: *Self, x: f64, y: f64) !void {
        try self.goto(x, y);
    }

    /// Set x coordinate
    pub fn setx(self: *Self, x: f64) !void {
        try self.goto(x, self.position.y);
    }

    /// Set y coordinate
    pub fn sety(self: *Self, y: f64) !void {
        try self.goto(self.position.x, y);
    }

    /// Set heading angle
    pub fn setheading(self: *Self, angle: f64) void {
        self.heading = @mod(angle, 360.0);
    }

    /// Alias for setheading
    pub fn seth(self: *Self, angle: f64) void {
        self.setheading(angle);
    }

    /// Go to home position (0, 0) with heading 0
    pub fn home(self: *Self) !void {
        try self.goto(0, 0);
        self.heading = 0;
    }

    /// Draw a circle
    pub fn circle(self: *Self, radius: f64, extent: f64) !void {
        const steps: u32 = @intFromFloat(@abs(extent) / 3);
        const step_len = 2.0 * radius * std.math.pi * extent / 360.0 / @as(f64, @floatFromInt(steps));
        const step_angle = extent / @as(f64, @floatFromInt(steps));

        for (0..steps) |_| {
            try self.forward(step_len);
            self.left(step_angle);
        }
    }

    /// Draw a dot
    pub fn dot(self: *Self, size: ?f64) !void {
        _ = self;
        _ = size;
        // Would draw a filled circle at current position
    }

    /// Stamp turtle shape
    pub fn stamp(self: *Self) u32 {
        _ = self;
        return 0;
    }

    // ========================================================================
    // Pen control
    // ========================================================================

    /// Lift pen up (no drawing)
    pub fn penup(self: *Self) void {
        self.pen_down = false;
    }

    /// Alias for penup
    pub fn pu(self: *Self) void {
        self.penup();
    }

    /// Alias for penup
    pub fn up(self: *Self) void {
        self.penup();
    }

    /// Put pen down (drawing)
    pub fn pendown(self: *Self) void {
        self.pen_down = true;
    }

    /// Alias for pendown
    pub fn pd(self: *Self) void {
        self.pendown();
    }

    /// Alias for pendown
    pub fn down(self: *Self) void {
        self.pendown();
    }

    /// Check if pen is down
    pub fn isdown(self: *const Self) bool {
        return self.pen_down;
    }

    /// Set pen size
    pub fn pensize(self: *Self, width: f64) void {
        self.pen_size = width;
    }

    /// Alias for pensize
    pub fn width(self: *Self, w: f64) void {
        self.pensize(w);
    }

    /// Set pen color
    pub fn pencolor(self: *Self, r: f64, g: f64, b: f64) void {
        self.pen_color = .{ .r = r, .g = g, .b = b };
    }

    /// Set fill color
    pub fn fillcolor(self: *Self, r: f64, g: f64, b: f64) void {
        self.fill_color = .{ .r = r, .g = g, .b = b };
    }

    /// Set both pen and fill color
    pub fn color(self: *Self, r: f64, g: f64, b: f64) void {
        self.pencolor(r, g, b);
        self.fillcolor(r, g, b);
    }

    /// Begin filling
    pub fn begin_fill(self: *Self) void {
        self.filling = true;
        self.fill_points.clearRetainingCapacity();
    }

    /// End filling
    pub fn end_fill(self: *Self) void {
        self.filling = false;
    }

    // ========================================================================
    // Visibility
    // ========================================================================

    /// Show turtle
    pub fn showturtle(self: *Self) void {
        self.visible = true;
    }

    /// Alias for showturtle
    pub fn st(self: *Self) void {
        self.showturtle();
    }

    /// Hide turtle
    pub fn hideturtle(self: *Self) void {
        self.visible = false;
    }

    /// Alias for hideturtle
    pub fn ht(self: *Self) void {
        self.hideturtle();
    }

    /// Check if turtle is visible
    pub fn isvisible(self: *const Self) bool {
        return self.visible;
    }

    // ========================================================================
    // Query state
    // ========================================================================

    /// Get current position
    pub fn pos(self: *const Self) Point {
        return self.position;
    }

    /// Alias for pos
    pub fn position_query(self: *const Self) Point {
        return self.pos();
    }

    /// Get x coordinate
    pub fn xcor(self: *const Self) f64 {
        return self.position.x;
    }

    /// Get y coordinate
    pub fn ycor(self: *const Self) f64 {
        return self.position.y;
    }

    /// Get heading
    pub fn heading_query(self: *const Self) f64 {
        return self.heading;
    }

    /// Get distance to point
    pub fn distance(self: *const Self, x: f64, y: f64) f64 {
        const dx = x - self.position.x;
        const dy = y - self.position.y;
        return @sqrt(dx * dx + dy * dy);
    }

    /// Get angle towards point
    pub fn towards(self: *const Self, x: f64, y: f64) f64 {
        const dx = x - self.position.x;
        const dy = y - self.position.y;
        return std.math.atan2(dy, dx) * 180.0 / std.math.pi;
    }

    /// Clear drawings
    pub fn clear(self: *Self) void {
        self.lines.clearRetainingCapacity();
    }

    /// Reset to initial state
    pub fn reset_state(self: *Self) void {
        self.position = .{ .x = 0, .y = 0 };
        self.heading = 0;
        self.pen_down = true;
        self.pen_color = .{ .r = 0, .g = 0, .b = 0 };
        self.pen_size = 1;
        self.visible = true;
        self.lines.clearRetainingCapacity();
    }
};

// ============================================================================
// Screen
// ============================================================================

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
            .turtles = std.ArrayList(*Turtle).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.turtles.deinit();
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
// Module State
// ============================================================================

var global_screen: ?*Screen = null;
var global_turtle: ?*Turtle = null;
var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
}

pub fn reset() void {
    global_screen = null;
    global_turtle = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "Point" {
    const p = Point{ .x = 3, .y = 4 };
    try std.testing.expectEqual(@as(f64, 3), p.x);
    try std.testing.expectEqual(@as(f64, 4), p.y);
}

test "Turtle init" {
    const allocator = std.testing.allocator;
    var turtle = Turtle.init(allocator);
    defer turtle.deinit();

    try std.testing.expectEqual(@as(f64, 0), turtle.position.x);
    try std.testing.expectEqual(@as(f64, 0), turtle.position.y);
    try std.testing.expect(turtle.pen_down);
}

test "Turtle forward" {
    const allocator = std.testing.allocator;
    var turtle = Turtle.init(allocator);
    defer turtle.deinit();

    try turtle.forward(100);
    try std.testing.expectApproxEqAbs(@as(f64, 100), turtle.position.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0), turtle.position.y, 0.001);
}

test "Turtle turn" {
    const allocator = std.testing.allocator;
    var turtle = Turtle.init(allocator);
    defer turtle.deinit();

    turtle.left(90);
    try std.testing.expectApproxEqAbs(@as(f64, 90), turtle.heading, 0.001);

    turtle.right(45);
    try std.testing.expectApproxEqAbs(@as(f64, 45), turtle.heading, 0.001);
}

test "Turtle penup/pendown" {
    const allocator = std.testing.allocator;
    var turtle = Turtle.init(allocator);
    defer turtle.deinit();

    try std.testing.expect(turtle.isdown());
    turtle.penup();
    try std.testing.expect(!turtle.isdown());
    turtle.pendown();
    try std.testing.expect(turtle.isdown());
}

test "Turtle goto" {
    const allocator = std.testing.allocator;
    var turtle = Turtle.init(allocator);
    defer turtle.deinit();

    try turtle.goto(50, 100);
    try std.testing.expectEqual(@as(f64, 50), turtle.position.x);
    try std.testing.expectEqual(@as(f64, 100), turtle.position.y);
}

test "Turtle distance" {
    const allocator = std.testing.allocator;
    var turtle = Turtle.init(allocator);
    defer turtle.deinit();

    const d = turtle.distance(3, 4);
    try std.testing.expectApproxEqAbs(@as(f64, 5), d, 0.001);
}

test "Screen init" {
    const allocator = std.testing.allocator;
    var screen = Screen.init(allocator);
    defer screen.deinit();

    try std.testing.expectEqual(@as(u32, 800), screen.width);
    try std.testing.expectEqual(@as(u32, 600), screen.height);
}
