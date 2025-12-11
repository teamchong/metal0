/// state - Specializer State and Statistics
/// Main specializer struct, statistics tracking, and module state.

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const opcodes = @import("opcodes.zig");
const functions = @import("functions.zig");

pub const SpecializedOp = opcodes.SpecializedOp;
pub const SpecializationContext = opcodes.SpecializationContext;

// ============================================================================
// Specialization Statistics
// ============================================================================

/// Statistics for specialization tracking
pub const SpecializationStats = struct {
    /// Number of successful specializations
    successes: u64 = 0,
    /// Number of deoptimizations
    deoptimizations: u64 = 0,
    /// Failure counts by reason
    failures: [32]u64 = [_]u64{0} ** 32,

    /// Record successful specialization
    pub fn recordSuccess(self: *SpecializationStats) void {
        self.successes += 1;
    }

    /// Record deoptimization
    pub fn recordDeopt(self: *SpecializationStats) void {
        self.deoptimizations += 1;
    }

    /// Record failure
    pub fn recordFailure(self: *SpecializationStats, reason: u8) void {
        if (reason < 32) {
            self.failures[reason] += 1;
        }
    }

    /// Get success rate
    pub fn getSuccessRate(self: *const SpecializationStats) f64 {
        const total = self.successes + self.deoptimizations;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.successes)) / @as(f64, @floatFromInt(total));
    }

    /// Reset statistics
    pub fn reset(self: *SpecializationStats) void {
        self.successes = 0;
        self.deoptimizations = 0;
        self.failures = [_]u64{0} ** 32;
    }
};

// ============================================================================
// Specializer
// ============================================================================

/// Main specializer
pub const Specializer = struct {
    const Self = @This();

    /// Memory allocator
    allocator: Allocator,
    /// Statistics
    stats: SpecializationStats = .{},
    /// Enable specialization
    enabled: bool = true,
    /// Minimum execution count before specializing
    threshold: u32 = 50,

    /// Create new specializer
    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    /// Specialize an instruction
    pub fn specialize(self: *Self, ctx: *SpecializationContext) SpecializedOp {
        if (!self.enabled) return .GENERIC;

        const result: SpecializedOp = switch (ctx.opcode) {
            106 => functions.specializeLoadAttr(ctx), // LOAD_ATTR
            95 => functions.specializeStoreAttr(ctx), // STORE_ATTR
            122 => functions.specializeBinaryOp(ctx), // BINARY_OP
            107 => functions.specializeCompareOp(ctx), // COMPARE_OP
            25 => functions.specializeBinarySubscr(ctx), // BINARY_SUBSCR
            60 => functions.specializeStoreSubscr(ctx), // STORE_SUBSCR
            92 => functions.specializeUnpackSequence(ctx), // UNPACK_SEQUENCE
            else => .GENERIC,
        };

        if (result != .GENERIC) {
            self.stats.recordSuccess();
        }

        return result;
    }

    /// Record deoptimization
    pub fn deoptimize(self: *Self, _: *SpecializationContext) void {
        self.stats.recordDeopt();
    }

    /// Get statistics
    pub fn getStats(self: *const Self) SpecializationStats {
        return self.stats;
    }

    /// Reset statistics
    pub fn resetStats(self: *Self) void {
        self.stats.reset();
    }
};

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var global_specializer: ?*Specializer = null;

/// Initialize the specialize module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get global specializer instance
pub fn getSpecializer() ?*Specializer {
    return global_specializer;
}

/// Set global specializer instance
pub fn setSpecializer(s: *Specializer) void {
    global_specializer = s;
}

/// Reset module state
pub fn resetModule() void {
    global_specializer = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "specializer integration" {
    const allocator = std.testing.allocator;

    var specializer = Specializer.init(allocator);

    var ctx = SpecializationContext{
        .ip = 0,
        .opcode = 122, // BINARY_OP
        .oparg = 0, // Add
        .cache = null,
        .lhs_type = .float_type,
        .rhs_type = .float_type,
    };

    const result = specializer.specialize(&ctx);
    try std.testing.expectEqual(SpecializedOp.BINARY_OP_ADD_FLOAT, result);
    try std.testing.expectEqual(@as(u64, 1), specializer.stats.successes);
}

test "statistics tracking" {
    var stats = SpecializationStats{};

    stats.recordSuccess();
    stats.recordSuccess();
    stats.recordDeopt();

    try std.testing.expectEqual(@as(u64, 2), stats.successes);
    try std.testing.expectEqual(@as(u64, 1), stats.deoptimizations);

    const rate = stats.getSuccessRate();
    try std.testing.expect(rate > 0.6 and rate < 0.7);
}
