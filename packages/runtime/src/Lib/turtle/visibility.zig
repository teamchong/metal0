//! Turtle visibility and query methods
//! Mirrors: CPython Lib/turtle.py (visibility and state query sections)

const std = @import("std");
const types = @import("types.zig");
const Point = types.Point;

/// Visibility and query methods for Turtle
pub const Visibility = struct {
    /// Show turtle
    pub fn showturtle(turtle: anytype) void {
        turtle.visible = true;
    }

    /// Alias for showturtle
    pub fn st(turtle: anytype) void {
        showturtle(turtle);
    }

    /// Hide turtle
    pub fn hideturtle(turtle: anytype) void {
        turtle.visible = false;
    }

    /// Alias for hideturtle
    pub fn ht(turtle: anytype) void {
        hideturtle(turtle);
    }

    /// Check if turtle is visible
    pub fn isvisible(turtle: anytype) bool {
        return turtle.visible;
    }

    /// Get current position
    pub fn pos(turtle: anytype) Point {
        return turtle.position;
    }

    /// Alias for pos
    pub fn position_query(turtle: anytype) Point {
        return pos(turtle);
    }

    /// Get x coordinate
    pub fn xcor(turtle: anytype) f64 {
        return turtle.position.x;
    }

    /// Get y coordinate
    pub fn ycor(turtle: anytype) f64 {
        return turtle.position.y;
    }

    /// Get heading
    pub fn heading_query(turtle: anytype) f64 {
        return turtle.heading;
    }

    /// Get distance to point
    pub fn distance(turtle: anytype, x: f64, y: f64) f64 {
        const dx = x - turtle.position.x;
        const dy = y - turtle.position.y;
        return @sqrt(dx * dx + dy * dy);
    }

    /// Get angle towards point
    pub fn towards(turtle: anytype, x: f64, y: f64) f64 {
        const dx = x - turtle.position.x;
        const dy = y - turtle.position.y;
        return std.math.atan2(dy, dx) * 180.0 / std.math.pi;
    }

    /// Clear drawings
    pub fn clear(turtle: anytype) void {
        turtle.lines.clearRetainingCapacity();
    }

    /// Reset to initial state
    pub fn reset_state(turtle: anytype) void {
        turtle.position = .{ .x = 0, .y = 0 };
        turtle.heading = 0;
        turtle.pen_down = true;
        turtle.pen_color = .{ .r = 0, .g = 0, .b = 0 };
        turtle.pen_size = 1;
        turtle.visible = true;
        turtle.lines.clearRetainingCapacity();
    }
};
