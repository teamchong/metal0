/// Frame Stack Management
/// Thread-local frame stack operations

const std = @import("std");
const InterpreterFrame = @import("interpreter_frame.zig").InterpreterFrame;
const PyFrameObject = @import("frame_object.zig").PyFrameObject;

// ============================================================================
// Frame Stack Management
// ============================================================================

/// Thread-local current frame
threadlocal var current_frame: ?*InterpreterFrame = null;

/// Get the current interpreter frame
pub fn getCurrentFrame() ?*InterpreterFrame {
    return current_frame;
}

/// Set the current interpreter frame
pub fn setCurrentFrame(frame: ?*InterpreterFrame) void {
    current_frame = frame;
}

/// Push a frame onto the stack
pub fn pushFrame(frame: *InterpreterFrame) void {
    frame.previous = current_frame;
    current_frame = frame;
}

/// Pop the current frame from the stack
pub fn popFrame() ?*InterpreterFrame {
    const frame = current_frame;
    if (frame) |f| {
        current_frame = f.previous;
    }
    return frame;
}

/// Get the first complete frame in the chain
pub fn getFirstComplete(frame: ?*InterpreterFrame) ?*InterpreterFrame {
    var f = frame;
    while (f) |fr| {
        if (!fr.isIncomplete()) {
            return fr;
        }
        f = fr.previous;
    }
    return null;
}

/// Get or create a frame object for an interpreter frame
pub fn getFrameObject(allocator: std.mem.Allocator, frame: *InterpreterFrame) !*PyFrameObject {
    if (frame.frame_obj) |f| {
        return f;
    }
    const f = try makeAndSetFrameObject(allocator, frame);
    return f;
}

/// Create and associate a frame object with an interpreter frame
/// Mirrors: _PyFrame_MakeAndSetFrameObject
pub fn makeAndSetFrameObject(allocator: std.mem.Allocator, frame: *InterpreterFrame) !*PyFrameObject {
    if (frame.frame_obj != null) {
        return frame.frame_obj.?;
    }

    const f = try PyFrameObject.createNoTrack(allocator, frame.getCode());

    // Link the interpreter frame
    f.f_frame = frame;
    frame.frame_obj = f;

    // Link f_back to previous frame's PyFrameObject
    const prev = getFirstComplete(frame.previous);
    if (prev) |p| {
        const back = try getFrameObject(allocator, p);
        f.f_back = back;
    }

    return f;
}

// ============================================================================
// Initialization
// ============================================================================

/// Initialize the frame subsystem
pub fn init() void {
    current_frame = null;
}

/// Finalize the frame subsystem
pub fn fini() void {
    current_frame = null;
}
