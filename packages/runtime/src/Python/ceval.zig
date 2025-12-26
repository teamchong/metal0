/// ceval - Central Execution Loop and Interpreter Control
/// Mirrors cpython/Python/ceval.c
///
/// This module provides:
/// - Bytecode execution machinery (_PyEval_EvalFrameDefault equivalent)
/// - Pending calls mechanism (Py_AddPendingCall, Py_MakePendingCalls)
/// - Tracing and profiling hooks
/// - Thread switching and GIL management
/// - Recursion limit checking
/// - Binary operations tables
/// - Frame evaluation control

const std = @import("std");
const runtime = @import("../runtime.zig");

// ============================================================================
// Submodule imports
// ============================================================================
const pending_calls_mod = @import("ceval/pending_calls.zig");
const state_mod = @import("ceval/state.zig");
const tracing_mod = @import("ceval/tracing.zig");
const operations_mod = @import("ceval/operations.zig");
const recursion_mod = @import("ceval/recursion.zig");
const thread_switch_mod = @import("ceval/thread_switch.zig");
const frame_eval_mod = @import("ceval/frame_eval.zig");
const async_gen_mod = @import("ceval/async_gen.zig");
const signals_mod = @import("ceval/signals.zig");
const pattern_match_mod = @import("ceval/pattern_match.zig");
const unpack_mod = @import("ceval/unpack.zig");

// ============================================================================
// Re-exports from pending_calls.zig
// ============================================================================
pub const PENDING_CALLS_ARRAY_SIZE = pending_calls_mod.PENDING_CALLS_ARRAY_SIZE;
pub const MAX_PENDING_CALLS_LOOP = pending_calls_mod.MAX_PENDING_CALLS_LOOP;
pub const PendingCallFunc = pending_calls_mod.PendingCallFunc;
pub const AddPendingResult = pending_calls_mod.AddPendingResult;
pub const PendingCalls = pending_calls_mod.PendingCalls;
pub const addPendingCall = pending_calls_mod.addPendingCall;
pub const makePendingCalls = pending_calls_mod.makePendingCalls;

// ============================================================================
// Re-exports from state.zig
// ============================================================================
pub const EVAL_BREAKER_GIL_DROP = state_mod.EVAL_BREAKER_GIL_DROP;
pub const EVAL_BREAKER_PENDING_CALLS = state_mod.EVAL_BREAKER_PENDING_CALLS;
pub const EVAL_BREAKER_SIGNALS = state_mod.EVAL_BREAKER_SIGNALS;
pub const EVAL_BREAKER_TRACING = state_mod.EVAL_BREAKER_TRACING;
pub const EVAL_BREAKER_GC = state_mod.EVAL_BREAKER_GC;
pub const EVAL_BREAKER_STOP_WORLD = state_mod.EVAL_BREAKER_STOP_WORLD;
pub const CEvalState = state_mod.CEvalState;

// ============================================================================
// Re-exports from tracing.zig
// ============================================================================
pub const TraceEvent = tracing_mod.TraceEvent;
pub const TraceFunc = tracing_mod.TraceFunc;
pub const setTrace = tracing_mod.setTrace;
pub const getTrace = tracing_mod.getTrace;
pub const setProfile = tracing_mod.setProfile;
pub const getProfile = tracing_mod.getProfile;
pub const callTrace = tracing_mod.callTrace;
pub const callProfile = tracing_mod.callProfile;
pub const setTraceAllThreads = tracing_mod.setTraceAllThreads;
pub const setProfileAllThreads = tracing_mod.setProfileAllThreads;

// ============================================================================
// Re-exports from operations.zig
// ============================================================================
pub const BinaryOp = operations_mod.BinaryOp;
pub const CompareOp = operations_mod.CompareOp;
pub const ConversionFunc = operations_mod.ConversionFunc;

// ============================================================================
// Re-exports from recursion.zig
// ============================================================================
pub const enterRecursiveCall = recursion_mod.enterRecursiveCall;
pub const leaveRecursiveCall = recursion_mod.leaveRecursiveCall;
pub const getRecursionDepth = recursion_mod.getRecursionDepth;
pub const setRecursionLimit = recursion_mod.setRecursionLimit;
pub const getRecursionLimit = recursion_mod.getRecursionLimit;

// ============================================================================
// Re-exports from thread_switch.zig
// ============================================================================
pub const setCheckInterval = thread_switch_mod.setCheckInterval;
pub const getCheckInterval = thread_switch_mod.getCheckInterval;
pub const checkTicker = thread_switch_mod.checkTicker;

// ============================================================================
// Re-exports from frame_eval.zig
// ============================================================================
pub const FrameEvalFunction = frame_eval_mod.FrameEvalFunction;
pub const setEvalFrameFunc = frame_eval_mod.setEvalFrameFunc;
pub const getEvalFrameFunc = frame_eval_mod.getEvalFrameFunc;
pub const getFrame = frame_eval_mod.getFrame;
pub const setFrame = frame_eval_mod.setFrame;
pub const getBuiltins = frame_eval_mod.getBuiltins;
pub const getGlobals = frame_eval_mod.getGlobals;
pub const getFrameLocals = frame_eval_mod.getFrameLocals;

// ============================================================================
// Re-exports from async_gen.zig
// ============================================================================
pub const setCoroutineOriginTrackingDepth = async_gen_mod.setCoroutineOriginTrackingDepth;
pub const getCoroutineOriginTrackingDepth = async_gen_mod.getCoroutineOriginTrackingDepth;
pub const setAsyncGenFirstiter = async_gen_mod.setAsyncGenFirstiter;
pub const getAsyncGenFirstiter = async_gen_mod.getAsyncGenFirstiter;
pub const setAsyncGenFinalizer = async_gen_mod.setAsyncGenFinalizer;
pub const getAsyncGenFinalizer = async_gen_mod.getAsyncGenFinalizer;

// ============================================================================
// Re-exports from signals.zig
// ============================================================================
pub const tripSignal = signals_mod.tripSignal;
pub const checkAndClearSignal = signals_mod.checkAndClearSignal;
pub const stopTheWorld = signals_mod.stopTheWorld;
pub const startTheWorld = signals_mod.startTheWorld;
pub const isWorldStopped = signals_mod.isWorldStopped;

// ============================================================================
// Re-exports from pattern_match.zig
// ============================================================================
pub const exceptionGroupMatch = pattern_match_mod.exceptionGroupMatch;
pub const matchKeys = pattern_match_mod.matchKeys;
pub const matchClass = pattern_match_mod.matchClass;

// ============================================================================
// Re-exports from unpack.zig
// ============================================================================
pub const unpackIterable = unpack_mod.unpackIterable;

// ============================================================================
// Eval Cache Integration
// ============================================================================
const eval_cache = @import("eval_cache.zig");

pub const evalCached = eval_cache.evalCached;
pub const evalWithScope = eval_cache.evalWithScope;
pub const initCache = eval_cache.initCache;
pub const clearCache = eval_cache.clearCache;
pub const getCacheStats = eval_cache.getCacheStats;
pub const deinitCache = eval_cache.deinitCache;
pub const eval = evalCached;

// ============================================================================
// Bytecode Execution (High-Level Stubs)
// ============================================================================

/// Evaluate a code object (AOT stub)
pub fn evalCode(
    allocator: std.mem.Allocator,
    code: anytype,
    globals: anytype,
    locals: anytype,
) !?*anyopaque {
    _ = allocator;
    _ = code;
    _ = globals;
    _ = locals;
    return null;
}

/// Evaluate with keyword arguments (AOT stub)
pub fn evalCodeEx(
    allocator: std.mem.Allocator,
    code: anytype,
    globals: anytype,
    locals: anytype,
    args: anytype,
    kwargs: anytype,
    defaults: anytype,
    kwdefaults: anytype,
    closure: anytype,
) !?*anyopaque {
    _ = allocator;
    _ = code;
    _ = globals;
    _ = locals;
    _ = args;
    _ = kwargs;
    _ = defaults;
    _ = kwdefaults;
    _ = closure;
    return null;
}

// ============================================================================
// Module Init/Fini
// ============================================================================

pub fn init() void {
    initCache() catch {};
}

pub fn fini() void {
    deinitCache();
}
