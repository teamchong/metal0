//! Turtle movement methods
//! Mirrors: CPython Lib/turtle.py (movement section)

const std = @import("std");
const types = @import("types.zig");
const Point = types.Point;
const Line = types.Line;
const Color = types.Color;

/// Movement methods for Turtle
pub const Movement = struct {
    /// Move forward by distance
    pub fn forward(turtle: anytype, distance: f64) !void {
        const rad = turtle.heading * std.math.pi / 180.0;
        const new_x = turtle.position.x + distance * @cos(rad);
        const new_y = turtle.position.y + distance * @sin(rad);

        if (turtle.pen_down) {
            try turtle.lines.append(turtle.allocator, .{
                .start = turtle.position,
                .end = .{ .x = new_x, .y = new_y },
                .color = turtle.pen_color,
                .width = turtle.pen_size,
            });
        }

        if (turtle.filling) {
            try turtle.fill_points.append(turtle.allocator, .{ .x = new_x, .y = new_y });
        }

        turtle.position.x = new_x;
        turtle.position.y = new_y;
    }

    /// Alias for forward
    pub fn fd(turtle: anytype, distance: f64) !void {
        try forward(turtle, distance);
    }

    /// Move backward by distance
    pub fn backward(turtle: anytype, distance: f64) !void {
        try forward(turtle, -distance);
    }

    /// Alias for backward
    pub fn bk(turtle: anytype, distance: f64) !void {
        try backward(turtle, distance);
    }

    /// Alias for backward
    pub fn back(turtle: anytype, distance: f64) !void {
        try backward(turtle, distance);
    }

    /// Turn right by angle degrees
    pub fn right(turtle: anytype, angle: f64) void {
        turtle.heading = @mod(turtle.heading - angle, 360.0);
    }

    /// Alias for right
    pub fn rt(turtle: anytype, angle: f64) void {
        right(turtle, angle);
    }

    /// Turn left by angle degrees
    pub fn left(turtle: anytype, angle: f64) void {
        turtle.heading = @mod(turtle.heading + angle, 360.0);
    }

    /// Alias for left
    pub fn lt(turtle: anytype, angle: f64) void {
        left(turtle, angle);
    }

    /// Go to absolute position
    pub fn goto(turtle: anytype, x: f64, y: f64) !void {
        const new_pos = Point{ .x = x, .y = y };

        if (turtle.pen_down) {
            try turtle.lines.append(turtle.allocator, .{
                .start = turtle.position,
                .end = new_pos,
                .color = turtle.pen_color,
                .width = turtle.pen_size,
            });
        }

        if (turtle.filling) {
            try turtle.fill_points.append(turtle.allocator, new_pos);
        }

        turtle.position = new_pos;
    }

    /// Alias for goto
    pub fn setpos(turtle: anytype, x: f64, y: f64) !void {
        try goto(turtle, x, y);
    }

    /// Alias for goto
    pub fn setposition(turtle: anytype, x: f64, y: f64) !void {
        try goto(turtle, x, y);
    }

    /// Set x coordinate
    pub fn setx(turtle: anytype, x: f64) !void {
        try goto(turtle, x, turtle.position.y);
    }

    /// Set y coordinate
    pub fn sety(turtle: anytype, y: f64) !void {
        try goto(turtle, turtle.position.x, y);
    }

    /// Set heading angle
    pub fn setheading(turtle: anytype, angle: f64) void {
        turtle.heading = @mod(angle, 360.0);
    }

    /// Alias for setheading
    pub fn seth(turtle: anytype, angle: f64) void {
        setheading(turtle, angle);
    }

    /// Go to home position (0, 0) with heading 0
    pub fn home(turtle: anytype) !void {
        try goto(turtle, 0, 0);
        turtle.heading = 0;
    }

    /// Draw a circle
    pub fn circle(turtle: anytype, radius: f64, extent: f64) !void {
        const steps: u32 = @intFromFloat(@abs(extent) / 3);
        const step_len = 2.0 * radius * std.math.pi * extent / 360.0 / @as(f64, @floatFromInt(steps));
        const step_angle = extent / @as(f64, @floatFromInt(steps));

        for (0..steps) |_| {
            try forward(turtle, step_len);
            left(turtle, step_angle);
        }
    }

    /// Draw a dot (filled circle) at current position
    pub fn dot(turtle: anytype, size: ?f64) !void {
        const dot_size = size orelse @max(turtle.pen_size + 4, turtle.pen_size * 2);

        // Approximate a dot as a very short line at current position
        // (A proper implementation would use a separate circles list)
        const current = turtle.position;
        try turtle.lines.append(turtle.allocator, .{
            .start = current,
            .end = .{ .x = current.x + 0.1, .y = current.y + 0.1 },
            .color = turtle.pen_color,
            .width = dot_size,
        });
    }

    /// Stamp turtle shape
    pub fn stamp(turtle: anytype) u32 {
        _ = turtle;
        return 0;
    }
};
