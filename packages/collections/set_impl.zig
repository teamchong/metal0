/// Generic set implementation - REUSES dict_impl!
///
/// Key insight: Set is just a dict with void values!
/// This allows us to reuse all of dict_impl's optimizations:
/// - Hash table with linear probing
/// - 75% load factor
/// - Tombstone deletion
/// - Zero code duplication!

const std = @import("std");
const dict_impl = @import("dict_impl.zig");

/// Generic set - REUSES dict_impl!
///
/// Config must provide:
/// - KeyType: type
/// - hashKey(key: KeyType) u64
/// - keysEqual(a: KeyType, b: KeyType) bool
/// - retainKey(key: KeyType) KeyType
/// - releaseKey(key: KeyType) void
pub fn SetImpl(comptime Config: type) type {
    // Set is dict with void values!
    const DictConfig = struct {
        pub const KeyType = Config.KeyType;
        pub const ValueType = void; // ← KEY INSIGHT!

        pub fn hashKey(key: Config.KeyType) u64 {
            return Config.hashKey(key);
        }

        pub fn keysEqual(a: Config.KeyType, b: Config.KeyType) bool {
            return Config.keysEqual(a, b);
        }

        pub fn retainKey(key: Config.KeyType) Config.KeyType {
            return Config.retainKey(key);
        }

        pub fn releaseKey(key: Config.KeyType) void {
            Config.releaseKey(key);
        }

        pub fn retainValue(_: void) void {}
        pub fn releaseValue(_: void) void {}
    };

    const DictCore = dict_impl.DictImpl(DictConfig);

    return struct {
        const Self = @This();

        dict: DictCore, // Reuse dict implementation!

        /// Initialize empty set
        pub fn init(allocator: std.mem.Allocator) !Self {
            return Self{
                .dict = try DictCore.init(allocator),
            };
        }

        /// Add element to set
        pub fn add(self: *Self, key: Config.KeyType) !void {
            try self.dict.set(key, {}); // Value is void!
        }

        /// Check if set contains element
        pub fn contains(self: *Self, key: Config.KeyType) bool {
            return self.dict.get(key) != null;
        }

        /// Remove element from set
        pub fn remove(self: *Self, key: Config.KeyType) bool {
            return self.dict.delete(key);
        }

        /// Discard element (no error if missing)
        pub fn discard(self: *Self, key: Config.KeyType) void {
            _ = self.dict.delete(key);
        }

        /// Get number of elements
        pub fn size(self: *const Self) usize {
            return self.dict.size;
        }

        /// Clear all elements
        pub fn clear(self: *Self) void {
            self.dict.clear();
        }

        /// Check if set is empty
        pub fn isEmpty(self: *const Self) bool {
            return self.dict.size == 0;
        }

        /// Get iterator over set elements
        pub fn iterator(self: *const Self) Iterator {
            return Iterator{
                .dict_iter = self.dict.iterator(),
            };
        }

        /// Free all memory
        pub fn deinit(self: *Self) void {
            self.dict.deinit();
        }

        /// Iterator (wraps dict iterator)
        pub const Iterator = struct {
            dict_iter: DictCore.Iterator,

            pub fn next(self: *Iterator) ?Config.KeyType {
                if (self.dict_iter.next()) |entry| {
                    return entry.key;
                }
                return null;
            }
        };

        // Set operations

        /// Union: self ∪ other
        pub fn unionWith(self: *Self, other: *const Self) !void {
            var iter = other.iterator();
            while (iter.next()) |key| {
                try self.add(key);
            }
        }

        /// Intersection: self ∩ other
        pub fn intersectionWith(self: *Self, other: *const Self) !Self {
            var result = try Self.init(self.dict.allocator);
            var iter = self.iterator();
            while (iter.next()) |key| {
                if (other.contains(key)) {
                    try result.add(key);
                }
            }
            return result;
        }

        /// Difference: self \ other
        pub fn differenceWith(self: *Self, other: *const Self) !Self {
            var result = try Self.init(self.dict.allocator);
            var iter = self.iterator();
            while (iter.next()) |key| {
                if (!other.contains(key)) {
                    try result.add(key);
                }
            }
            return result;
        }

        /// Symmetric difference: (self \ other) ∪ (other \ self)
        pub fn symmetricDifferenceWith(self: *Self, other: *const Self) !Self {
            var result = try Self.init(self.dict.allocator);

            // Add elements in self but not other
            var iter1 = self.iterator();
            while (iter1.next()) |key| {
                if (!other.contains(key)) {
                    try result.add(key);
                }
            }

            // Add elements in other but not self
            var iter2 = other.iterator();
            while (iter2.next()) |key| {
                if (!self.contains(key)) {
                    try result.add(key);
                }
            }

            return result;
        }

        /// Check if self is subset of other
        pub fn isSubsetOf(self: *const Self, other: *const Self) bool {
            if (self.size() > other.size()) return false;

            var iter = self.iterator();
            while (iter.next()) |key| {
                if (!other.contains(key)) return false;
            }
            return true;
        }

        /// Check if self is superset of other
        pub fn isSupersetOf(self: *const Self, other: *const Self) bool {
            return other.isSubsetOf(self);
        }

        /// Check if sets are disjoint (no common elements)
        pub fn isDisjoint(self: *const Self, other: *const Self) bool {
            var iter = self.iterator();
            while (iter.next()) |key| {
                if (other.contains(key)) return false;
            }
            return true;
        }
    };
}

// Example configs

/// Native integer set (no refcounting)
pub const NativeIntSetConfig = struct {
    pub const KeyType = i64;

    pub fn hashKey(key: i64) u64 {
        // Simple integer hash (from dict_impl's NativeIntDictConfig)
        return @bitCast(key);
    }

    pub fn keysEqual(a: i64, b: i64) bool {
        return a == b;
    }

    pub fn retainKey(key: i64) i64 {
        return key;
    }

    pub fn releaseKey(_: i64) void {}
};

/// Native string set (no refcounting, but needs to handle string ownership)
pub fn NativeStringSetConfig(comptime ownership: enum { borrowed, owned }) type {
    return struct {
        pub const KeyType = []const u8;

        pub fn hashKey(key: []const u8) u64 {
            return std.hash.Wyhash.hash(0, key);
        }

        pub fn keysEqual(a: []const u8, b: []const u8) bool {
            return std.mem.eql(u8, a, b);
        }

        pub fn retainKey(key: []const u8) []const u8 {
            return key; // Caller owns string
        }

        pub fn releaseKey(key: []const u8) void {
            if (ownership == .owned) {
                // Would free string here if owned
                _ = key;
            }
        }
    };
}

// Tests
test "set basic operations" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const IntSet = SetImpl(NativeIntSetConfig);
    var set = try IntSet.init(allocator);
    defer set.deinit();

    // Add elements
    try set.add(1);
    try set.add(2);
    try set.add(3);

    try testing.expectEqual(@as(usize, 3), set.size());
    try testing.expect(set.contains(1));
    try testing.expect(set.contains(2));
    try testing.expect(set.contains(3));
    try testing.expect(!set.contains(4));

    // Remove element
    try testing.expect(set.remove(2));
    try testing.expectEqual(@as(usize, 2), set.size());
    try testing.expect(!set.contains(2));

    // Remove non-existent
    try testing.expect(!set.remove(99));
}

test "set operations" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const IntSet = SetImpl(NativeIntSetConfig);

    var set1 = try IntSet.init(allocator);
    defer set1.deinit();
    try set1.add(1);
    try set1.add(2);
    try set1.add(3);

    var set2 = try IntSet.init(allocator);
    defer set2.deinit();
    try set2.add(2);
    try set2.add(3);
    try set2.add(4);

    // Union
    try set1.unionWith(&set2);
    try testing.expectEqual(@as(usize, 4), set1.size());
    try testing.expect(set1.contains(4));

    // Intersection
    var set3 = try IntSet.init(allocator);
    defer set3.deinit();
    try set3.add(1);
    try set3.add(2);

    var set4 = try IntSet.init(allocator);
    defer set4.deinit();
    try set4.add(2);
    try set4.add(3);

    var intersection = try set3.intersectionWith(&set4);
    defer intersection.deinit();

    try testing.expectEqual(@as(usize, 1), intersection.size());
    try testing.expect(intersection.contains(2));
}

test "set subset/superset" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const IntSet = SetImpl(NativeIntSetConfig);

    var set1 = try IntSet.init(allocator);
    defer set1.deinit();
    try set1.add(1);
    try set1.add(2);

    var set2 = try IntSet.init(allocator);
    defer set2.deinit();
    try set2.add(1);
    try set2.add(2);
    try set2.add(3);

    try testing.expect(set1.isSubsetOf(&set2));
    try testing.expect(!set1.isSupersetOf(&set2));
    try testing.expect(set2.isSupersetOf(&set1));
    try testing.expect(!set2.isSubsetOf(&set1));
}

test "set disjoint" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const IntSet = SetImpl(NativeIntSetConfig);

    var set1 = try IntSet.init(allocator);
    defer set1.deinit();
    try set1.add(1);
    try set1.add(2);

    var set2 = try IntSet.init(allocator);
    defer set2.deinit();
    try set2.add(3);
    try set2.add(4);

    try testing.expect(set1.isDisjoint(&set2));

    try set2.add(2);
    try testing.expect(!set1.isDisjoint(&set2));
}
