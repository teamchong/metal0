/// Function call statistics
/// Mirrors cpython/Python/pystats.c

const std = @import("std");
const Atomic = std.atomic.Value;
const constants = @import("constants.zig");

/// Call types
pub const CallType = enum {
    python,
    c,
    method,
    builtin,
    generator,
};

/// Statistics for function calls
pub const CallStats = struct {
    /// Total calls
    total_calls: Atomic(u64) = Atomic(u64).init(0),
    /// Calls to Python functions
    python_calls: Atomic(u64) = Atomic(u64).init(0),
    /// Calls to C functions
    c_calls: Atomic(u64) = Atomic(u64).init(0),
    /// Method calls
    method_calls: Atomic(u64) = Atomic(u64).init(0),
    /// Builtin calls
    builtin_calls: Atomic(u64) = Atomic(u64).init(0),
    /// Generator/coroutine calls
    generator_calls: Atomic(u64) = Atomic(u64).init(0),
    /// Maximum call depth seen
    max_depth: Atomic(u32) = Atomic(u32).init(0),
    /// Call depth histogram
    depth_histogram: [constants.MAX_CALL_DEPTH]Atomic(u64) = undefined,

    const Self = @This();

    pub fn init() Self {
        var self = Self{};
        for (&self.depth_histogram) |*h| {
            h.* = Atomic(u64).init(0);
        }
        return self;
    }

    pub fn recordCall(self: *Self, call_type: CallType, depth: u32) void {
        _ = self.total_calls.fetchAdd(1, .monotonic);

        switch (call_type) {
            .python => _ = self.python_calls.fetchAdd(1, .monotonic),
            .c => _ = self.c_calls.fetchAdd(1, .monotonic),
            .method => _ = self.method_calls.fetchAdd(1, .monotonic),
            .builtin => _ = self.builtin_calls.fetchAdd(1, .monotonic),
            .generator => _ = self.generator_calls.fetchAdd(1, .monotonic),
        }

        // Update max depth
        var max_d = self.max_depth.load(.monotonic);
        while (depth > max_d) {
            const result = self.max_depth.cmpxchgWeak(max_d, depth, .monotonic, .monotonic);
            if (result) |new_max| {
                max_d = new_max;
            } else {
                break;
            }
        }

        // Record in histogram
        if (depth < constants.MAX_CALL_DEPTH) {
            _ = self.depth_histogram[depth].fetchAdd(1, .monotonic);
        }
    }
};
