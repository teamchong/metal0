//! Core types and error definitions for turtle graphics
//! Mirrors: CPython Lib/turtle.py (types section)

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
// Tests
// ============================================================================

test "Point" {
    const p = Point{ .x = 3, .y = 4 };
    try std.testing.expectEqual(@as(f64, 3), p.x);
    try std.testing.expectEqual(@as(f64, 4), p.y);
}
