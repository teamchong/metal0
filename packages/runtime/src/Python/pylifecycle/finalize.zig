/// pylifecycle finalization functions
const std = @import("std");
const state = @import("state.zig");
const init = @import("init.zig");

/// Finalize Python runtime
pub fn finalize() void {
    _ = finalizeEx();
}

/// Finalize Python runtime with status return
pub fn finalizeEx() i32 {
    if (!state.runtime.initialized) {
        return 0;
    }

    const tstate = state.runtime.main_tstate orelse return -1;

    state.runtime.finalizing = tstate;

    waitForThreadShutdown();
    callExitFuncs();
    clearAuditHooks();

    if (tstate.interp) |interp| {
        interp.finalizing = true;
    }

    init._tstate = null;

    state.runtime.initialized = false;
    state.runtime.core_initialized = false;
    state.runtime.finalizing = null;

    return 0;
}

/// Wait for non-daemon threads to finish
fn waitForThreadShutdown() void {
    const threading = @import("../../Lib/threading.zig");

    var wait_count: u32 = 0;
    while (wait_count < 10) : (wait_count += 1) {
        const active = threading.activeCount();
        if (active <= 1) break;
        std.time.sleep(10 * std.time.ns_per_ms);
    }
}

/// Call registered exit functions
fn callExitFuncs() void {
    var i = state.runtime.nexitfuncs;
    while (i > 0) {
        i -= 1;
        if (state.runtime.exitfuncs[i]) |func| {
            func();
            state.runtime.exitfuncs[i] = null;
        }
    }
    state.runtime.nexitfuncs = 0;
}

/// Clear audit hooks
fn clearAuditHooks() void {
    state.runtime.audit_hooks.head = null;
    state.runtime.audit_hooks.count = 0;
}
