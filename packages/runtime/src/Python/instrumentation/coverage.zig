/// instrumentation/coverage - Coverage tracking support
/// Simple line and branch coverage tracking

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Coverage Support
// ============================================================================

/// Simple coverage tracking
pub const CoverageData = struct {
    /// Lines executed (line number -> count)
    lines: std.AutoHashMap(u32, u64),
    /// Branches taken
    branches: std.AutoHashMap(u64, u64),
    /// Allocator
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .lines = std.AutoHashMap(u32, u64).init(allocator),
            .branches = std.AutoHashMap(u64, u64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.lines.deinit();
        self.branches.deinit();
    }

    pub fn recordLine(self: *Self, lineno: u32) !void {
        const entry = try self.lines.getOrPut(lineno);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    pub fn recordBranch(self: *Self, from: u32, to: u32) !void {
        const key = (@as(u64, from) << 32) | @as(u64, to);
        const entry = try self.branches.getOrPut(key);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    pub fn getLineCount(self: *const Self, lineno: u32) u64 {
        return self.lines.get(lineno) orelse 0;
    }

    pub fn wasLineExecuted(self: *const Self, lineno: u32) bool {
        return self.lines.contains(lineno);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "coverage data" {
    var cov = CoverageData.init(std.testing.allocator);
    defer cov.deinit();

    try cov.recordLine(10);
    try cov.recordLine(10);
    try cov.recordLine(20);

    try std.testing.expectEqual(@as(u64, 2), cov.getLineCount(10));
    try std.testing.expectEqual(@as(u64, 1), cov.getLineCount(20));
    try std.testing.expectEqual(@as(u64, 0), cov.getLineCount(30));

    try std.testing.expect(cov.wasLineExecuted(10));
    try std.testing.expect(!cov.wasLineExecuted(30));
}
