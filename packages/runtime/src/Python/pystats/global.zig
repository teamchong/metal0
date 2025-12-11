/// Global statistics container and state
/// Mirrors cpython/Python/pystats.c

const std = @import("std");
const constants = @import("constants.zig");
const OpcodeStats = @import("opcode_stats.zig").OpcodeStats;
const AllocStats = @import("alloc_stats.zig").AllocStats;
const CallStats = @import("call_stats.zig").CallStats;
const CallType = @import("call_stats.zig").CallType;
const SpecializationStats = @import("spec_stats.zig").SpecializationStats;
const GCStats = @import("gc_stats.zig").GCStats;

/// Global statistics container
pub const PyStats = struct {
    /// Opcode statistics
    opcode_stats: [constants.MAX_OPCODES]OpcodeStats = undefined,
    /// Allocation statistics
    alloc_stats: AllocStats = .{},
    /// Call statistics
    call_stats: CallStats = undefined,
    /// Specialization statistics per opcode
    spec_stats: [constants.MAX_OPCODES]SpecializationStats = undefined,
    /// GC statistics
    gc_stats: GCStats = undefined,
    /// Whether stats collection is enabled
    enabled: bool = false,

    const Self = @This();

    pub fn init() Self {
        var self = Self{
            .call_stats = CallStats.init(),
            .gc_stats = GCStats.init(),
        };
        for (&self.opcode_stats) |*s| {
            s.* = OpcodeStats.init();
        }
        for (&self.spec_stats) |*s| {
            s.* = .{};
        }
        return self;
    }

    /// Enable statistics collection
    pub fn enable(self: *Self) void {
        self.enabled = true;
    }

    /// Disable statistics collection
    pub fn disable(self: *Self) void {
        self.enabled = false;
    }

    /// Reset all statistics
    pub fn reset(self: *Self) void {
        self.* = Self.init();
    }
};

// Global state
var g_stats: PyStats = PyStats.init();

/// Get global statistics
pub fn getStats() *PyStats {
    return &g_stats;
}

/// Enable statistics collection
pub fn enable() void {
    g_stats.enable();
}

/// Disable statistics collection
pub fn disable() void {
    g_stats.disable();
}

/// Check if statistics are enabled
pub fn isEnabled() bool {
    return g_stats.enabled;
}

/// Reset all statistics
pub fn reset() void {
    g_stats.reset();
}

/// Record opcode execution
pub fn recordOpcode(opcode: u8, cycles: u64) void {
    if (!g_stats.enabled) return;
    g_stats.opcode_stats[opcode].record(cycles);
}

/// Record opcode pair
pub fn recordOpcodePair(opcode: u8, next_opcode: u8) void {
    if (!g_stats.enabled) return;
    g_stats.opcode_stats[opcode].recordPair(next_opcode);
}

/// Record allocation
pub fn recordAlloc(size: usize) void {
    if (!g_stats.enabled) return;
    g_stats.alloc_stats.recordAlloc(size);
}

/// Record free
pub fn recordFree(size: usize) void {
    if (!g_stats.enabled) return;
    g_stats.alloc_stats.recordFree(size);
}

/// Record call
pub fn recordCall(call_type: CallType, depth: u32) void {
    if (!g_stats.enabled) return;
    g_stats.call_stats.recordCall(call_type, depth);
}

/// Record specialization hit
pub fn recordSpecHit(opcode: u8) void {
    if (!g_stats.enabled) return;
    g_stats.spec_stats[opcode].recordHit();
}

/// Record specialization miss
pub fn recordSpecMiss(opcode: u8) void {
    if (!g_stats.enabled) return;
    g_stats.spec_stats[opcode].recordMiss();
}

/// Record GC collection
pub fn recordGC(generation: u8, collected: u64, uncollectable: u64, time_ns: u64) void {
    if (!g_stats.enabled) return;
    g_stats.gc_stats.recordCollection(generation, collected, uncollectable, time_ns);
}

pub fn init() void {}
