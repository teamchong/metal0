/// traceback/init - Traceback Initialization
/// Mirrors cpython/Python/traceback.c
///
/// This module provides:
/// - Initialize traceback subsystem
/// - Finalize traceback subsystem

const stack = @import("stack.zig");
const repeat = @import("repeat.zig");

/// Initialize traceback subsystem
pub fn init() void {
    stack.clearStack();
    repeat.reset();
}

/// Finalize traceback subsystem
pub fn fini() void {
    stack.clearStack();
}
