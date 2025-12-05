/// Generic immutable fixed-size array implementation (comptime configurable)
///
/// Pattern: Write once, specialize many!
/// - Native tuples (no refcount)
/// - PyObject tuples (with refcount)
/// - Typed tuples ((i64, f64, str), etc.)
/// - Zero runtime cost (comptime specialization)

const std = @import("std");

/// Generic immutable tuple implementation
///
/// Config must provide:
/// - ItemType: type
/// - retainItem(item: ItemType) ItemType
/// - releaseItem(item: ItemType) void
pub fn TupleImpl(comptime Config: type) type {
    return struct {
        const Self = @This();

        items: []Config.ItemType,
        size: usize,
        allocator: std.mem.Allocator,

        // Cached hash (comptime: only if Config.cacheable)
        hash_cached: if (@hasDecl(Config, "cacheable") and Config.cacheable) ?u64 else void,

        /// Create tuple from items (takes ownership)
        pub fn init(allocator: std.mem.Allocator, size: usize) !Self {
            const items = try allocator.alloc(Config.ItemType, size);

            return Self{
                .items = items,
                .size = size,
                .allocator = allocator,
                .hash_cached = if (@hasDecl(Config, "cacheable") and Config.cacheable) null else {},
            };
        }

        /// Create tuple from slice (copies and retains items)
        pub fn fromSlice(allocator: std.mem.Allocator, items_slice: []const Config.ItemType) !Self {
            var tuple = try Self.init(allocator, items_slice.len);

            for (items_slice, 0..) |item, i| {
                tuple.items[i] = Config.retainItem(item);
            }

            return tuple;
        }

        /// Get item at index (immutable access)
        pub fn get(self: *const Self, idx: usize) ?Config.ItemType {
            if (idx >= self.size) return null;
            return self.items[idx];
        }

        /// Set item at index (only during construction!)
        /// NOTE: This should only be called before tuple is "frozen"
        pub fn setUnchecked(self: *Self, idx: usize, item: Config.ItemType) void {
            if (idx < self.size) {
                self.items[idx] = Config.retainItem(item);
            }
        }

        /// Get slice of items (creates new tuple)
        pub fn slice(self: *const Self, start: usize, end: usize) !Self {
            if (start > end or end > self.size) return error.InvalidSlice;

            const len = end - start;
            var new_tuple = try Self.init(self.allocator, len);

            for (self.items[start..end], 0..) |item, i| {
                new_tuple.items[i] = Config.retainItem(item);
            }

            return new_tuple;
        }

        /// Concatenate two tuples (creates new tuple)
        pub fn concat(self: *const Self, other: *const Self) !Self {
            const new_size = self.size + other.size;
            var new_tuple = try Self.init(self.allocator, new_size);

            for (self.items, 0..) |item, i| {
                new_tuple.items[i] = Config.retainItem(item);
            }

            for (other.items, 0..) |item, i| {
                new_tuple.items[self.size + i] = Config.retainItem(item);
            }

            return new_tuple;
        }

        /// Repeat tuple n times (creates new tuple)
        pub fn repeat(self: *const Self, n: usize) !Self {
            const new_size = self.size * n;
            var new_tuple = try Self.init(self.allocator, new_size);

            var offset: usize = 0;
            var i: usize = 0;
            while (i < n) : (i += 1) {
                for (self.items, 0..) |item, j| {
                    new_tuple.items[offset + j] = Config.retainItem(item);
                }
                offset += self.size;
            }

            return new_tuple;
        }

        /// Compute hash (comptime: caches if Config.cacheable)
        pub fn hash(self: *Self) u64 {
            if (@hasDecl(Config, "cacheable") and Config.cacheable) {
                if (self.hash_cached) |cached| {
                    return cached;
                }
            }

            // Compute hash from items
            var h: u64 = 0;

            for (self.items) |item| {
                // XOR with item hash (simple but effective)
                h ^= if (@hasDecl(Config, "hashItem"))
                    Config.hashItem(item)
                else
                    @as(u64, @bitCast(@as(i64, @intCast(@intFromPtr(&item)))));

                // Mix hash
                h = h *% 0x9e3779b97f4a7c15;
            }

            if (@hasDecl(Config, "cacheable") and Config.cacheable) {
                self.hash_cached = h;
            }

            return h;
        }

        /// Check equality with another tuple
        pub fn equals(self: *const Self, other: *const Self) bool {
            if (self.size != other.size) return false;

            for (self.items, other.items) |a, b| {
                if (@hasDecl(Config, "itemsEqual")) {
                    if (!Config.itemsEqual(a, b)) return false;
                } else {
                    // Default: pointer/value equality
                    if (a != b) return false;
                }
            }

            return true;
        }

        /// Count occurrences of value in tuple (Python tuple.count)
        pub fn count(self: *const Self, value: Config.ItemType) usize {
            var n: usize = 0;
            for (self.items) |item| {
                const is_equal = if (@hasDecl(Config, "itemsEqual"))
                    Config.itemsEqual(item, value)
                else
                    item == value;
                if (is_equal) n += 1;
            }
            return n;
        }

        /// Find first index of value in tuple (Python tuple.index)
        /// Returns error.NotFound if value not present
        pub fn index(self: *const Self, value: Config.ItemType, start: usize, end: ?usize) !usize {
            const stop = end orelse self.size;
            const actual_start = @min(start, self.size);
            const actual_stop = @min(stop, self.size);

            for (self.items[actual_start..actual_stop], actual_start..) |item, i| {
                const is_equal = if (@hasDecl(Config, "itemsEqual"))
                    Config.itemsEqual(item, value)
                else
                    item == value;
                if (is_equal) return i;
            }
            return error.NotFound;
        }

        /// Free all resources
        pub fn deinit(self: *Self) void {
            for (self.items) |item| {
                Config.releaseItem(item);
            }
            self.allocator.free(self.items);
        }

        /// Iterator
        pub const Iterator = struct {
            tuple: *const Self,
            index: usize,

            pub fn next(iter: *Iterator) ?Config.ItemType {
                if (iter.index >= iter.tuple.size) return null;

                const item = iter.tuple.items[iter.index];
                iter.index += 1;
                return item;
            }
        };

        pub fn iterator(self: *const Self) Iterator {
            return Iterator{
                .tuple = self,
                .index = 0,
            };
        }
    };
}

// ============================================================================
//                         EXAMPLE CONFIGS
// ============================================================================

/// Native i64 tuple (no refcount, no caching)
pub const NativeI64TupleConfig = struct {
    pub const ItemType = i64;
    pub const cacheable = false;

    pub fn retainItem(item: i64) i64 {
        return item; // No refcount for primitives
    }

    pub fn releaseItem(item: i64) void {
        _ = item; // No refcount for primitives
    }

    pub fn hashItem(item: i64) u64 {
        return @as(u64, @bitCast(item));
    }

    pub fn itemsEqual(a: i64, b: i64) bool {
        return a == b;
    }
};

/// PyObject tuple config (with refcount, with hash caching)
/// NOTE: Actual implementation in pyobject_tuple.zig
pub fn PyObjectTupleConfig(comptime PyObject: type) type {
    return struct {
        pub const ItemType = *PyObject;
        pub const cacheable = true; // PyTuples cache hash!

        pub fn retainItem(item: *PyObject) *PyObject {
            item.ob_refcnt += 1; // INCREF
            return item;
        }

        pub fn releaseItem(item: *PyObject) void {
            item.ob_refcnt -= 1; // DECREF
            // TODO: Dealloc if refcnt == 0
        }

        pub fn hashItem(item: *PyObject) u64 {
            // TODO: Call tp_hash slot
            return @intFromPtr(item);
        }

        pub fn itemsEqual(a: *PyObject, b: *PyObject) bool {
            // TODO: Call tp_richcompare slot
            return a == b;
        }
    };
}

// ============================================================================
//                              TESTS
// ============================================================================

test "TupleImpl - native i64 tuple" {
    const Tuple = TupleImpl(NativeI64TupleConfig);

    var tuple = try Tuple.init(std.testing.allocator, 3);
    defer tuple.deinit();

    // Set items during construction
    tuple.setUnchecked(0, 10);
    tuple.setUnchecked(1, 20);
    tuple.setUnchecked(2, 30);

    // Test get
    try std.testing.expectEqual(@as(i64, 10), tuple.get(0).?);
    try std.testing.expectEqual(@as(i64, 20), tuple.get(1).?);
    try std.testing.expectEqual(@as(i64, 30), tuple.get(2).?);

    // Test out of bounds
    try std.testing.expectEqual(@as(?i64, null), tuple.get(3));
}

test "TupleImpl - fromSlice" {
    const Tuple = TupleImpl(NativeI64TupleConfig);

    const items = [_]i64{ 1, 2, 3, 4, 5 };
    var tuple = try Tuple.fromSlice(std.testing.allocator, &items);
    defer tuple.deinit();

    try std.testing.expectEqual(@as(usize, 5), tuple.size);

    for (items, 0..) |expected, i| {
        try std.testing.expectEqual(expected, tuple.get(i).?);
    }
}

test "TupleImpl - concat and repeat" {
    const Tuple = TupleImpl(NativeI64TupleConfig);

    const items1 = [_]i64{ 1, 2 };
    var tuple1 = try Tuple.fromSlice(std.testing.allocator, &items1);
    defer tuple1.deinit();

    const items2 = [_]i64{ 3, 4 };
    var tuple2 = try Tuple.fromSlice(std.testing.allocator, &items2);
    defer tuple2.deinit();

    // Test concat
    var concatenated = try tuple1.concat(&tuple2);
    defer concatenated.deinit();

    try std.testing.expectEqual(@as(usize, 4), concatenated.size);
    try std.testing.expectEqual(@as(i64, 1), concatenated.get(0).?);
    try std.testing.expectEqual(@as(i64, 4), concatenated.get(3).?);

    // Test repeat
    var repeated = try tuple1.repeat(3);
    defer repeated.deinit();

    try std.testing.expectEqual(@as(usize, 6), repeated.size);
    try std.testing.expectEqual(@as(i64, 1), repeated.get(0).?);
    try std.testing.expectEqual(@as(i64, 2), repeated.get(1).?);
    try std.testing.expectEqual(@as(i64, 1), repeated.get(2).?);
    try std.testing.expectEqual(@as(i64, 2), repeated.get(3).?);
}

test "TupleImpl - hash and equals" {
    const Tuple = TupleImpl(NativeI64TupleConfig);

    const items1 = [_]i64{ 1, 2, 3 };
    var tuple1 = try Tuple.fromSlice(std.testing.allocator, &items1);
    defer tuple1.deinit();

    var tuple2 = try Tuple.fromSlice(std.testing.allocator, &items1);
    defer tuple2.deinit();

    const items3 = [_]i64{ 1, 2, 4 };
    var tuple3 = try Tuple.fromSlice(std.testing.allocator, &items3);
    defer tuple3.deinit();

    // Test equals
    try std.testing.expect(tuple1.equals(&tuple2));
    try std.testing.expect(!tuple1.equals(&tuple3));

    // Test hash (same items should have same hash)
    const hash1 = tuple1.hash();
    const hash2 = tuple2.hash();
    try std.testing.expectEqual(hash1, hash2);
}

test "TupleImpl - slice" {
    const Tuple = TupleImpl(NativeI64TupleConfig);

    const items = [_]i64{ 1, 2, 3, 4, 5 };
    var tuple = try Tuple.fromSlice(std.testing.allocator, &items);
    defer tuple.deinit();

    // Test slice
    var sliced = try tuple.slice(1, 4);
    defer sliced.deinit();

    try std.testing.expectEqual(@as(usize, 3), sliced.size);
    try std.testing.expectEqual(@as(i64, 2), sliced.get(0).?);
    try std.testing.expectEqual(@as(i64, 3), sliced.get(1).?);
    try std.testing.expectEqual(@as(i64, 4), sliced.get(2).?);
}

test "TupleImpl - count and index" {
    const Tuple = TupleImpl(NativeI64TupleConfig);

    const items = [_]i64{ 1, 2, 3, 2, 4, 2, 5 };
    var tuple = try Tuple.fromSlice(std.testing.allocator, &items);
    defer tuple.deinit();

    // Test count
    try std.testing.expectEqual(@as(usize, 3), tuple.count(2));
    try std.testing.expectEqual(@as(usize, 1), tuple.count(1));
    try std.testing.expectEqual(@as(usize, 0), tuple.count(99));

    // Test index (basic)
    try std.testing.expectEqual(@as(usize, 1), try tuple.index(2, 0, null));
    try std.testing.expectEqual(@as(usize, 0), try tuple.index(1, 0, null));

    // Test index with start
    try std.testing.expectEqual(@as(usize, 3), try tuple.index(2, 2, null));

    // Test index with start and end
    try std.testing.expectEqual(@as(usize, 3), try tuple.index(2, 2, 5));

    // Test index not found
    try std.testing.expectError(error.NotFound, tuple.index(99, 0, null));
    try std.testing.expectError(error.NotFound, tuple.index(2, 6, null)); // After all 2s
}
