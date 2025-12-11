//! Turtle class definition with delegated method implementations
//! Mirrors: CPython Lib/turtle.py (Turtle class)

const std = @import("std");
const types = @import("types.zig");
const movement = @import("movement.zig");
const pen = @import("pen.zig");
const visibility = @import("visibility.zig");

const Point = types.Point;
const Color = types.Color;
const Line = types.Line;

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
        self.lines.deinit(self.allocator);
        self.fill_points.deinit(self.allocator);
    }

    // ========================================================================
    // Movement - Delegate to movement module
    // ========================================================================

    pub fn forward(self: *Self, distance: f64) !void {
        try movement.Movement.forward(self, distance);
    }

    pub fn fd(self: *Self, distance: f64) !void {
        try movement.Movement.fd(self, distance);
    }

    pub fn backward(self: *Self, distance: f64) !void {
        try movement.Movement.backward(self, distance);
    }

    pub fn bk(self: *Self, distance: f64) !void {
        try movement.Movement.bk(self, distance);
    }

    pub fn back(self: *Self, distance: f64) !void {
        try movement.Movement.back(self, distance);
    }

    pub fn right(self: *Self, angle: f64) void {
        movement.Movement.right(self, angle);
    }

    pub fn rt(self: *Self, angle: f64) void {
        movement.Movement.rt(self, angle);
    }

    pub fn left(self: *Self, angle: f64) void {
        movement.Movement.left(self, angle);
    }

    pub fn lt(self: *Self, angle: f64) void {
        movement.Movement.lt(self, angle);
    }

    pub fn goto(self: *Self, x: f64, y: f64) !void {
        try movement.Movement.goto(self, x, y);
    }

    pub fn setpos(self: *Self, x: f64, y: f64) !void {
        try movement.Movement.setpos(self, x, y);
    }

    pub fn setposition(self: *Self, x: f64, y: f64) !void {
        try movement.Movement.setposition(self, x, y);
    }

    pub fn setx(self: *Self, x: f64) !void {
        try movement.Movement.setx(self, x);
    }

    pub fn sety(self: *Self, y: f64) !void {
        try movement.Movement.sety(self, y);
    }

    pub fn setheading(self: *Self, angle: f64) void {
        movement.Movement.setheading(self, angle);
    }

    pub fn seth(self: *Self, angle: f64) void {
        movement.Movement.seth(self, angle);
    }

    pub fn home(self: *Self) !void {
        try movement.Movement.home(self);
    }

    pub fn circle(self: *Self, radius: f64, extent: f64) !void {
        try movement.Movement.circle(self, radius, extent);
    }

    pub fn dot(self: *Self, size: ?f64) !void {
        try movement.Movement.dot(self, size);
    }

    pub fn stamp(self: *Self) u32 {
        return movement.Movement.stamp(self);
    }

    // ========================================================================
    // Pen control - Delegate to pen module
    // ========================================================================

    pub fn penup(self: *Self) void {
        pen.Pen.penup(self);
    }

    pub fn pu(self: *Self) void {
        pen.Pen.pu(self);
    }

    pub fn up(self: *Self) void {
        pen.Pen.up(self);
    }

    pub fn pendown(self: *Self) void {
        pen.Pen.pendown(self);
    }

    pub fn pd(self: *Self) void {
        pen.Pen.pd(self);
    }

    pub fn down(self: *Self) void {
        pen.Pen.down(self);
    }

    pub fn isdown(self: *const Self) bool {
        return pen.Pen.isdown(self);
    }

    pub fn pensize(self: *Self, width: f64) void {
        pen.Pen.pensize(self, width);
    }

    pub fn width(self: *Self, w: f64) void {
        pen.Pen.width(self, w);
    }

    pub fn pencolor(self: *Self, r: f64, g: f64, b: f64) void {
        pen.Pen.pencolor(self, r, g, b);
    }

    pub fn fillcolor(self: *Self, r: f64, g: f64, b: f64) void {
        pen.Pen.fillcolor(self, r, g, b);
    }

    pub fn color(self: *Self, r: f64, g: f64, b: f64) void {
        pen.Pen.color(self, r, g, b);
    }

    pub fn begin_fill(self: *Self) void {
        pen.Pen.begin_fill(self);
    }

    pub fn end_fill(self: *Self) void {
        pen.Pen.end_fill(self);
    }

    // ========================================================================
    // Visibility and query - Delegate to visibility module
    // ========================================================================

    pub fn showturtle(self: *Self) void {
        visibility.Visibility.showturtle(self);
    }

    pub fn st(self: *Self) void {
        visibility.Visibility.st(self);
    }

    pub fn hideturtle(self: *Self) void {
        visibility.Visibility.hideturtle(self);
    }

    pub fn ht(self: *Self) void {
        visibility.Visibility.ht(self);
    }

    pub fn isvisible(self: *const Self) bool {
        return visibility.Visibility.isvisible(self);
    }

    pub fn pos(self: *const Self) Point {
        return visibility.Visibility.pos(self);
    }

    pub fn position_query(self: *const Self) Point {
        return visibility.Visibility.position_query(self);
    }

    pub fn xcor(self: *const Self) f64 {
        return visibility.Visibility.xcor(self);
    }

    pub fn ycor(self: *const Self) f64 {
        return visibility.Visibility.ycor(self);
    }

    pub fn heading_query(self: *const Self) f64 {
        return visibility.Visibility.heading_query(self);
    }

    pub fn distance(self: *const Self, x: f64, y: f64) f64 {
        return visibility.Visibility.distance(self, x, y);
    }

    pub fn towards(self: *const Self, x: f64, y: f64) f64 {
        return visibility.Visibility.towards(self, x, y);
    }

    pub fn clear(self: *Self) void {
        visibility.Visibility.clear(self);
    }

    pub fn reset_state(self: *Self) void {
        visibility.Visibility.reset_state(self);
    }
};

// ============================================================================
// Tests
// ============================================================================

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
