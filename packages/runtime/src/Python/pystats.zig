/// pystats - Python Statistics
/// Mirrors cpython/Python/pystats.c
///
/// This module provides runtime statistics collection:
/// - Opcode execution counts
/// - Object allocation statistics
/// - Call statistics
/// - Type specialization stats
/// - GC statistics

// Re-export constants
pub const MAX_OPCODES = @import("pystats/constants.zig").MAX_OPCODES;
pub const MAX_CALL_DEPTH = @import("pystats/constants.zig").MAX_CALL_DEPTH;
pub const SPECIALIZATION_ENTRIES = @import("pystats/constants.zig").SPECIALIZATION_ENTRIES;

// Re-export types
pub const OpcodeStats = @import("pystats/opcode_stats.zig").OpcodeStats;
pub const AllocStats = @import("pystats/alloc_stats.zig").AllocStats;
pub const CallStats = @import("pystats/call_stats.zig").CallStats;
pub const CallType = @import("pystats/call_stats.zig").CallType;
pub const SpecializationStats = @import("pystats/spec_stats.zig").SpecializationStats;
pub const GCStats = @import("pystats/gc_stats.zig").GCStats;
pub const PyStats = @import("pystats/global.zig").PyStats;
pub const StatsSummary = @import("pystats/reporting.zig").StatsSummary;

// Re-export global functions
pub const getStats = @import("pystats/global.zig").getStats;
pub const enable = @import("pystats/global.zig").enable;
pub const disable = @import("pystats/global.zig").disable;
pub const isEnabled = @import("pystats/global.zig").isEnabled;
pub const reset = @import("pystats/global.zig").reset;
pub const init = @import("pystats/global.zig").init;

// Re-export recording functions
pub const recordOpcode = @import("pystats/global.zig").recordOpcode;
pub const recordOpcodePair = @import("pystats/global.zig").recordOpcodePair;
pub const recordAlloc = @import("pystats/global.zig").recordAlloc;
pub const recordFree = @import("pystats/global.zig").recordFree;
pub const recordCall = @import("pystats/global.zig").recordCall;
pub const recordSpecHit = @import("pystats/global.zig").recordSpecHit;
pub const recordSpecMiss = @import("pystats/global.zig").recordSpecMiss;
pub const recordGC = @import("pystats/global.zig").recordGC;

// Re-export reporting functions
pub const getSummary = @import("pystats/reporting.zig").getSummary;

// Re-export tests
test {
    _ = @import("pystats/tests.zig");
}
