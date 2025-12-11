/// pystate - Python Thread and Interpreter State
/// Mirrors cpython/Python/pystate.c
///
/// Manages interpreter and thread state:
/// - Interpreter state creation/deletion
/// - Thread state creation/deletion/binding
/// - Current thread state lookup
/// - GIL state management
/// - Cross-interpreter operations

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const builtin = @import("builtin");

// Re-export the core types from pylifecycle for consistency
pub const lifecycle = @import("pylifecycle.zig");

// Re-export submodules
pub const types = @import("pystate/types.zig");
pub const interpreter = @import("pystate/interpreter.zig");
pub const thread_state = @import("pystate/thread_state.zig");
pub const interp_state = @import("pystate/interp_state.zig");
pub const global = @import("pystate/global.zig");
pub const gilstate = @import("pystate/gilstate.zig");

// Re-export types
pub const ThreadStateStatus = types.ThreadStateStatus;
pub const ThreadState = types.ThreadState;
pub const ExceptionInfo = types.ExceptionInfo;
pub const ProfileFunc = types.ProfileFunc;
pub const TraceFunc = types.TraceFunc;
pub const ThreadStateWhence = types.ThreadStateWhence;
pub const ThreadStateList = types.ThreadStateList;
pub const ImportState = types.ImportState;
pub const CodecState = types.CodecState;
pub const GCState = types.GCState;
pub const LongState = types.LongState;
pub const DictState = types.DictState;
pub const CEvalState = types.CEvalState;
pub const InterpreterWhence = types.InterpreterWhence;
pub const FeatureFlags = types.FeatureFlags;
pub const GILState = types.GILState;
pub const InterpreterState = interpreter.InterpreterState;

// Re-export thread state functions
pub const threadStateNew = thread_state.threadStateNew;
pub const threadStateDelete = thread_state.threadStateDelete;
pub const threadStateClear = thread_state.threadStateClear;
pub const threadStateBind = thread_state.threadStateBind;
pub const threadStateGet = thread_state.threadStateGet;
pub const threadStateSwap = thread_state.threadStateSwap;
pub const threadStateGetDict = thread_state.threadStateGetDict;
pub const threadStateSetAsyncExc = thread_state.threadStateSetAsyncExc;

// Re-export interpreter state functions
pub const interpreterStateNew = interp_state.interpreterStateNew;
pub const interpreterStateDelete = interp_state.interpreterStateDelete;
pub const interpreterStateClear = interp_state.interpreterStateClear;
pub const interpreterStateGetID = interp_state.interpreterStateGetID;
pub const interpreterStateMain = interp_state.interpreterStateMain;
pub const interpreterStateHead = interp_state.interpreterStateHead;
pub const interpreterStateNext = interp_state.interpreterStateNext;
pub const interpreterStateGet = interp_state.interpreterStateGet;
pub const isMainInterpreter = interp_state.isMainInterpreter;
pub const getInterpreterCount = interp_state.getInterpreterCount;
pub const getThreadCount = interp_state.getThreadCount;
pub const enumerateThreadStates = interp_state.enumerateThreadStates;

// Re-export GIL state functions
pub const gilStateEnsure = gilstate.gilStateEnsure;
pub const gilStateRelease = gilstate.gilStateRelease;
pub const gilStateCheck = gilstate.gilStateCheck;
pub const gilStateGetThisThreadState = gilstate.gilStateGetThisThreadState;

// ============================================================================
// Initialization
// ============================================================================

/// Initialize the pystate module
pub fn init() void {
    global.interpreters = .{};
    global.next_interp_id = 0;
}

/// Finalize the pystate module
pub fn fini() void {
    while (global.interpreters.head) |interp| {
        interpreterStateDelete(interp);
    }
}

// ============================================================================
// Tests
// ============================================================================

test "interpreter state new/delete" {
    init();
    defer fini();

    const interp = interpreterStateNew();
    try std.testing.expect(interp != null);
    try std.testing.expectEqual(@as(i64, 0), interp.?.id);
    try std.testing.expect(isMainInterpreter(interp.?));

    interpreterStateDelete(interp.?);
    try std.testing.expectEqual(@as(u64, 0), global.interpreters.count);
}

test "thread state new/delete" {
    init();
    defer fini();

    const interp = interpreterStateNew().?;
    defer interpreterStateDelete(interp);

    const tstate = threadStateNew(interp);
    try std.testing.expect(tstate != null);
    try std.testing.expectEqual(@as(u64, 0), tstate.?.id);
    try std.testing.expectEqual(@as(u64, 1), interp.threads.count);

    threadStateDelete(tstate.?);
    try std.testing.expectEqual(@as(u64, 0), interp.threads.count);
}

test "thread state swap" {
    init();
    defer fini();

    const interp = interpreterStateNew().?;
    defer interpreterStateDelete(interp);

    const tstate = threadStateNew(interp).?;
    defer threadStateDelete(tstate);

    try std.testing.expect(threadStateGet() == null);

    const old = threadStateSwap(tstate);
    try std.testing.expect(old == null);
    try std.testing.expectEqual(tstate, threadStateGet().?);

    _ = threadStateSwap(null);
    try std.testing.expect(threadStateGet() == null);
}

test "gilstate" {
    init();
    defer fini();

    const interp = interpreterStateNew().?;
    defer interpreterStateDelete(interp);

    try std.testing.expect(!gilStateCheck());

    const state = gilStateEnsure();
    try std.testing.expect(gilStateCheck());

    gilStateRelease(state);
}

test "interpreter iteration" {
    init();
    defer fini();

    const interp1 = interpreterStateNew().?;
    const interp2 = interpreterStateNew().?;
    defer interpreterStateDelete(interp1);
    defer interpreterStateDelete(interp2);

    try std.testing.expectEqual(@as(u64, 2), getInterpreterCount());

    var count: u64 = 0;
    var current = interpreterStateHead();
    while (current) |i| {
        count += 1;
        current = interpreterStateNext(i);
    }
    try std.testing.expectEqual(@as(u64, 2), count);
}

test {
    _ = types;
    _ = interpreter;
    _ = thread_state;
    _ = interp_state;
    _ = global;
    _ = gilstate;
}
