/// gilstate - GIL State Management
/// GIL acquisition and release for multi-threaded access.

const std = @import("std");
const types = @import("types.zig");
const global = @import("global.zig");
const thread_state = @import("thread_state.zig");

pub const GILState = types.GILState;
pub const ThreadState = types.ThreadState;

// ============================================================================
// GIL State Functions
// ============================================================================

/// Ensure GIL is held
/// Mirrors: PyGILState_Ensure()
pub fn gilStateEnsure() GILState {
    var tstate = global._tss_tstate;

    if (tstate != null) {
        tstate.?.gilstate_counter += 1;
        return .locked;
    }

    // Create new thread state
    const interp = global.interpreters.main orelse return .unlocked;
    tstate = thread_state.threadStateNewWithWhence(interp, .gilstate);
    if (tstate == null) {
        return .unlocked;
    }

    thread_state.threadStateBind(tstate.?);
    _ = thread_state.threadStateSwap(tstate);
    tstate.?.gilstate_counter = 1;
    global._tss_gilstate = tstate;

    return .unlocked;
}

/// Release GIL
/// Mirrors: PyGILState_Release()
pub fn gilStateRelease(state: GILState) void {
    const tstate = global._tss_tstate orelse return;

    tstate.gilstate_counter -= 1;

    if (tstate.gilstate_counter == 0 and state == .unlocked) {
        // We created this thread state, clean it up
        _ = thread_state.threadStateSwap(null);
        thread_state.threadStateDelete(tstate);
        global._tss_gilstate = null;
    }
}

/// Check if GIL is held by current thread
/// Mirrors: PyGILState_Check()
pub fn gilStateCheck() bool {
    return global._tss_tstate != null;
}

/// Get the thread state for GILState
/// Mirrors: PyGILState_GetThisThreadState()
pub fn gilStateGetThisThreadState() ?*ThreadState {
    return global._tss_gilstate;
}
