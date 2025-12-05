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
/// The returned key wrapper supports all 6 comparison operators.
pub fn CmpToKey(comptime T: type) type {
    return struct {
        value: T,
        cmp_func: *const fn (T, T) i32,

        const Self = @This();

        pub fn init(value: T, cmp_func: *const fn (T, T) i32) Self {
            return .{ .value = value, .cmp_func = cmp_func };
        }

        /// Less than: a < b
        pub fn lt(self: Self, other: Self) bool {
            return self.cmp_func(self.value, other.value) < 0;
        }

        /// Less than or equal: a <= b
        pub fn le(self: Self, other: Self) bool {
            return self.cmp_func(self.value, other.value) <= 0;
        }

        /// Equal: a == b
        pub fn eq(self: Self, other: Self) bool {
            return self.cmp_func(self.value, other.value) == 0;
        }

        /// Not equal: a != b
        pub fn ne(self: Self, other: Self) bool {
            return self.cmp_func(self.value, other.value) != 0;
        }

        /// Greater than: a > b
        pub fn gt(self: Self, other: Self) bool {
            return self.cmp_func(self.value, other.value) > 0;
        }

        /// Greater than or equal: a >= b
        pub fn ge(self: Self, other: Self) bool {
            return self.cmp_func(self.value, other.value) >= 0;
        }

        /// Alias for lt (used by std.sort)
        pub fn lessThan(self: Self, other: Self) bool {
            return self.lt(other);
        }

        /// Order function for std.mem.sort context parameter
        pub fn order(context: *const fn (T, T) i32, a: Self, b: Self) bool {
            _ = context;
            return a.lt(b);
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
                .order = .empty,
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

/// cache(func) - Simple unbounded cache
/// This is equivalent to lru_cache(maxsize=None)
pub fn Cache(comptime KeyType: type, comptime ValueType: type) type {
    return struct {
        cache: std.AutoHashMap(KeyType, ValueType),
        hits: usize,
        misses: usize,
        allocator: Allocator,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .cache = std.AutoHashMap(KeyType, ValueType).init(allocator),
                .hits = 0,
                .misses = 0,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.cache.deinit();
        }

        pub fn get(self: *Self, key: KeyType) ?ValueType {
            if (self.cache.get(key)) |value| {
                self.hits += 1;
                return value;
            }
            return null;
        }

        pub fn put(self: *Self, key: KeyType, value: ValueType) !void {
            self.misses += 1;
            try self.cache.put(key, value);
        }

        pub fn cacheInfo(self: Self) CacheInfo {
            return .{
                .hits = self.hits,
                .misses = self.misses,
                .maxsize = 0, // 0 means unlimited
                .currsize = self.cache.count(),
            };
        }

        pub fn cacheClear(self: *Self) void {
            self.cache.clearRetainingCapacity();
            self.hits = 0;
            self.misses = 0;
        }
    };
}

/// WRAPPER_ASSIGNMENTS - Default attributes copied by update_wrapper
/// In Python: ('__module__', '__name__', '__qualname__', '__annotations__', '__doc__', '__wrapped__')
pub const WRAPPER_ASSIGNMENTS: [6][]const u8 = .{
    "__module__",
    "__name__",
    "__qualname__",
    "__annotations__",
    "__doc__",
    "__wrapped__",
};

/// WRAPPER_UPDATES - Default attributes updated by update_wrapper
/// In Python: ('__dict__',)
pub const WRAPPER_UPDATES: [1][]const u8 = .{
    "__dict__",
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

test "cmp_to_key comparisons" {
    // Standard comparison function: returns -1, 0, or 1
    const compare = struct {
        fn f(a: i32, b: i32) i32 {
            if (a < b) return -1;
            if (a > b) return 1;
            return 0;
        }
    }.f;

    const K = CmpToKey(i32);
    const k5 = K.init(5, &compare);
    const k3 = K.init(3, &compare);
    const k5b = K.init(5, &compare);

    // All 6 comparison operators
    try std.testing.expect(!k5.lt(k3)); // 5 < 3 is false
    try std.testing.expect(k3.lt(k5)); // 3 < 5 is true
    try std.testing.expect(!k5.le(k3)); // 5 <= 3 is false
    try std.testing.expect(k5.le(k5b)); // 5 <= 5 is true
    try std.testing.expect(k5.eq(k5b)); // 5 == 5 is true
    try std.testing.expect(!k5.eq(k3)); // 5 == 3 is false
    try std.testing.expect(k5.ne(k3)); // 5 != 3 is true
    try std.testing.expect(!k5.ne(k5b)); // 5 != 5 is false
    try std.testing.expect(k5.gt(k3)); // 5 > 3 is true
    try std.testing.expect(!k3.gt(k5)); // 3 > 5 is false
    try std.testing.expect(k5.ge(k5b)); // 5 >= 5 is true
    try std.testing.expect(k5.ge(k3)); // 5 >= 3 is true
}

test "cache basic (unbounded)" {
    const allocator = std.testing.allocator;
    var cache = Cache(i32, i32).init(allocator);
    defer cache.deinit();

    try cache.put(1, 100);
    try cache.put(2, 200);
    try cache.put(3, 300);

    try std.testing.expectEqual(@as(?i32, 100), cache.get(1));
    try std.testing.expectEqual(@as(?i32, 200), cache.get(2));
    try std.testing.expectEqual(@as(?i32, 300), cache.get(3));
    try std.testing.expectEqual(@as(?i32, null), cache.get(4));

    // No eviction - all items remain
    const info = cache.cacheInfo();
    try std.testing.expectEqual(@as(usize, 3), info.currsize);
    try std.testing.expectEqual(@as(usize, 0), info.maxsize); // 0 = unlimited
}

test "cache clear" {
    const allocator = std.testing.allocator;
    var cache = Cache(i32, i32).init(allocator);
    defer cache.deinit();

    try cache.put(1, 100);
    try cache.put(2, 200);

    cache.cacheClear();

    try std.testing.expectEqual(@as(?i32, null), cache.get(1));
    try std.testing.expectEqual(@as(?i32, null), cache.get(2));
    try std.testing.expectEqual(@as(usize, 0), cache.cacheInfo().currsize);
}
