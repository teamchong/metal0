/// Set operations runtime helpers
/// Extracted from codegen to prevent comptime explosion from repeated @hasDecl/@TypeOf checks
///
/// Problem: Each set.remove(), set.discard(), set.pop() emitted inline @hasDecl checks
/// causing O(n²) monomorphization when many set operations exist in a single file.
///
/// Solution: These helpers are compiled once per key type, called N times.
const std = @import("std");

pub const SetOpsError = error{
    KeyError,
    OutOfMemory,
};

/// Generic set operations that work with both AutoHashMap and ArrayHashMap
/// Monomorphizes once per K type, not once per call site
pub fn SetOps(comptime K: type) type {
    return struct {
        const Self = @This();

        // Type alias for the set type (AutoHashMap(K, void))
        pub const Set = std.AutoHashMap(K, void);

        /// Remove element from set, returns true if removed, false if not present
        /// Works with both AutoHashMap (.remove) and ArrayHashMap (.swapRemove)
        pub fn removeKey(set: anytype, key: K) bool {
            // Compile-time dispatch - resolved once per set type
            if (@hasDecl(@TypeOf(set.*), "swapRemove")) {
                return set.swapRemove(key);
            } else {
                return set.remove(key);
            }
        }

        /// Remove element, raise KeyError if not present (Python set.remove semantics)
        pub fn remove(set: anytype, key: K) SetOpsError!void {
            if (!removeKey(set, key)) {
                return SetOpsError.KeyError;
            }
        }

        /// Remove element if present, no error if missing (Python set.discard semantics)
        pub fn discard(set: anytype, key: K) void {
            _ = removeKey(set, key);
        }

        /// Pop and return arbitrary element, raise KeyError if empty
        pub fn pop(set: anytype) SetOpsError!K {
            var iter = set.iterator();
            const entry = iter.next() orelse return SetOpsError.KeyError;
            const key = entry.key_ptr.*;
            _ = removeKey(set, key);
            return key;
        }

        /// Create a shallow copy of the set
        pub fn copy(allocator: std.mem.Allocator, set: anytype) SetOpsError!Set {
            var result = Set.init(allocator);
            var iter = set.iterator();
            while (iter.next()) |entry| {
                try result.put(entry.key_ptr.*, {});
            }
            return result;
        }

        /// Check if set is subset of other
        pub fn isSubset(set: anytype, other: anytype) bool {
            var iter = set.iterator();
            while (iter.next()) |entry| {
                if (!other.contains(entry.key_ptr.*)) return false;
            }
            return true;
        }

        /// Check if set is superset of other
        pub fn isSuperset(set: anytype, other: anytype) bool {
            var iter = other.iterator();
            while (iter.next()) |entry| {
                if (!set.contains(entry.key_ptr.*)) return false;
            }
            return true;
        }

        /// Check if sets are disjoint (no common elements)
        pub fn isDisjoint(set: anytype, other: anytype) bool {
            var iter = set.iterator();
            while (iter.next()) |entry| {
                if (other.contains(entry.key_ptr.*)) return false;
            }
            return true;
        }

        /// Create union of two sets
        pub fn setUnion(allocator: std.mem.Allocator, set: anytype, other: anytype) SetOpsError!Set {
            var result = Set.init(allocator);
            // Add all from set
            var iter1 = set.iterator();
            while (iter1.next()) |entry| {
                try result.put(entry.key_ptr.*, {});
            }
            // Add all from other
            var iter2 = other.iterator();
            while (iter2.next()) |entry| {
                try result.put(entry.key_ptr.*, {});
            }
            return result;
        }

        /// Create intersection of two sets
        pub fn intersection(allocator: std.mem.Allocator, set: anytype, other: anytype) SetOpsError!Set {
            var result = Set.init(allocator);
            var iter = set.iterator();
            while (iter.next()) |entry| {
                if (other.contains(entry.key_ptr.*)) {
                    try result.put(entry.key_ptr.*, {});
                }
            }
            return result;
        }

        /// Create difference of two sets (elements in set but not in other)
        pub fn difference(allocator: std.mem.Allocator, set: anytype, other: anytype) SetOpsError!Set {
            var result = Set.init(allocator);
            var iter = set.iterator();
            while (iter.next()) |entry| {
                if (!other.contains(entry.key_ptr.*)) {
                    try result.put(entry.key_ptr.*, {});
                }
            }
            return result;
        }

        /// Create symmetric difference of two sets (elements in either but not both)
        pub fn symmetricDifference(allocator: std.mem.Allocator, set: anytype, other: anytype) SetOpsError!Set {
            var result = Set.init(allocator);
            // Add elements from set that are not in other
            var iter1 = set.iterator();
            while (iter1.next()) |entry| {
                if (!other.contains(entry.key_ptr.*)) {
                    try result.put(entry.key_ptr.*, {});
                }
            }
            // Add elements from other that are not in set
            var iter2 = other.iterator();
            while (iter2.next()) |entry| {
                if (!set.contains(entry.key_ptr.*)) {
                    try result.put(entry.key_ptr.*, {});
                }
            }
            return result;
        }

        /// Update set in-place with intersection
        pub fn intersectionUpdate(allocator: std.mem.Allocator, set: anytype, other: anytype) SetOpsError!void {
            // Collect keys to remove (can't modify while iterating)
            var to_remove = std.ArrayList(K).init(allocator);
            defer to_remove.deinit();

            var iter = set.iterator();
            while (iter.next()) |entry| {
                if (!other.contains(entry.key_ptr.*)) {
                    try to_remove.append(entry.key_ptr.*);
                }
            }

            for (to_remove.items) |key| {
                _ = removeKey(set, key);
            }
        }

        /// Update set in-place with difference
        pub fn differenceUpdate(set: anytype, other: anytype) void {
            var iter = other.iterator();
            while (iter.next()) |entry| {
                _ = removeKey(set, entry.key_ptr.*);
            }
        }

        /// Update set in-place with symmetric difference
        pub fn symmetricDifferenceUpdate(allocator: std.mem.Allocator, set: anytype, other: anytype) SetOpsError!void {
            // Collect keys to remove (in both sets) and keys to add (in other but not set)
            var to_remove = std.ArrayList(K).init(allocator);
            defer to_remove.deinit();
            var to_add = std.ArrayList(K).init(allocator);
            defer to_add.deinit();

            // Find elements in set that are in other (to remove)
            var iter1 = set.iterator();
            while (iter1.next()) |entry| {
                if (other.contains(entry.key_ptr.*)) {
                    try to_remove.append(entry.key_ptr.*);
                }
            }

            // Find elements in other that are not in set (to add)
            var iter2 = other.iterator();
            while (iter2.next()) |entry| {
                if (!set.contains(entry.key_ptr.*)) {
                    try to_add.append(entry.key_ptr.*);
                }
            }

            // Apply changes
            for (to_remove.items) |key| {
                _ = removeKey(set, key);
            }
            for (to_add.items) |key| {
                try set.put(key, {});
            }
        }
    };
}

// Pre-instantiated for common types to avoid repeated monomorphization
pub const IntSetOps = SetOps(i64);
pub const StringSetOps = SetOps([]const u8);

// Tests
test "SetOps.remove" {
    const allocator = std.testing.allocator;
    var set = std.AutoHashMap(i64, void).init(allocator);
    defer set.deinit();

    try set.put(1, {});
    try set.put(2, {});
    try set.put(3, {});

    try IntSetOps.remove(&set, 2);
    try std.testing.expect(!set.contains(2));
    try std.testing.expect(set.contains(1));
    try std.testing.expect(set.contains(3));

    // Remove non-existent key should error
    try std.testing.expectError(SetOpsError.KeyError, IntSetOps.remove(&set, 99));
}

test "SetOps.discard" {
    const allocator = std.testing.allocator;
    var set = std.AutoHashMap(i64, void).init(allocator);
    defer set.deinit();

    try set.put(1, {});
    try set.put(2, {});

    IntSetOps.discard(&set, 2);
    try std.testing.expect(!set.contains(2));

    // Discard non-existent key should not error
    IntSetOps.discard(&set, 99);
}

test "SetOps.pop" {
    const allocator = std.testing.allocator;
    var set = std.AutoHashMap(i64, void).init(allocator);
    defer set.deinit();

    try set.put(1, {});
    try set.put(2, {});

    const popped = try IntSetOps.pop(&set);
    try std.testing.expect(popped == 1 or popped == 2);
    try std.testing.expectEqual(@as(usize, 1), set.count());

    _ = try IntSetOps.pop(&set);
    try std.testing.expectEqual(@as(usize, 0), set.count());

    // Pop from empty set should error
    try std.testing.expectError(SetOpsError.KeyError, IntSetOps.pop(&set));
}

test "SetOps.copy" {
    const allocator = std.testing.allocator;
    var set = std.AutoHashMap(i64, void).init(allocator);
    defer set.deinit();

    try set.put(1, {});
    try set.put(2, {});
    try set.put(3, {});

    var copy = try IntSetOps.copy(allocator, &set);
    defer copy.deinit();

    try std.testing.expectEqual(@as(usize, 3), copy.count());
    try std.testing.expect(copy.contains(1));
    try std.testing.expect(copy.contains(2));
    try std.testing.expect(copy.contains(3));
}

test "SetOps.setUnion" {
    const allocator = std.testing.allocator;
    var a = std.AutoHashMap(i64, void).init(allocator);
    defer a.deinit();
    var b = std.AutoHashMap(i64, void).init(allocator);
    defer b.deinit();

    try a.put(1, {});
    try a.put(2, {});
    try b.put(2, {});
    try b.put(3, {});

    var result = try IntSetOps.setUnion(allocator, &a, &b);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.count());
    try std.testing.expect(result.contains(1));
    try std.testing.expect(result.contains(2));
    try std.testing.expect(result.contains(3));
}

test "SetOps.intersection" {
    const allocator = std.testing.allocator;
    var a = std.AutoHashMap(i64, void).init(allocator);
    defer a.deinit();
    var b = std.AutoHashMap(i64, void).init(allocator);
    defer b.deinit();

    try a.put(1, {});
    try a.put(2, {});
    try a.put(3, {});
    try b.put(2, {});
    try b.put(3, {});
    try b.put(4, {});

    var result = try IntSetOps.intersection(allocator, &a, &b);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.count());
    try std.testing.expect(result.contains(2));
    try std.testing.expect(result.contains(3));
}

test "SetOps.difference" {
    const allocator = std.testing.allocator;
    var a = std.AutoHashMap(i64, void).init(allocator);
    defer a.deinit();
    var b = std.AutoHashMap(i64, void).init(allocator);
    defer b.deinit();

    try a.put(1, {});
    try a.put(2, {});
    try a.put(3, {});
    try b.put(2, {});

    var result = try IntSetOps.difference(allocator, &a, &b);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.count());
    try std.testing.expect(result.contains(1));
    try std.testing.expect(result.contains(3));
}

test "SetOps.symmetricDifference" {
    const allocator = std.testing.allocator;
    var a = std.AutoHashMap(i64, void).init(allocator);
    defer a.deinit();
    var b = std.AutoHashMap(i64, void).init(allocator);
    defer b.deinit();

    try a.put(1, {});
    try a.put(2, {});
    try b.put(2, {});
    try b.put(3, {});

    var result = try IntSetOps.symmetricDifference(allocator, &a, &b);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.count());
    try std.testing.expect(result.contains(1));
    try std.testing.expect(result.contains(3));
}
