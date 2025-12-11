/// Opcode execution statistics
/// Mirrors cpython/Python/pystats.c

const std = @import("std");
const Atomic = std.atomic.Value;
const constants = @import("constants.zig");

/// Statistics for a single opcode
pub const OpcodeStats = struct {
    /// Execution count
    count: Atomic(u64) = Atomic(u64).init(0),
    /// Total cycles spent
    cycles: Atomic(u64) = Atomic(u64).init(0),
    /// Pair execution (this opcode followed by...)
    pair_counts: [constants.MAX_OPCODES]Atomic(u64) = undefined,

    const Self = @This();

    pub fn init() Self {
        var self = Self{};
        for (&self.pair_counts) |*p| {
            p.* = Atomic(u64).init(0);
        }
        return self;
    }

    pub fn record(self: *Self, cycles_spent: u64) void {
        _ = self.count.fetchAdd(1, .monotonic);
        _ = self.cycles.fetchAdd(cycles_spent, .monotonic);
    }

    pub fn recordPair(self: *Self, next_opcode: u8) void {
        _ = self.pair_counts[next_opcode].fetchAdd(1, .monotonic);
    }

    pub fn getCount(self: *const Self) u64 {
        return self.count.load(.monotonic);
    }

    pub fn getCycles(self: *const Self) u64 {
        return self.cycles.load(.monotonic);
    }
};
