/// CEval State and Eval Breaker flags
/// Mirrors part of cpython/Python/ceval.c
const std = @import("std");
const pending_calls = @import("pending_calls.zig");
const PendingCalls = pending_calls.PendingCalls;

/// Eval breaker bit flags
pub const EVAL_BREAKER_GIL_DROP: usize = 1 << 0;
pub const EVAL_BREAKER_PENDING_CALLS: usize = 1 << 1;
pub const EVAL_BREAKER_SIGNALS: usize = 1 << 2;
pub const EVAL_BREAKER_TRACING: usize = 1 << 3;
pub const EVAL_BREAKER_GC: usize = 1 << 4;
pub const EVAL_BREAKER_STOP_WORLD: usize = 1 << 5;

/// CEval state for an interpreter
pub const CEvalState = struct {
    instrumentation_version: usize = 0,
    recursion_limit: i32 = 1000,
    own_gil: bool = true,
    pending: PendingCalls = PendingCalls.init(),
    check_interval: i32 = 100,
    switch_interval: u64 = 5000,
    gil_drop_request: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    eval_breaker: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    pub fn init() CEvalState {
        return .{};
    }

    pub fn setRecursionLimit(self: *CEvalState, limit: i32) !void {
        if (limit < 1) {
            return error.ValueError;
        }
        self.recursion_limit = limit;
    }

    pub fn getRecursionLimit(self: *CEvalState) i32 {
        return self.recursion_limit;
    }

    pub fn requestGilDrop(self: *CEvalState) void {
        self.gil_drop_request.store(true, .release);
        self.setEvalBreakerBit(EVAL_BREAKER_GIL_DROP);
    }

    pub fn clearGilDropRequest(self: *CEvalState) void {
        self.gil_drop_request.store(false, .release);
        self.clearEvalBreakerBit(EVAL_BREAKER_GIL_DROP);
    }

    pub fn setEvalBreakerBit(self: *CEvalState, bit: usize) void {
        _ = self.eval_breaker.fetchOr(bit, .acq_rel);
    }

    pub fn clearEvalBreakerBit(self: *CEvalState, bit: usize) void {
        _ = self.eval_breaker.fetchAnd(~bit, .acq_rel);
    }

    pub fn shouldBreak(self: *CEvalState) bool {
        return self.eval_breaker.load(.acquire) != 0;
    }
};
