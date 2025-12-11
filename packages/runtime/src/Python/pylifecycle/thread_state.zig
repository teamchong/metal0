/// pylifecycle thread state management
const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const state = @import("state.zig");
const init = @import("init.zig");
const types = @import("types.zig");

const ThreadState = state.ThreadState;
const InterpreterState = state.InterpreterState;

/// Check if Python is initialized
pub fn isInitialized() bool {
    return state.runtime.initialized;
}

/// Check if Python is finalizing
pub fn isFinalizing() bool {
    return state.runtime.finalizing != null;
}

/// Get the runtime state
pub fn getRuntime() *state.RuntimeState {
    return &state.runtime;
}

/// Get the current thread state
pub fn getThreadState() ?*ThreadState {
    return init._tstate;
}

/// Get the main interpreter
pub fn getMainInterpreter() ?*InterpreterState {
    if (state.runtime.main_tstate) |tstate| {
        return tstate.interp;
    }
    return null;
}

/// Register an exit function
pub fn atExit(func: types.ExitFunc) i32 {
    if (state.runtime.nexitfuncs >= state.runtime.exitfuncs.len) {
        return -1;
    }
    state.runtime.exitfuncs[state.runtime.nexitfuncs] = func;
    state.runtime.nexitfuncs += 1;
    return 0;
}

/// Create a new interpreter
pub fn newInterpreter() ?*ThreadState {
    if (!state.runtime.initialized) {
        return null;
    }

    var interp = allocator_helper.fast_allocator.create(InterpreterState) catch {
        return null;
    };
    interp.* = .{};
    interp.id = state.runtime.next_interp_id;
    state.runtime.next_interp_id += 1;

    if (getMainInterpreter()) |main_interp| {
        interp.config = main_interp.config;
    }

    var tstate = allocator_helper.fast_allocator.create(ThreadState) catch {
        allocator_helper.fast_allocator.destroy(interp);
        return null;
    };
    tstate.* = .{};
    tstate.interp = interp;
    tstate.thread_id = @intCast(std.Thread.getCurrentId());

    interp.threads_head = tstate;
    interp.threads_count = 1;
    interp._ready = true;

    return tstate;
}

/// End an interpreter
pub fn endInterpreter(tstate: *ThreadState) void {
    if (tstate.interp) |interp| {
        interp.finalizing = true;
        allocator_helper.fast_allocator.destroy(interp);
    }
    allocator_helper.fast_allocator.destroy(tstate);
}

/// Create a new thread state
pub fn threadStateNew(interp: *InterpreterState) ?*ThreadState {
    var tstate = allocator_helper.fast_allocator.create(ThreadState) catch {
        return null;
    };
    tstate.* = .{};
    tstate.interp = interp;
    tstate.thread_id = @intCast(std.Thread.getCurrentId());

    tstate.next = interp.threads_head;
    if (interp.threads_head) |head| {
        head.prev = tstate;
    }
    interp.threads_head = tstate;
    interp.threads_count += 1;

    return tstate;
}

/// Delete a thread state
pub fn threadStateDelete(tstate: *ThreadState) void {
    if (tstate.interp) |interp| {
        if (tstate.prev) |prev| {
            prev.next = tstate.next;
        } else {
            interp.threads_head = tstate.next;
        }
        if (tstate.next) |next| {
            next.prev = tstate.prev;
        }
        interp.threads_count -= 1;
    }
    allocator_helper.fast_allocator.destroy(tstate);
}

/// Swap thread state
pub fn threadStateSwap(new_tstate: ?*ThreadState) ?*ThreadState {
    const old = init._tstate;
    init._tstate = new_tstate;
    return old;
}

/// GIL state result
pub const GILStateResult = enum {
    locked,
    unlocked,
};

/// Ensure GIL is held
pub fn gilStateEnsure() GILStateResult {
    const tstate = init._tstate;
    if (tstate != null) {
        tstate.?.gilstate_counter += 1;
        return .locked;
    }

    if (getMainInterpreter()) |interp| {
        const new_tstate = threadStateNew(interp);
        if (new_tstate) |ts| {
            ts.gilstate_counter = 1;
            init._tstate = ts;
            return .unlocked;
        }
    }
    return .unlocked;
}

/// Release GIL if we acquired it
pub fn gilStateRelease(gil_state: GILStateResult) void {
    const tstate = init._tstate orelse return;

    tstate.gilstate_counter -= 1;
    if (tstate.gilstate_counter == 0 and gil_state == .unlocked) {
        threadStateDelete(tstate);
        init._tstate = null;
    }
}

/// Check if current thread holds GIL
pub fn gilStateCheck() bool {
    return init._tstate != null;
}
