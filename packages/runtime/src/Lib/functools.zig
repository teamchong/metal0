//! Python 'functools' module - Higher-order functions and operations on callable objects
//!
//! Provides tools for working with functions and callable objects.
//! Includes function caching, partial application, and reduction.
//!
//! Mirrors: CPython Lib/functools.py

const std = @import("std");

/// Sentinel value for reduce with no initial value
pub const SENTINEL = struct {};

/// Apply a function cumulatively to items of a sequence (left to right)
/// to reduce the sequence to a single value.
pub fn reduce(
    comptime T: type,
    comptime func: fn (T, T) T,
    items: []const T,
    initial: ?T,
) !T {
    if (items.len == 0) {
        if (initial) |init| {
            return init;
        }
        return error.EmptySequence;
    }

    var result: T = initial orelse items[0];
    const start: usize = if (initial == null) 1 else 0;

    for (items[start..]) |item| {
        result = func(result, item);
    }

    return result;
}

/// Create a partial function application
/// Returns a struct that can be called with the remaining arguments
pub fn partial(comptime Func: type, comptime func: Func, args: anytype) Partial(Func, @TypeOf(args)) {
    return .{ .func = func, .args = args };
}

pub fn Partial(comptime Func: type, comptime ArgsType: type) type {
    return struct {
        func: Func,
        args: ArgsType,

        const Self = @This();

        pub fn call(self: Self, remaining_args: anytype) CallReturnType(Func) {
            // Combine partial args with remaining args
            return @call(.auto, self.func, self.args ++ remaining_args);
        }
    };
}

fn CallReturnType(comptime Func: type) type {
    const info = @typeInfo(Func);
    return switch (info) {
        .@"fn" => |f| f.return_type orelse void,
        .pointer => |p| CallReturnType(p.child),
        else => void,
    };
}

/// LRU (Least Recently Used) Cache
/// Memoization decorator that caches function results
pub fn LruCache(comptime KeyType: type, comptime ValueType: type, comptime maxsize: usize) type {
    return struct {
        cache: std.AutoHashMap(KeyType, CacheEntry),
        order: [maxsize]?KeyType,
        order_head: usize,
        hits: usize,
        misses: usize,
        allocator: std.mem.Allocator,

        const CacheEntry = struct {
            value: ValueType,
            age: usize,
        };

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .cache = std.AutoHashMap(KeyType, CacheEntry).init(allocator),
                .order = [_]?KeyType{null} ** maxsize,
                .order_head = 0,
                .hits = 0,
                .misses = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.cache.deinit();
        }

        pub fn get(self: *Self, key: KeyType) ?ValueType {
            if (self.cache.get(key)) |entry| {
                self.hits += 1;
                return entry.value;
            }
            return null;
        }

        pub fn put(self: *Self, key: KeyType, value: ValueType) !void {
            self.misses += 1;

            // If at capacity, evict oldest
            if (self.cache.count() >= maxsize) {
                if (self.order[self.order_head]) |old_key| {
                    _ = self.cache.remove(old_key);
                }
            }

            try self.cache.put(key, .{ .value = value, .age = self.order_head });
            self.order[self.order_head] = key;
            self.order_head = (self.order_head + 1) % maxsize;
        }

        pub fn cacheInfo(self: *const Self) CacheInfo {
            return .{
                .hits = self.hits,
                .misses = self.misses,
                .maxsize = maxsize,
                .currsize = self.cache.count(),
            };
        }

        pub fn cacheClear(self: *Self) void {
            self.cache.clearRetainingCapacity();
            self.order = [_]?KeyType{null} ** maxsize;
            self.order_head = 0;
            self.hits = 0;
            self.misses = 0;
        }
    };
}

pub const CacheInfo = struct {
    hits: usize,
    misses: usize,
    maxsize: usize,
    currsize: usize,
};

/// Compare two values using a key function
pub fn cmpToKey(comptime T: type, comptime cmp: fn (T, T) std.math.Order) type {
    return struct {
        value: T,

        const Self = @This();

        pub fn lessThan(a: Self, b: Self) bool {
            return cmp(a.value, b.value) == .lt;
        }

        pub fn init(value: T) Self {
            return .{ .value = value };
        }
    };
}

/// Total ordering from comparison methods
/// Given a class with __eq__ and one of __lt__, __le__, __gt__, __ge__,
/// fills in the rest
pub const TotalOrdering = struct {
    pub fn lessThan(comptime T: type, a: T, b: T) bool {
        if (@hasDecl(T, "lt")) {
            return T.lt(a, b);
        } else if (@hasDecl(T, "le") and @hasDecl(T, "eq")) {
            return T.le(a, b) and !T.eq(a, b);
        } else if (@hasDecl(T, "gt")) {
            return !T.gt(a, b) and !T.eq(a, b);
        } else if (@hasDecl(T, "ge")) {
            return !T.ge(a, b);
        }
        @compileError("Type must have at least one comparison method");
    }

    pub fn lessOrEqual(comptime T: type, a: T, b: T) bool {
        return lessThan(T, a, b) or T.eq(a, b);
    }

    pub fn greaterThan(comptime T: type, a: T, b: T) bool {
        return !lessOrEqual(T, a, b);
    }

    pub fn greaterOrEqual(comptime T: type, a: T, b: T) bool {
        return !lessThan(T, a, b);
    }
};

/// Wraps a function to cache results (simple version)
pub fn cache(comptime KeyType: type, comptime ValueType: type) type {
    return LruCache(KeyType, ValueType, 128);
}

/// Identity function - returns its argument unchanged
pub fn identity(x: anytype) @TypeOf(x) {
    return x;
}

// ============================================================================
// Tests
// ============================================================================

fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn multiply(a: i32, b: i32) i32 {
    return a * b;
}

test "reduce with addition" {
    const items = [_]i32{ 1, 2, 3, 4, 5 };
    const result = try reduce(i32, add, &items, null);
    try std.testing.expectEqual(@as(i32, 15), result);
}

test "reduce with multiplication" {
    const items = [_]i32{ 1, 2, 3, 4, 5 };
    const result = try reduce(i32, multiply, &items, null);
    try std.testing.expectEqual(@as(i32, 120), result);
}

test "reduce with initial value" {
    const items = [_]i32{ 1, 2, 3 };
    const result = try reduce(i32, add, &items, 10);
    try std.testing.expectEqual(@as(i32, 16), result);
}

test "reduce empty with initial" {
    const items = [_]i32{};
    const result = try reduce(i32, add, &items, 42);
    try std.testing.expectEqual(@as(i32, 42), result);
}

test "reduce empty without initial" {
    const items = [_]i32{};
    const result = reduce(i32, add, &items, null);
    try std.testing.expectError(error.EmptySequence, result);
}

test "LruCache basic operations" {
    const allocator = std.testing.allocator;
    var lru = LruCache(i32, i32, 3).init(allocator);
    defer lru.deinit();

    try lru.put(1, 100);
    try lru.put(2, 200);

    try std.testing.expectEqual(@as(?i32, 100), lru.get(1));
    try std.testing.expectEqual(@as(?i32, 200), lru.get(2));
    try std.testing.expectEqual(@as(?i32, null), lru.get(3));
}

test "LruCache eviction" {
    const allocator = std.testing.allocator;
    var lru = LruCache(i32, i32, 2).init(allocator);
    defer lru.deinit();

    try lru.put(1, 100);
    try lru.put(2, 200);
    try lru.put(3, 300); // Should evict key 1

    try std.testing.expectEqual(@as(?i32, null), lru.get(1));
    try std.testing.expectEqual(@as(?i32, 200), lru.get(2));
    try std.testing.expectEqual(@as(?i32, 300), lru.get(3));
}

test "LruCache info" {
    const allocator = std.testing.allocator;
    var lru = LruCache(i32, i32, 10).init(allocator);
    defer lru.deinit();

    try lru.put(1, 100);
    _ = lru.get(1); // hit
    _ = lru.get(2); // miss (not found)

    const info = lru.cacheInfo();
    try std.testing.expectEqual(@as(usize, 1), info.hits);
    try std.testing.expectEqual(@as(usize, 1), info.misses);
    try std.testing.expectEqual(@as(usize, 10), info.maxsize);
}

test "identity" {
    try std.testing.expectEqual(@as(i32, 42), identity(@as(i32, 42)));
    try std.testing.expectEqualStrings("hello", identity("hello"));
}
