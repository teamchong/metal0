//! CPython source: Modules/xxsubtype.c
//!
//! Internal test module for testing CPython's type/subtype C implementation.
//! Used to verify type inheritance, method resolution, and the type system.
//!
//! In metal0's AOT model, types are known at compile time and inheritance
//! is handled through Zig's type system. This module provides compatibility
//! testing for type-related behaviors.
//!
//! Mirrors: CPython Modules/xxsubtype.c

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Error Types
// ============================================================================

pub const XXSubtypeError = error{
    TestFailed,
    TypeError,
    AttributeError,
    RuntimeError,
    OutOfMemory,
};

// ============================================================================
// Test Counters
// ============================================================================

var tests_run: usize = 0;
var tests_passed: usize = 0;
var tests_failed: usize = 0;

// ============================================================================
// Base Types
// ============================================================================

/// Base list subtype for testing
pub const SpamList = struct {
    const Self = @This();

    /// Internal list storage
    items: std.ArrayList(i64),
    /// Custom state attribute
    state: i32 = 0,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .items = std.ArrayList(i64).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.items.deinit();
    }

    pub fn append(self: *Self, item: i64) !void {
        try self.items.append(item);
    }

    pub fn len(self: *const Self) usize {
        return self.items.items.len;
    }

    pub fn get(self: *const Self, index: usize) ?i64 {
        if (index >= self.items.items.len) return null;
        return self.items.items[index];
    }

    /// Custom method: get the state
    pub fn getstate(self: *const Self) i32 {
        return self.state;
    }

    /// Custom method: set the state
    pub fn setstate(self: *Self, state: i32) void {
        self.state = state;
    }
};

/// Base dict subtype for testing
pub const SpamDict = struct {
    const Self = @This();

    /// Internal map storage
    map: hashmap_helper.StringHashMap(i64),
    /// Custom state attribute
    state: i32 = 0,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .map = hashmap_helper.StringHashMap(i64).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn put(self: *Self, key: []const u8, value: i64) !void {
        try self.map.put(key, value);
    }

    pub fn get(self: *const Self, key: []const u8) ?i64 {
        return self.map.get(key);
    }

    pub fn len(self: *const Self) usize {
        return self.map.count();
    }

    /// Custom method: get the state
    pub fn getstate(self: *const Self) i32 {
        return self.state;
    }

    /// Custom method: set the state
    pub fn setstate(self: *Self, state: i32) void {
        self.state = state;
    }
};

// ============================================================================
// Subtype Tests
// ============================================================================

/// Test SpamList creation
pub fn test_spamlist_create() XXSubtypeError!void {
    tests_run += 1;
    const allocator = std.heap.page_allocator;
    var list = SpamList.init(allocator);
    defer list.deinit();
    tests_passed += 1;
}

/// Test SpamList append
pub fn test_spamlist_append() XXSubtypeError!void {
    tests_run += 1;
    const allocator = std.heap.page_allocator;
    var list = SpamList.init(allocator);
    defer list.deinit();

    list.append(1) catch return error.OutOfMemory;
    list.append(2) catch return error.OutOfMemory;

    if (list.len() != 2) {
        tests_failed += 1;
        return error.TestFailed;
    }
    tests_passed += 1;
}

/// Test SpamList state
pub fn test_spamlist_state() XXSubtypeError!void {
    tests_run += 1;
    const allocator = std.heap.page_allocator;
    var list = SpamList.init(allocator);
    defer list.deinit();

    list.setstate(42);
    if (list.getstate() != 42) {
        tests_failed += 1;
        return error.TestFailed;
    }
    tests_passed += 1;
}

/// Test SpamDict creation
pub fn test_spamdict_create() XXSubtypeError!void {
    tests_run += 1;
    const allocator = std.heap.page_allocator;
    var dict = SpamDict.init(allocator);
    defer dict.deinit();
    tests_passed += 1;
}

/// Test SpamDict put/get
pub fn test_spamdict_operations() XXSubtypeError!void {
    tests_run += 1;
    const allocator = std.heap.page_allocator;
    var dict = SpamDict.init(allocator);
    defer dict.deinit();

    dict.put("key", 100) catch return error.OutOfMemory;
    const value = dict.get("key") orelse {
        tests_failed += 1;
        return error.TestFailed;
    };

    if (value != 100) {
        tests_failed += 1;
        return error.TestFailed;
    }
    tests_passed += 1;
}

/// Test SpamDict state
pub fn test_spamdict_state() XXSubtypeError!void {
    tests_run += 1;
    const allocator = std.heap.page_allocator;
    var dict = SpamDict.init(allocator);
    defer dict.deinit();

    dict.setstate(99);
    if (dict.getstate() != 99) {
        tests_failed += 1;
        return error.TestFailed;
    }
    tests_passed += 1;
}

// ============================================================================
// Type System Tests
// ============================================================================

/// Test type size
pub fn test_type_size() XXSubtypeError!void {
    tests_run += 1;
    // SpamList should have non-zero size
    if (@sizeOf(SpamList) == 0) {
        tests_failed += 1;
        return error.TestFailed;
    }
    tests_passed += 1;
}

/// Test type alignment
pub fn test_type_alignment() XXSubtypeError!void {
    tests_run += 1;
    // Types should be properly aligned
    if (@alignOf(SpamList) == 0) {
        tests_failed += 1;
        return error.TestFailed;
    }
    tests_passed += 1;
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Run all xxsubtype tests
pub fn run_all_tests() XXSubtypeError!void {
    tests_run = 0;
    tests_passed = 0;
    tests_failed = 0;

    try test_spamlist_create();
    try test_spamlist_append();
    try test_spamlist_state();
    try test_spamdict_create();
    try test_spamdict_operations();
    try test_spamdict_state();
    try test_type_size();
    try test_type_alignment();
}

/// Get test statistics
pub fn get_test_stats() struct { run: usize, passed: usize, failed: usize } {
    return .{
        .run = tests_run,
        .passed = tests_passed,
        .failed = tests_failed,
    };
}

/// Reset test counters
pub fn reset_test_stats() void {
    tests_run = 0;
    tests_passed = 0;
    tests_failed = 0;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
    reset_test_stats();
}

pub fn reset() void {
    reset_test_stats();
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "run xxsubtype tests" {
    init();
    try run_all_tests();
    const stats = get_test_stats();
    try std.testing.expect(stats.run > 0);
    try std.testing.expectEqual(stats.run, stats.passed);
}

test "SpamList basic operations" {
    const allocator = std.testing.allocator;
    var list = SpamList.init(allocator);
    defer list.deinit();

    try list.append(10);
    try list.append(20);

    try std.testing.expectEqual(@as(usize, 2), list.len());
    try std.testing.expectEqual(@as(i64, 10), list.get(0).?);
    try std.testing.expectEqual(@as(i64, 20), list.get(1).?);
}

test "SpamList state" {
    const allocator = std.testing.allocator;
    var list = SpamList.init(allocator);
    defer list.deinit();

    try std.testing.expectEqual(@as(i32, 0), list.getstate());
    list.setstate(123);
    try std.testing.expectEqual(@as(i32, 123), list.getstate());
}

test "SpamDict basic operations" {
    const allocator = std.testing.allocator;
    var dict = SpamDict.init(allocator);
    defer dict.deinit();

    try dict.put("foo", 42);
    try dict.put("bar", 100);

    try std.testing.expectEqual(@as(usize, 2), dict.len());
    try std.testing.expectEqual(@as(i64, 42), dict.get("foo").?);
    try std.testing.expectEqual(@as(i64, 100), dict.get("bar").?);
}

test "type sizes" {
    try std.testing.expect(@sizeOf(SpamList) > 0);
    try std.testing.expect(@sizeOf(SpamDict) > 0);
}
