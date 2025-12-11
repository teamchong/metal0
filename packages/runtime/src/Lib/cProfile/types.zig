//! Profile data types
//!
//! Core types for profile entries and call stack tracking.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Profile Entry
// ============================================================================

/// Statistics for a single function
pub const ProfileEntry = struct {
    /// Number of calls
    ncalls: u64 = 0,
    /// Number of recursive calls
    nrcalls: u64 = 0,
    /// Total time in this function
    tottime: f64 = 0.0,
    /// Cumulative time (including subcalls)
    cumtime: f64 = 0.0,
    /// Function name
    name: []const u8,
    /// File name
    filename: []const u8,
    /// Line number
    lineno: usize,
    /// Callers: maps caller name -> call count
    callers: hashmap_helper.StringHashMap(u64) = undefined,
    /// Callees: maps callee name -> call count
    callees: hashmap_helper.StringHashMap(u64) = undefined,
    allocator: ?std.mem.Allocator = null,

    pub fn init(name: []const u8, filename: []const u8, lineno: usize) ProfileEntry {
        return .{
            .name = name,
            .filename = filename,
            .lineno = lineno,
            .callers = undefined,
            .callees = undefined,
            .allocator = null,
        };
    }

    pub fn initWithAllocator(allocator: std.mem.Allocator, name: []const u8, filename: []const u8, lineno: usize) ProfileEntry {
        return .{
            .name = name,
            .filename = filename,
            .lineno = lineno,
            .callers = hashmap_helper.StringHashMap(u64).init(allocator),
            .callees = hashmap_helper.StringHashMap(u64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ProfileEntry) void {
        if (self.allocator != null) {
            self.callers.deinit();
            self.callees.deinit();
        }
    }

    /// Record a call from caller
    pub fn recordCaller(self: *ProfileEntry, caller_name: []const u8) void {
        if (self.allocator == null) return;
        const entry = self.callers.getOrPut(caller_name) catch return;
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    /// Record a call to callee
    pub fn recordCallee(self: *ProfileEntry, callee_name: []const u8) void {
        if (self.allocator == null) return;
        const entry = self.callees.getOrPut(callee_name) catch return;
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    /// Get per-call time
    pub fn percallTot(self: *const ProfileEntry) f64 {
        if (self.ncalls == 0) return 0.0;
        return self.tottime / @as(f64, @floatFromInt(self.ncalls));
    }

    /// Get per-call cumulative time
    pub fn percallCum(self: *const ProfileEntry) f64 {
        if (self.ncalls == 0) return 0.0;
        return self.cumtime / @as(f64, @floatFromInt(self.ncalls));
    }
};

// ============================================================================
// Call Stack Entry
// ============================================================================

/// Entry in the call stack for tracking nested calls
pub const CallStackEntry = struct {
    name: []const u8,
    start_time: i128,
    subcall_time: f64,
};

// ============================================================================
// Tests
// ============================================================================

test "ProfileEntry init" {
    const entry = ProfileEntry.init("test", "test.py", 10);
    try std.testing.expectEqualStrings("test", entry.name);
    try std.testing.expectEqualStrings("test.py", entry.filename);
    try std.testing.expectEqual(@as(usize, 10), entry.lineno);
    try std.testing.expectEqual(@as(u64, 0), entry.ncalls);
}

test "ProfileEntry percall" {
    var entry = ProfileEntry.init("test", "test.py", 10);
    entry.ncalls = 10;
    entry.tottime = 1.0;
    entry.cumtime = 2.0;

    try std.testing.expectApproxEqAbs(@as(f64, 0.1), entry.percallTot(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2), entry.percallCum(), 0.001);
}

test "ProfileEntry percall zero calls" {
    const entry = ProfileEntry.init("test", "test.py", 10);
    try std.testing.expectEqual(@as(f64, 0.0), entry.percallTot());
    try std.testing.expectEqual(@as(f64, 0.0), entry.percallCum());
}
