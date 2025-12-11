/// frame - Frame Object Implementation
/// Mirrors cpython/Python/frame.c and pycore_frame.h
///
/// This module provides:
/// - PyFrameObject: The Python frame object visible to Python code
/// - InterpreterFrame: The internal execution frame
/// - Frame state management (created, executing, suspended, completed)
/// - Stack and locals management
/// - Frame traversal and cleanup

const std = @import("std");

// Re-export submodules
pub const state = @import("frame/state.zig");
pub const interpreter_frame = @import("frame/interpreter_frame.zig");
pub const frame_object = @import("frame/frame_object.zig");
pub const stack_management = @import("frame/stack_management.zig");
pub const line_table = @import("frame/line_table.zig");
pub const utilities = @import("frame/utilities.zig");

// Re-export commonly used types
pub const FrameState = state.FrameState;
pub const FrameOwner = state.FrameOwner;
pub const isStateSuspended = state.isStateSuspended;
pub const isStateFinished = state.isStateFinished;

pub const InterpreterFrame = interpreter_frame.InterpreterFrame;
pub const PyFrameObject = frame_object.PyFrameObject;

pub const getCurrentFrame = stack_management.getCurrentFrame;
pub const setCurrentFrame = stack_management.setCurrentFrame;
pub const pushFrame = stack_management.pushFrame;
pub const popFrame = stack_management.popFrame;
pub const getFirstComplete = stack_management.getFirstComplete;
pub const getFrameObject = stack_management.getFrameObject;
pub const makeAndSetFrameObject = stack_management.makeAndSetFrameObject;

pub const LineTableEntry = line_table.LineTableEntry;
pub const setLineTable = line_table.setLineTable;
pub const clearLineTable = line_table.clearLineTable;
pub const getFrameLine = line_table.getFrameLine;

pub const ExecutableKind = utilities.ExecutableKind;
pub const numSlotsForCode = utilities.numSlotsForCode;
pub const getLocalsArray = utilities.getLocalsArray;
pub const getStackbase = utilities.getStackbase;
pub const setStackPointer = utilities.setStackPointer;

pub const init = stack_management.init;
pub const fini = stack_management.fini;

// ============================================================================
// Tests
// ============================================================================

test "frame state helpers" {
    try std.testing.expect(isStateSuspended(.suspended));
    try std.testing.expect(isStateSuspended(.suspended_yield_from));
    try std.testing.expect(!isStateSuspended(.executing));

    try std.testing.expect(isStateFinished(.completed));
    try std.testing.expect(isStateFinished(.cleared));
    try std.testing.expect(!isStateFinished(.executing));
}

test "interpreter frame basics" {
    var frame = InterpreterFrame.init(null, null, null);
    frame.nlocalsplus = 3;

    // Test locals
    frame.setLocal(0, @ptrFromInt(0x1000));
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x1000)), frame.getLocal(0));

    // Test stack
    frame.stackpointer = frame.stackBase();
    try std.testing.expectEqual(@as(usize, 0), frame.stackDepth());

    frame.stackPush(@ptrFromInt(0x2000));
    try std.testing.expectEqual(@as(usize, 1), frame.stackDepth());
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x2000)), frame.stackPeek());

    const popped = frame.stackPop();
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x2000)), popped);
    try std.testing.expectEqual(@as(usize, 0), frame.stackDepth());
}

test "frame object creation" {
    const allocator = std.testing.allocator;

    const frame = try PyFrameObject.create(allocator, null);
    defer frame.destroy();

    try std.testing.expect(frame.f_frame != null);
    try std.testing.expect(frame.f_frame.?.frame_obj == frame);
    try std.testing.expectEqual(FrameOwner.frame_object, frame.f_frame.?.owner);
}

test "frame stack management" {
    var frame1 = InterpreterFrame.init(null, null, null);
    var frame2 = InterpreterFrame.init(null, null, null);

    try std.testing.expect(getCurrentFrame() == null);

    pushFrame(&frame1);
    try std.testing.expect(getCurrentFrame() == &frame1);

    pushFrame(&frame2);
    try std.testing.expect(getCurrentFrame() == &frame2);
    try std.testing.expect(frame2.previous == &frame1);

    _ = popFrame();
    try std.testing.expect(getCurrentFrame() == &frame1);

    _ = popFrame();
    try std.testing.expect(getCurrentFrame() == null);
}

test "frame copy" {
    var src = InterpreterFrame.init(@ptrFromInt(0x1000), @ptrFromInt(0x2000), @ptrFromInt(0x3000));
    src.nlocalsplus = 2;
    src.stackpointer = 4;
    src.setLocal(0, @ptrFromInt(0x4000));
    src.setLocal(1, @ptrFromInt(0x5000));

    var dest: InterpreterFrame = undefined;
    src.copy(&dest);

    try std.testing.expectEqual(src.f_executable, dest.f_executable);
    try std.testing.expectEqual(src.f_globals, dest.f_globals);
    try std.testing.expectEqual(src.f_builtins, dest.f_builtins);
    try std.testing.expectEqual(src.nlocalsplus, dest.nlocalsplus);
    try std.testing.expectEqual(src.stackpointer, dest.stackpointer);
    try std.testing.expectEqual(src.getLocal(0), dest.getLocal(0));
    try std.testing.expect(dest.previous == null); // Should not copy previous
}
