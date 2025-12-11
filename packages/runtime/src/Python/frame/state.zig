/// Frame State and Owner Types
/// Mirrors cpython/Python/frame.c frame state management

// ============================================================================
// Frame State
// ============================================================================

/// Frame execution state
/// Mirrors: PyFrameState enum
pub const FrameState = enum(i8) {
    created = -3, // Frame created but not yet executing
    suspended = -2, // Frame suspended (e.g., generator yield)
    suspended_yield_from = -1, // Suspended in yield from
    executing = 0, // Currently executing
    completed = 1, // Execution completed normally
    cleared = 4, // Frame has been cleared
};

/// Check if frame state is suspended
pub fn isStateSuspended(state: FrameState) bool {
    return state == .suspended or state == .suspended_yield_from;
}

/// Check if frame state is finished
pub fn isStateFinished(state: FrameState) bool {
    return @intFromEnum(state) >= @intFromEnum(FrameState.completed);
}

// ============================================================================
// Frame Owner
// ============================================================================

/// Who owns this frame
pub const FrameOwner = enum(u8) {
    thread = 0, // Owned by thread (normal execution)
    generator = 1, // Owned by generator/coroutine
    frame_object = 2, // Owned by PyFrameObject
    cstack = 3, // Owned by C stack
    interpreter = 255, // Owned by interpreter (sentinel)
};
