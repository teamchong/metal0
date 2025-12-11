/// interp_state - Interpreter State Operations
/// Interpreter state creation, deletion, and management.

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const interpreter = @import("interpreter.zig");
const thread_state = @import("thread_state.zig");
const global = @import("global.zig");

pub const InterpreterState = interpreter.InterpreterState;

// ============================================================================
// Interpreter State Functions
// ============================================================================

/// Create a new interpreter state
/// Mirrors: PyInterpreterState_New()
pub fn interpreterStateNew() ?*InterpreterState {
    const interp = allocator_helper.fast_allocator.create(InterpreterState) catch {
        return null;
    };
    interp.* = .{};

    // Assign ID
    interp.id = global.next_interp_id;
    global.next_interp_id += 1;

    // Add to global list
    interp.next = global.interpreters.head;
    if (global.interpreters.head) |head| {
        head.prev = interp;
    }
    global.interpreters.head = interp;
    global.interpreters.count += 1;

    // First interpreter is main
    if (global.interpreters.main == null) {
        global.interpreters.main = interp;
        interp._whence = .runtime;
    }

    return interp;
}

/// Delete an interpreter state
/// Mirrors: PyInterpreterState_Delete()
pub fn interpreterStateDelete(interp: *InterpreterState) void {
    interpreterStateClear(interp);

    // Remove from global list
    if (interp.prev) |prev| {
        prev.next = interp.next;
    } else {
        global.interpreters.head = interp.next;
    }
    if (interp.next) |next| {
        next.prev = interp.prev;
    }
    global.interpreters.count -= 1;

    if (global.interpreters.main == interp) {
        global.interpreters.main = null;
    }

    allocator_helper.fast_allocator.destroy(interp);
}

/// Clear interpreter state
/// Mirrors: PyInterpreterState_Clear()
pub fn interpreterStateClear(interp: *InterpreterState) void {
    interp.finalizing = true;

    // Delete all thread states
    while (interp.threads.head) |tstate| {
        thread_state.threadStateDelete(tstate);
    }

    interp.modules = null;
    interp.builtins = null;
}

/// Get interpreter ID
/// Mirrors: PyInterpreterState_GetID()
pub fn interpreterStateGetID(interp: *InterpreterState) i64 {
    return interp.id;
}

/// Get main interpreter
/// Mirrors: PyInterpreterState_Main()
pub fn interpreterStateMain() ?*InterpreterState {
    return global.interpreters.main;
}

/// Get head interpreter
/// Mirrors: PyInterpreterState_Head()
pub fn interpreterStateHead() ?*InterpreterState {
    return global.interpreters.head;
}

/// Get next interpreter
/// Mirrors: PyInterpreterState_Next()
pub fn interpreterStateNext(interp: *InterpreterState) ?*InterpreterState {
    return interp.next;
}

/// Get current interpreter
pub fn interpreterStateGet() ?*InterpreterState {
    return global._tss_interp;
}

/// Check if interpreter is main
pub fn isMainInterpreter(interp: *const InterpreterState) bool {
    return interp == global.interpreters.main;
}

/// Get number of interpreters
pub fn getInterpreterCount() u64 {
    return global.interpreters.count;
}

/// Get thread count for an interpreter
pub fn getThreadCount(interp: *InterpreterState) u64 {
    return interp.threads.count;
}

/// Enumerate all thread states in an interpreter
pub fn enumerateThreadStates(interp: *InterpreterState, callback: *const fn (*thread_state.ThreadState) void) void {
    var tstate = interp.threads.head;
    while (tstate) |ts| {
        callback(ts);
        tstate = ts.next;
    }
}
