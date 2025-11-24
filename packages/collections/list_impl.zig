/// Generic dynamic array implementation (comptime configurable)
///
/// Pattern: Write once, specialize many!
/// - Native lists (no refcount)
/// - PyObject lists (with refcount)
/// - Typed lists (i64[], f64[], etc.)
/// - Zero runtime cost (comptime specialization)

const std = @import("std");

/// Generic dynamic array implementation
///
/// Config must provide:
/// - ItemType: type
/// - retainItem(item: ItemType) ItemType
/// - releaseItem(item: ItemType) void
pub fn ListImpl(comptime Config: type) type {
    return struct {
        const Self = @This();

        items: []Config.ItemType,
        size: usize,
        capacity: usize,
        allocator: std.mem.Allocator,

        /// Initialize empty list
        pub fn init(allocator: std.mem.Allocator) !Self {
            return Self{
                .items = &[_]Config.ItemType{},
                .size = 0,
                .capacity = 0,
                .allocator = allocator,
            };
        }

        /// Initialize with initial capacity
        pub fn initCapacity(allocator: std.mem.Allocator, capacity: usize) !Self {
            const items = try allocator.alloc(Config.ItemType, capacity);
            return Self{
                .items = items,
                .size = 0,
                .capacity = capacity,
                .allocator = allocator,
            };
        }

        /// Append item to end of list
        pub fn append(self: *Self, item: Config.ItemType) !void {
            if (self.size >= self.capacity) {
                try self.grow();
            }

            self.items[self.size] = Config.retainItem(item);
            self.size += 1;
        }

        /// Insert item at index
        pub fn insert(self: *Self, index: usize, item: Config.ItemType) !void {
            if (index > self.size) return error.IndexOutOfBounds;

            if (self.size >= self.capacity) {
                try self.grow();
            }

            // Shift items right
            if (index < self.size) {
                var i = self.size;
                while (i > index) : (i -= 1) {
                    self.items[i] = self.items[i - 1];
                }
            }

            self.items[index] = Config.retainItem(item);
            self.size += 1;
        }

        /// Get item at index
        pub fn get(self: *Self, index: usize) ?Config.ItemType {
            if (index >= self.size) return null;
            return self.items[index];
        }

        /// Set item at index (replaces existing)
        pub fn set(self: *Self, index: usize, item: Config.ItemType) !void {
            if (index >= self.size) return error.IndexOutOfBounds;

            // Release old item
            Config.releaseItem(self.items[index]);

            // Set new item
            self.items[index] = Config.retainItem(item);
        }

        /// Remove and return item at index
        pub fn remove(self: *Self, index: usize) !Config.ItemType {
            if (index >= self.size) return error.IndexOutOfBounds;

            const item = self.items[index];

            // Shift items left
            var i = index;
            while (i < self.size - 1) : (i += 1) {
                self.items[i] = self.items[i + 1];
            }

            self.size -= 1;

            // Note: item is already retained, caller owns it
            return item;
        }

        /// Pop last item
        pub fn pop(self: *Self) ?Config.ItemType {
            if (self.size == 0) return null;

            self.size -= 1;
            return self.items[self.size];
        }

        /// Clear all items
        pub fn clear(self: *Self) void {
            for (self.items[0..self.size]) |item| {
                Config.releaseItem(item);
            }
            self.size = 0;
        }

        /// Get slice of items (comptime: only if allowed by config)
        pub fn slice(self: *Self, start: usize, end: usize) !Self {
            if (start > end or end > self.size) return error.InvalidSlice;

            const len = end - start;
            var new_list = try Self.initCapacity(self.allocator, len);

            for (self.items[start..end]) |item| {
                try new_list.append(item);
            }

            return new_list;
        }

        /// Concatenate two lists
        pub fn concat(self: *Self, other: *Self) !Self {
            var new_list = try Self.initCapacity(self.allocator, self.size + other.size);

            for (self.items[0..self.size]) |item| {
                try new_list.append(item);
            }

            for (other.items[0..other.size]) |item| {
                try new_list.append(item);
            }

            return new_list;
        }

        /// Repeat list n times
        pub fn repeat(self: *Self, n: usize) !Self {
            const new_size = self.size * n;
            var new_list = try Self.initCapacity(self.allocator, new_size);

            var i: usize = 0;
            while (i < n) : (i += 1) {
                for (self.items[0..self.size]) |item| {
                    try new_list.append(item);
                }
            }

            return new_list;
        }

        /// Reverse list in place
        pub fn reverse(self: *Self) void {
            if (self.size <= 1) return;

            var i: usize = 0;
            var j = self.size - 1;

            while (i < j) {
                const temp = self.items[i];
                self.items[i] = self.items[j];
                self.items[j] = temp;
                i += 1;
                j -= 1;
            }
        }

        /// Sort list (comptime: only if Config provides compare function)
        pub fn sort(self: *Self, comptime lessThan: fn (a: Config.ItemType, b: Config.ItemType) bool) void {
            if (self.size <= 1) return;

            // Simple insertion sort (TODO: use quicksort for large lists)
            var i: usize = 1;
            while (i < self.size) : (i += 1) {
                const key = self.items[i];
                var j = i;

                while (j > 0 and lessThan(key, self.items[j - 1])) {
                    self.items[j] = self.items[j - 1];
                    j -= 1;
                }

                self.items[j] = key;
            }
        }

        /// Free all resources
        pub fn deinit(self: *Self) void {
            for (self.items[0..self.size]) |item| {
                Config.releaseItem(item);
            }

            if (self.capacity > 0) {
                self.allocator.free(self.items);
            }
        }

        /// Grow capacity (double or initial size)
        fn grow(self: *Self) !void {
            const new_capacity = if (self.capacity == 0) 8 else self.capacity * 2;

            const new_items = try self.allocator.alloc(Config.ItemType, new_capacity);

            // Copy existing items
            if (self.size > 0) {
                @memcpy(new_items[0..self.size], self.items[0..self.size]);
            }

            // Free old array
            if (self.capacity > 0) {
                self.allocator.free(self.items);
            }

            self.items = new_items;
            self.capacity = new_capacity;
        }

        /// Iterator
        pub const Iterator = struct {
            list: *Self,
            index: usize,

            pub fn next(iter: *Iterator) ?Config.ItemType {
                if (iter.index >= iter.list.size) return null;

                const item = iter.list.items[iter.index];
                iter.index += 1;
                return item;
            }
        };

        pub fn iterator(self: *Self) Iterator {
            return Iterator{
                .list = self,
                .index = 0,
            };
        }
    };
}

// ============================================================================
//                         EXAMPLE CONFIGS
// ============================================================================

/// Native i64 list (no refcount)
pub const NativeI64ListConfig = struct {
    pub const ItemType = i64;

    pub fn retainItem(item: i64) i64 {
        return item; // No refcount for primitives
    }

    pub fn releaseItem(item: i64) void {
        _ = item; // No refcount for primitives
    }
};

/// Native string list (no refcount, no ownership)
pub const NativeStringListConfig = struct {
    pub const ItemType = []const u8;

    pub fn retainItem(item: []const u8) []const u8 {
        return item; // No refcount for native
    }

    pub fn releaseItem(item: []const u8) void {
        _ = item; // No refcount for native
    }
};

/// PyObject list config (with refcount)
/// NOTE: Actual implementation in pyobject_list.zig
pub fn PyObjectListConfig(comptime PyObject: type) type {
    return struct {
        pub const ItemType = *PyObject;

        pub fn retainItem(item: *PyObject) *PyObject {
            item.ob_refcnt += 1; // INCREF
            return item;
        }

        pub fn releaseItem(item: *PyObject) void {
            item.ob_refcnt -= 1; // DECREF
            // TODO: Dealloc if refcnt == 0
        }
    };
}

// ============================================================================
//                              TESTS
// ============================================================================

test "ListImpl - native i64 list" {
    const List = ListImpl(NativeI64ListConfig);

    var list = try List.init(std.testing.allocator);
    defer list.deinit();

    // Test append
    try list.append(10);
    try list.append(20);
    try list.append(30);

    try std.testing.expectEqual(@as(usize, 3), list.size);
    try std.testing.expectEqual(@as(i64, 10), list.get(0).?);
    try std.testing.expectEqual(@as(i64, 20), list.get(1).?);
    try std.testing.expectEqual(@as(i64, 30), list.get(2).?);

    // Test set
    try list.set(1, 99);
    try std.testing.expectEqual(@as(i64, 99), list.get(1).?);

    // Test insert
    try list.insert(1, 15);
    try std.testing.expectEqual(@as(usize, 4), list.size);
    try std.testing.expectEqual(@as(i64, 15), list.get(1).?);

    // Test remove
    const removed = try list.remove(1);
    try std.testing.expectEqual(@as(i64, 15), removed);
    try std.testing.expectEqual(@as(usize, 3), list.size);

    // Test pop
    const popped = list.pop();
    try std.testing.expectEqual(@as(i64, 30), popped.?);
    try std.testing.expectEqual(@as(usize, 2), list.size);
}

test "ListImpl - concat and repeat" {
    const List = ListImpl(NativeI64ListConfig);

    var list1 = try List.init(std.testing.allocator);
    defer list1.deinit();

    try list1.append(1);
    try list1.append(2);

    var list2 = try List.init(std.testing.allocator);
    defer list2.deinit();

    try list2.append(3);
    try list2.append(4);

    // Test concat
    var concatenated = try list1.concat(&list2);
    defer concatenated.deinit();

    try std.testing.expectEqual(@as(usize, 4), concatenated.size);
    try std.testing.expectEqual(@as(i64, 1), concatenated.get(0).?);
    try std.testing.expectEqual(@as(i64, 4), concatenated.get(3).?);

    // Test repeat
    var repeated = try list1.repeat(3);
    defer repeated.deinit();

    try std.testing.expectEqual(@as(usize, 6), repeated.size);
    try std.testing.expectEqual(@as(i64, 1), repeated.get(0).?);
    try std.testing.expectEqual(@as(i64, 2), repeated.get(1).?);
    try std.testing.expectEqual(@as(i64, 1), repeated.get(2).?);
}

test "ListImpl - reverse and sort" {
    const List = ListImpl(NativeI64ListConfig);

    var list = try List.init(std.testing.allocator);
    defer list.deinit();

    try list.append(3);
    try list.append(1);
    try list.append(4);
    try list.append(2);

    // Test reverse
    list.reverse();
    try std.testing.expectEqual(@as(i64, 2), list.get(0).?);
    try std.testing.expectEqual(@as(i64, 4), list.get(1).?);

    // Test sort
    list.sort(struct {
        fn lessThan(a: i64, b: i64) bool {
            return a < b;
        }
    }.lessThan);

    try std.testing.expectEqual(@as(i64, 1), list.get(0).?);
    try std.testing.expectEqual(@as(i64, 2), list.get(1).?);
    try std.testing.expectEqual(@as(i64, 3), list.get(2).?);
    try std.testing.expectEqual(@as(i64, 4), list.get(3).?);
}

test "ListImpl - grow capacity" {
    const List = ListImpl(NativeI64ListConfig);

    var list = try List.init(std.testing.allocator);
    defer list.deinit();

    // Append many items to trigger growth
    var i: i64 = 0;
    while (i < 20) : (i += 1) {
        try list.append(i);
    }

    try std.testing.expectEqual(@as(usize, 20), list.size);

    // Verify all items accessible
    i = 0;
    while (i < 20) : (i += 1) {
        const val = list.get(@intCast(i)).?;
        try std.testing.expectEqual(i, val);
    }
}
