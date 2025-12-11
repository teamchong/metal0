/// Frame evaluation control for ceval
/// Mirrors part of cpython/Python/ceval.c
const std = @import("std");

/// Frame evaluation function signature
pub const FrameEvalFunction = *const fn (
    tstate: ?*anyopaque,
    frame: ?*anyopaque,
    throw_flag: c_int,
) callconv(.C) ?*anyopaque;

/// Custom frame evaluation function
var frame_eval_func: ?FrameEvalFunction = null;

/// Set custom frame evaluation function
pub fn setEvalFrameFunc(func: ?FrameEvalFunction) void {
    frame_eval_func = func;
}

/// Get current frame evaluation function
pub fn getEvalFrameFunc() ?FrameEvalFunction {
    return frame_eval_func;
}

/// Get current frame
pub fn getFrame() ?*anyopaque {
    return null;
}

/// Set current frame
pub fn setFrame(frame: ?*anyopaque) void {
    _ = frame;
}

/// Get builtins from current context
pub fn getBuiltins() ?*anyopaque {
    return null;
}

/// Get globals from current context
pub fn getGlobals() ?*anyopaque {
    return null;
}

/// Get locals from current frame
pub fn getFrameLocals() ?*anyopaque {
    return null;
}
