/// thread_state - Thread State Operations
/// Thread state creation, deletion, and management.

const std = @import("std");
const types = @import("types.zig");
const interpreter = @import("interpreter.zig");
const global = @import("global.zig");

pub const ThreadState = types.ThreadState;
pub const ThreadStateWhence = types.ThreadStateWhence;
pub const InterpreterState = interpreter.InterpreterState;

// ============================================================================
// Thread State Functions
// ============================================================================

/// Create a new thread state
/// Mirrors: PyThreadState_New()
pub fn threadStateNew(interp: *InterpreterState) ?*ThreadState {
    return threadStateNewWithWhence(interp, .interp);
}

/// Create a new thread state with origin
pub fn threadStateNewWithWhence(interp: *InterpreterState, whence: ThreadStateWhence) ?*ThreadState {
    const tstate = interp.allocator.create(ThreadState) catch {
        return null;
    };
    tstate.* = .{};
    tstate.interp = interp;
    tstate._whence = whence;
    tstate.recursion_limit = interp.ceval.recursion_limit;
    tstate._status.initialized = true;

    // Assign ID
    tstate.id = interp.threads.next_id;
    interp.threads.next_id += 1;

    // Add to interpreter's thread list
    tstate.next = interp.threads.head;
    if (interp.threads.head) |head| {
        head.prev = tstate;
    }
    interp.threads.head = tstate;
    interp.threads.count += 1;

    return tstate;
}

/// Delete a thread state
/// Mirrors: PyThreadState_Delete()
pub fn threadStateDelete(tstate: *ThreadState) void {
    threadStateClear(tstate);

    if (tstate.interp) |interp| {
        // Remove from interpreter's thread list
        if (tstate.prev) |prev| {
            prev.next = tstate.next;
        } else {
            interp.threads.head = tstate.next;
        }
        if (tstate.next) |next| {
            next.prev = tstate.prev;
        }
        interp.threads.count -= 1;
    }

    // Deallocate
    const allocator = tstate.allocator;
    allocator.destroy(tstate);
}

/// Clear thread state
/// Mirrors: PyThreadState_Clear()
pub fn threadStateClear(tstate: *ThreadState) void {
    tstate._status.cleared = true;
    tstate.current_frame = null;
    tstate.curexc_type = null;
    tstate.curexc_value = null;
    tstate.curexc_traceback = null;
    tstate.c_profilefunc = null;
    tstate.c_tracefunc = null;
    tstate.c_profileobj = null;
    tstate.c_traceobj = null;
    tstate.async_gen_firstiter = null;
    tstate.async_gen_finalizer = null;
    tstate.context = null;
}

/// Bind thread state to current thread
/// Mirrors: _PyThreadState_Bind()
pub fn threadStateBind(tstate: *ThreadState) void {
    tstate.thread_id = std.Thread.getCurrentId();
    tstate._status.bound = true;
}

/// Get current thread state
/// Mirrors: PyThreadState_Get()
pub fn threadStateGet() ?*ThreadState {
    return global._tss_tstate;
}

/// Swap thread states
/// Mirrors: PyThreadState_Swap()
pub fn threadStateSwap(new_tstate: ?*ThreadState) ?*ThreadState {
    const old = global._tss_tstate;

    if (new_tstate) |ts| {
        global._tss_tstate = ts;
        global._tss_interp = ts.interp;
        ts._status.active = true;
    } else {
        if (old) |o| {
            o._status.active = false;
        }
        global._tss_tstate = null;
        global._tss_interp = null;
    }

    return old;
}

/// Get thread state dictionary (per-thread storage)
/// Mirrors: PyThreadState_GetDict()
pub fn threadStateGetDict(tstate: *ThreadState) ?*anyopaque {
    return tstate.dict;
}

/// Set async exception on a thread
/// Mirrors: PyThreadState_SetAsyncExc()
pub fn threadStateSetAsyncExc(id: u64, exc: ?*anyopaque) i32 {
    const interp = global.interpreters.main orelse return 0;
    var tstate = interp.threads.head;
    var count: i32 = 0;

    while (tstate) |ts| : (tstate = ts.next) {
        if (ts.thread_id == id) {
            if (exc == null) {
                ts.curexc_type = null;
                ts.curexc_value = null;
                ts.curexc_traceback = null;
            } else {
                ts.curexc_type = exc;
            }
            count += 1;
        }
    }

    return count;
}
