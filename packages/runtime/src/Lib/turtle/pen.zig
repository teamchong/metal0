//! Turtle pen control methods
//! Mirrors: CPython Lib/turtle.py (pen control section)

const std = @import("std");
const types = @import("types.zig");
const Color = types.Color;

/// Pen control methods for Turtle
pub const Pen = struct {
    /// Lift pen up (no drawing)
    pub fn penup(turtle: anytype) void {
        turtle.pen_down = false;
    }

    /// Alias for penup
    pub fn pu(turtle: anytype) void {
        penup(turtle);
    }

    /// Alias for penup
    pub fn up(turtle: anytype) void {
        penup(turtle);
    }

    /// Put pen down (drawing)
    pub fn pendown(turtle: anytype) void {
        turtle.pen_down = true;
    }

    /// Alias for pendown
    pub fn pd(turtle: anytype) void {
        pendown(turtle);
    }

    /// Alias for pendown
    pub fn down(turtle: anytype) void {
        pendown(turtle);
    }

    /// Check if pen is down
    pub fn isdown(turtle: anytype) bool {
        return turtle.pen_down;
    }

    /// Set pen size
    pub fn pensize(turtle: anytype, width: f64) void {
        turtle.pen_size = width;
    }

    /// Alias for pensize
    pub fn width(turtle: anytype, w: f64) void {
        pensize(turtle, w);
    }

    /// Set pen color
    pub fn pencolor(turtle: anytype, r: f64, g: f64, b: f64) void {
        turtle.pen_color = .{ .r = r, .g = g, .b = b };
    }

    /// Set fill color
    pub fn fillcolor(turtle: anytype, r: f64, g: f64, b: f64) void {
        turtle.fill_color = .{ .r = r, .g = g, .b = b };
    }

    /// Set both pen and fill color
    pub fn color(turtle: anytype, r: f64, g: f64, b: f64) void {
        pencolor(turtle, r, g, b);
        fillcolor(turtle, r, g, b);
    }

    /// Begin filling
    pub fn begin_fill(turtle: anytype) void {
        turtle.filling = true;
        turtle.fill_points.clearRetainingCapacity();
    }

    /// End filling
    pub fn end_fill(turtle: anytype) void {
        turtle.filling = false;
    }
};
