/// pylifecycle - Python Interpreter Lifecycle Management
/// Mirrors cpython/Python/pylifecycle.c
///
/// Manages the interpreter lifecycle:
/// - Initialization (Py_Initialize, Py_InitializeEx)
/// - Finalization (Py_Finalize, Py_FinalizeEx)
/// - Runtime state management
/// - Thread state lifecycle
/// - Exit functions (atexit handlers)

const std = @import("std");

// Submodule imports
const types_mod = @import("pylifecycle/types.zig");
const state_mod = @import("pylifecycle/state.zig");
const init_mod = @import("pylifecycle/init.zig");
const finalize_mod = @import("pylifecycle/finalize.zig");
const locale_mod = @import("pylifecycle/locale.zig");
const thread_state_mod = @import("pylifecycle/thread_state.zig");
const audit_mod = @import("pylifecycle/audit.zig");

// ============================================================================
// Re-exports from types.zig
// ============================================================================
pub const StatusKind = types_mod.StatusKind;
pub const Status = types_mod.Status;
pub const PreConfig = types_mod.PreConfig;
pub const Config = types_mod.Config;
pub const ExitFunc = types_mod.ExitFunc;
pub const OpenCodeHook = types_mod.OpenCodeHook;
pub const AuditHook = types_mod.AuditHook;
pub const AuditHookList = types_mod.AuditHookList;
pub const AtForkHandlers = types_mod.AtForkHandlers;
pub const GILState = types_mod.GILState;

// ============================================================================
// Re-exports from state.zig
// ============================================================================
pub const RuntimeState = state_mod.RuntimeState;
pub const ThreadState = state_mod.ThreadState;
pub const InterpreterState = state_mod.InterpreterState;

// ============================================================================
// Re-exports from init.zig
// ============================================================================
pub const preInitialize = init_mod.preInitialize;
pub const preInitializeFromConfig = init_mod.preInitializeFromConfig;
pub const initialize = init_mod.initialize;
pub const initializeEx = init_mod.initializeEx;
pub const initializeFromConfig = init_mod.initializeFromConfig;
pub const exitStatusException = init_mod.exitStatusException;

// ============================================================================
// Re-exports from finalize.zig
// ============================================================================
pub const finalize = finalize_mod.finalize;
pub const finalizeEx = finalize_mod.finalizeEx;

// ============================================================================
// Re-exports from locale.zig
// ============================================================================
pub const isLegacyLocaleDetected = locale_mod.isLegacyLocaleDetected;

// ============================================================================
// Re-exports from thread_state.zig
// ============================================================================
pub const isInitialized = thread_state_mod.isInitialized;
pub const isFinalizing = thread_state_mod.isFinalizing;
pub const getRuntime = thread_state_mod.getRuntime;
pub const getThreadState = thread_state_mod.getThreadState;
pub const getMainInterpreter = thread_state_mod.getMainInterpreter;
pub const atExit = thread_state_mod.atExit;
pub const newInterpreter = thread_state_mod.newInterpreter;
pub const endInterpreter = thread_state_mod.endInterpreter;
pub const threadStateNew = thread_state_mod.threadStateNew;
pub const threadStateDelete = thread_state_mod.threadStateDelete;
pub const threadStateSwap = thread_state_mod.threadStateSwap;
pub const GILStateResult = thread_state_mod.GILStateResult;
pub const gilStateEnsure = thread_state_mod.gilStateEnsure;
pub const gilStateRelease = thread_state_mod.gilStateRelease;
pub const gilStateCheck = thread_state_mod.gilStateCheck;

// ============================================================================
// Re-exports from audit.zig
// ============================================================================
pub const addAuditHook = audit_mod.addAuditHook;
pub const audit = audit_mod.audit;

// ============================================================================
// Tests
// ============================================================================
test "status ok" {
    const status = Status.ok();
    try std.testing.expect(!status.isException());
    try std.testing.expect(!status.isExit());
    try std.testing.expect(!status.isError());
}

test "status error" {
    const status = Status.err("test error");
    try std.testing.expect(status.isException());
    try std.testing.expect(status.isError());
    try std.testing.expectEqualStrings("test error", status.err_msg.?);
}

test "preconfig defaults" {
    const config = PreConfig{};
    try std.testing.expect(config.parse_argv);
    try std.testing.expect(config.use_environment);
    try std.testing.expect(config.configure_locale);
}

test "config defaults" {
    const config = Config{};
    try std.testing.expect(config.site_import);
    try std.testing.expect(config.install_signal_handlers);
    try std.testing.expectEqual(@as(i32, 4300), config.int_max_str_digits);
}
