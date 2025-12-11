/// traceback/capture - Traceback Capture from Frames
/// Mirrors cpython/Python/traceback.c
///
/// This module provides:
/// - Create traceback from interpreter frames
/// - Capture current call stack
/// - Convert frame chains to traceback chains

const std = @import("std");
const types = @import("types.zig");
const frame_mod = @import("../frame.zig");

/// Create traceback from interpreter frame
/// Mirrors: _PyTraceBack_FromFrame
pub fn fromFrame(allocator: std.mem.Allocator, frame: *frame_mod.InterpreterFrame) !*types.PyTracebackObject {
    // Get or create frame object
    const frame_obj = try frame_mod.getFrameObject(allocator, frame);

    return types.PyTracebackObject.create(
        allocator,
        null,
        frame_obj,
        frame.getLasti(),
        frame_mod.getFrameLine(frame),
    );
}

/// Capture current call stack as traceback
pub fn captureStack(allocator: std.mem.Allocator) !?*types.PyTracebackObject {
    var frame = frame_mod.getCurrentFrame();
    if (frame == null) return null;

    var tb: ?*types.PyTracebackObject = null;
    var depth: usize = 0;

    while (frame) |f| : (depth += 1) {
        if (depth >= types.MAX_FRAME_DEPTH) break;

        const frame_obj = try frame_mod.getFrameObject(allocator, f);
        const entry = try types.PyTracebackObject.create(
            allocator,
            tb,
            frame_obj,
            f.getLasti(),
            frame_mod.getFrameLine(f),
        );
        tb = entry;

        frame = f.previous;
    }

    return tb;
}
