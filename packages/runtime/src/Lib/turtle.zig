//! CPython source: Lib/turtle.py
//!
//! Turtle graphics implementation for educational programming.
//! Uses a metaphor of a "turtle" that moves around the screen drawing lines.
//!
//! Mirrors: CPython Lib/turtle.py

// Re-export all submodules
pub const types = @import("turtle/types.zig");
pub const movement = @import("turtle/movement.zig");
pub const pen = @import("turtle/pen.zig");
pub const visibility = @import("turtle/visibility.zig");
pub const turtle_class = @import("turtle/turtle_class.zig");
pub const screen = @import("turtle/screen.zig");
pub const state = @import("turtle/state.zig");

// Re-export commonly used types
pub const TurtleError = types.TurtleError;
pub const Point = types.Point;
pub const Color = types.Color;
pub const Line = types.Line;
pub const Turtle = turtle_class.Turtle;
pub const Screen = screen.Screen;

// Re-export module state functions
pub const init = state.init;
pub const reset = state.reset;
