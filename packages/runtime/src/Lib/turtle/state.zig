//! Global module state for turtle graphics
//! Mirrors: CPython Lib/turtle.py (module state)

const screen = @import("screen.zig");
const turtle_class = @import("turtle_class.zig");

const Screen = screen.Screen;
const Turtle = turtle_class.Turtle;

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
