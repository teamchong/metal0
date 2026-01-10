//! zipfile._path._functools - Functional tools for zipfile path operations
//! Reference: cpython/Lib/zipfile/_path/_functools.py (internal)
//!
//! Utility functions for zipfile path operations.

const std = @import("std");

/// Pass-through filter that accepts everything
pub fn passThrough(comptime T: type) fn (T) bool {
    return struct {
        fn f(_: T) bool {
            return true;
        }
    }.f;
}

/// Create a filter that matches items with a specific prefix
pub fn prefixFilter(allocator: std.mem.Allocator, prefix: []const u8) !struct {
    allocator: std.mem.Allocator,
    prefix: []const u8,

    pub fn match(self: @This(), item: []const u8) bool {
        return std.mem.startsWith(u8, item, self.prefix);
    }
} {
    return .{
        .allocator = allocator,
        .prefix = prefix,
    };
}

/// Create a filter that matches items with a specific suffix
pub fn suffixFilter(allocator: std.mem.Allocator, suffix: []const u8) !struct {
    allocator: std.mem.Allocator,
    suffix: []const u8,

    pub fn match(self: @This(), item: []const u8) bool {
        return std.mem.endsWith(u8, item, self.suffix);
    }
} {
    return .{
        .allocator = allocator,
        .suffix = suffix,
    };
}

/// Compose two filters with AND logic
pub fn andFilter(comptime T: type, f1: fn (T) bool, f2: fn (T) bool) fn (T) bool {
    return struct {
        fn f(item: T) bool {
            return f1(item) and f2(item);
        }
    }.f;
}

/// Compose two filters with OR logic
pub fn orFilter(comptime T: type, f1: fn (T) bool, f2: fn (T) bool) fn (T) bool {
    return struct {
        fn f(item: T) bool {
            return f1(item) or f2(item);
        }
    }.f;
}

/// Negate a filter
pub fn notFilter(comptime T: type, f: fn (T) bool) fn (T) bool {
    return struct {
        fn neg(item: T) bool {
            return !f(item);
        }
    }.neg;
}

/// Cached property implementation
pub fn CachedProperty(comptime T: type, comptime ValueT: type, comptime getter: fn (*T) ValueT) type {
    return struct {
        const Self = @This();

        cached: ?ValueT = null,
        owner: *T,

        pub fn init(owner: *T) Self {
            return .{ .owner = owner };
        }

        pub fn get(self: *Self) ValueT {
            if (self.cached) |v| {
                return v;
            }
            const value = getter(self.owner);
            self.cached = value;
            return value;
        }

        pub fn invalidate(self: *Self) void {
            self.cached = null;
        }
    };
}

/// Method wrapper for consistent calling convention
pub fn MethodWrapper(comptime SelfT: type, comptime RetT: type) type {
    return struct {
        self: *SelfT,
        method: *const fn (*SelfT) RetT,

        pub fn call(wrapper: @This()) RetT {
            return wrapper.method(wrapper.self);
        }
    };
}

/// Identity function
pub fn identity(comptime T: type) fn (T) T {
    return struct {
        fn f(x: T) T {
            return x;
        }
    }.f;
}

/// Constant function
pub fn constant(comptime T: type, comptime value: T) fn (anytype) T {
    return struct {
        fn f(_: anytype) T {
            return value;
        }
    }.f;
}

/// Memoize function results
pub fn Memoize(comptime KeyT: type, comptime ValueT: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        cache: std.AutoHashMap(KeyT, ValueT),
        func: *const fn (KeyT) ValueT,

        pub fn init(allocator: std.mem.Allocator, func: *const fn (KeyT) ValueT) Self {
            return .{
                .allocator = allocator,
                .cache = std.AutoHashMap(KeyT, ValueT).init(allocator),
                .func = func,
            };
        }

        pub fn deinit(self: *Self) void {
            self.cache.deinit();
        }

        pub fn call(self: *Self, key: KeyT) !ValueT {
            if (self.cache.get(key)) |cached| {
                return cached;
            }
            const result = self.func(key);
            try self.cache.put(key, result);
            return result;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "passThrough" {
    const filter = passThrough([]const u8);
    try std.testing.expect(filter("anything"));
    try std.testing.expect(filter(""));
}

test "prefixFilter" {
    const allocator = std.testing.allocator;
    const filter = try prefixFilter(allocator, "test_");
    try std.testing.expect(filter.match("test_file.txt"));
    try std.testing.expect(!filter.match("file.txt"));
}

test "suffixFilter" {
    const allocator = std.testing.allocator;
    const filter = try suffixFilter(allocator, ".txt");
    try std.testing.expect(filter.match("file.txt"));
    try std.testing.expect(!filter.match("file.py"));
}

test "identity" {
    const f = identity(i32);
    try std.testing.expectEqual(@as(i32, 42), f(42));
}
