/// _functools - C accelerator module for functools
/// Provides: reduce, partial, cmp_to_key, _lru_cache_wrapper
const std = @import("std");
const Allocator = std.mem.Allocator;

/// reduce(function, iterable[, initializer]) -> value
/// Apply a function of two arguments cumulatively to the items of an iterable,
/// from left to right, so as to reduce the iterable to a single value.
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

    var accumulator: T = initial orelse items[0];
    const start_idx: usize = if (initial == null) 1 else 0;

    for (items[start_idx..]) |item| {
        accumulator = func(accumulator, item);
    }

    return accumulator;
}

/// Dynamic reduce for runtime function pointers
pub fn reduceDynamic(
    comptime T: type,
    func: *const fn (T, T) T,
    items: []const T,
    initial: ?T,
) !T {
    if (items.len == 0) {
        if (initial) |init| {
            return init;
        }
        return error.EmptySequence;
    }

    var accumulator: T = initial orelse items[0];
    const start_idx: usize = if (initial == null) 1 else 0;

    for (items[start_idx..]) |item| {
        accumulator = func(accumulator, item);
    }

    return accumulator;
}

/// partial(func, *args, **kwargs) -> partial object
/// Create a new function with partial application of the given arguments and keywords.
pub fn Partial(comptime Func: type, comptime Args: type) type {
    return struct {
        func: Func,
        args: Args,

        const Self = @This();

        pub fn init(func: Func, args: Args) Self {
            return .{ .func = func, .args = args };
        }

        pub fn call(self: Self, extra_args: anytype) @typeInfo(@TypeOf(self.func)).@"fn".return_type.? {
            // Combine partial args with extra args and call
            return @call(.auto, self.func, self.args ++ extra_args);
        }
    };
}

/// Simple partial for single-arg functions
pub fn partial1(comptime ReturnType: type, comptime Arg1: type, comptime Arg2: type) type {
    return struct {
        func: *const fn (Arg1, Arg2) ReturnType,
        arg1: Arg1,

        const Self = @This();

        pub fn init(func: *const fn (Arg1, Arg2) ReturnType, arg1: Arg1) Self {
            return .{ .func = func, .arg1 = arg1 };
        }

        pub fn call(self: Self, arg2: Arg2) ReturnType {
            return self.func(self.arg1, arg2);
        }
    };
}

/// cmp_to_key(func) -> key function
/// Convert a cmp= function into a key= function for sorting.
pub fn CmpToKey(comptime T: type) type {
    return struct {
        value: T,
        cmp_func: *const fn (T, T) i32,

        const Self = @This();

        pub fn init(value: T, cmp_func: *const fn (T, T) i32) Self {
            return .{ .value = value, .cmp_func = cmp_func };
        }

        pub fn lessThan(self: Self, other: Self) bool {
            return self.cmp_func(self.value, other.value) < 0;
        }

        pub fn order(context: *const fn (T, T) i32, a: Self, b: Self) bool {
            _ = context;
            return a.cmp_func(a.value, b.value) < 0;
        }
    };
}

/// LRU Cache wrapper - implements functools.lru_cache
pub fn LruCache(comptime KeyType: type, comptime ValueType: type, comptime max_size: usize) type {
    return struct {
        cache: std.AutoHashMap(KeyType, CacheEntry),
        order: std.ArrayList(KeyType),
        hits: usize,
        misses: usize,
        allocator: Allocator,

        const CacheEntry = struct {
            value: ValueType,
            // Could add timestamp for LRU eviction
        };

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .cache = std.AutoHashMap(KeyType, CacheEntry).init(allocator),
                .order = std.ArrayList(KeyType).init(allocator),
                .hits = 0,
                .misses = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.cache.deinit();
            self.order.deinit(self.allocator);
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

            // Evict if at capacity
            if (self.cache.count() >= max_size and max_size > 0) {
                if (self.order.items.len > 0) {
                    const oldest = self.order.orderedRemove(0);
                    _ = self.cache.remove(oldest);
                }
            }

            try self.cache.put(key, .{ .value = value });
            try self.order.append(self.allocator, key);
        }

        pub fn cacheInfo(self: Self) CacheInfo {
            return .{
                .hits = self.hits,
                .misses = self.misses,
                .maxsize = max_size,
                .currsize = self.cache.count(),
            };
        }

        pub fn cacheClear(self: *Self) void {
            self.cache.clearRetainingCapacity();
            self.order.clearRetainingCapacity();
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

// ============================================================================
// Tests
// ============================================================================

test "reduce with initial value" {
    const add = struct {
        fn f(a: i32, b: i32) i32 {
            return a + b;
        }
    }.f;

    const items = [_]i32{ 1, 2, 3, 4, 5 };
    const result = try reduce(i32, add, &items, 0);
    try std.testing.expectEqual(@as(i32, 15), result);
}

test "reduce without initial value" {
    const mul = struct {
        fn f(a: i32, b: i32) i32 {
            return a * b;
        }
    }.f;

    const items = [_]i32{ 1, 2, 3, 4, 5 };
    const result = try reduce(i32, mul, &items, null);
    try std.testing.expectEqual(@as(i32, 120), result);
}

test "reduce empty sequence with initial" {
    const add = struct {
        fn f(a: i32, b: i32) i32 {
            return a + b;
        }
    }.f;

    const items = [_]i32{};
    const result = try reduce(i32, add, &items, 42);
    try std.testing.expectEqual(@as(i32, 42), result);
}

test "reduce empty sequence without initial" {
    const add = struct {
        fn f(a: i32, b: i32) i32 {
            return a + b;
        }
    }.f;

    const items = [_]i32{};
    const result = reduce(i32, add, &items, null);
    try std.testing.expectError(error.EmptySequence, result);
}

test "lru cache basic" {
    const allocator = std.testing.allocator;
    var cache = LruCache(i32, i32, 3).init(allocator);
    defer cache.deinit();

    try cache.put(1, 100);
    try cache.put(2, 200);

    try std.testing.expectEqual(@as(?i32, 100), cache.get(1));
    try std.testing.expectEqual(@as(?i32, 200), cache.get(2));
    try std.testing.expectEqual(@as(?i32, null), cache.get(3));
}

test "lru cache eviction" {
    const allocator = std.testing.allocator;
    var cache = LruCache(i32, i32, 2).init(allocator);
    defer cache.deinit();

    try cache.put(1, 100);
    try cache.put(2, 200);
    try cache.put(3, 300); // Should evict key 1

    try std.testing.expectEqual(@as(?i32, null), cache.get(1)); // Evicted
    try std.testing.expectEqual(@as(?i32, 200), cache.get(2));
    try std.testing.expectEqual(@as(?i32, 300), cache.get(3));
}
