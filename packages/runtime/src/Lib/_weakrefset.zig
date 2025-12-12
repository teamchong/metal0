//! CPython source: Lib/_weakrefset.py
//!
//! Provides WeakSet implementation.
//!
//! Mirrors: CPython Lib/_weakrefset.py

const std = @import("std");

// ============================================================================
// WeakRef - Simulated weak reference
// ============================================================================

/// Simulated weak reference (Zig doesn't have native weak refs)
pub fn WeakRef(comptime T: type) type {
    return struct {
        const Self = @This();

        ptr: ?*T,
        callback: ?*const fn (?*T) void,

        pub fn init(obj: *T, callback: ?*const fn (?*T) void) Self {
            return .{
                .ptr = obj,
                .callback = callback,
            };
        }

        /// Dereference the weak reference
        pub fn deref(self: Self) ?*T {
            return self.ptr;
        }

        /// Check if reference is still alive
        pub fn isAlive(self: Self) bool {
            return self.ptr != null;
        }

        /// Clear the reference (called when object is destroyed)
        pub fn clear(self: *Self) void {
            if (self.callback) |cb| {
                cb(self.ptr);
            }
            self.ptr = null;
        }

        /// Get hash for the referenced object
        pub fn hash(self: Self) u64 {
            if (self.ptr) |p| {
                return @intFromPtr(p);
            }
            return 0;
        }
    };
}

// ============================================================================
// WeakSet
// ============================================================================

/// Set that holds weak references to objects
pub fn WeakSet(comptime T: type) type {
    return struct {
        const Self = @This();
        const Ref = WeakRef(T);

        allocator: std.mem.Allocator,
        data: std.AutoHashMap(usize, Ref),
        pending_removals: std.ArrayList(usize),
        iterating: bool,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .data = std.AutoHashMap(usize, Ref).init(allocator),
                .pending_removals = .{},
                .iterating = false,
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
            self.pending_removals.deinit(self.allocator);
        }

        /// Remove dead references
        fn commitRemovals(self: *Self) void {
            while (self.pending_removals.popOrNull()) |key| {
                _ = self.data.remove(key);
            }
        }

        /// Add an element
        pub fn add(self: *Self, item: *T) !void {
            if (!self.iterating) {
                self.commitRemovals();
            }

            const key = @intFromPtr(item);
            const ref = Ref.init(item, null);
            try self.data.put(key, ref);
        }

        /// Remove an element
        pub fn remove(self: *Self, item: *T) !void {
            const key = @intFromPtr(item);

            if (self.iterating) {
                try self.pending_removals.append(self.allocator, key);
            } else {
                self.commitRemovals();
                _ = self.data.remove(key);
            }
        }

        /// Discard an element (no error if not present)
        pub fn discard(self: *Self, item: *T) void {
            self.remove(item) catch {};
        }

        /// Check if element is in set
        pub fn contains(self: *Self, item: *T) bool {
            const key = @intFromPtr(item);
            if (self.data.get(key)) |ref| {
                return ref.isAlive();
            }
            return false;
        }

        /// Get number of live elements
        pub fn len(self: *Self) usize {
            var count: usize = 0;
            var it = self.data.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.isAlive()) {
                    count += 1;
                }
            }
            return count;
        }

        /// Check if set is empty
        pub fn isEmpty(self: *Self) bool {
            return self.len() == 0;
        }

        /// Clear all elements
        pub fn clear(self: *Self) void {
            self.data.clearRetainingCapacity();
            self.pending_removals.clearRetainingCapacity();
        }

        /// Pop an arbitrary element
        pub fn pop(self: *Self) ?*T {
            if (!self.iterating) {
                self.commitRemovals();
            }

            var it = self.data.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.isAlive()) {
                    const result = entry.value_ptr.deref();
                    _ = self.data.remove(entry.key_ptr.*);
                    return result;
                }
            }
            return null;
        }

        /// Create a copy of the set
        pub fn copy(self: *Self) !Self {
            var new_set = Self.init(self.allocator);
            var it = self.data.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.deref()) |obj| {
                    try new_set.add(obj);
                }
            }
            return new_set;
        }

        /// Iterator over live references
        pub const Iterator = struct {
            parent: *Self,
            inner: std.AutoHashMap(usize, Ref).Iterator,

            pub fn next(self: *Iterator) ?*T {
                while (self.inner.next()) |entry| {
                    if (entry.value_ptr.deref()) |obj| {
                        return obj;
                    }
                }
                self.parent.iterating = false;
                return null;
            }
        };

        /// Get iterator
        pub fn iterator(self: *Self) Iterator {
            if (!self.iterating) {
                self.commitRemovals();
            }
            self.iterating = true;
            return .{
                .parent = self,
                .inner = self.data.iterator(),
            };
        }

        // ====================================================================
        // Set operations
        // ====================================================================

        /// Check if subset
        pub fn isSubset(self: *Self, other: *Self) bool {
            var it = self.iterator();
            while (it.next()) |item| {
                if (!other.contains(item)) {
                    return false;
                }
            }
            return true;
        }

        /// Check if superset
        pub fn isSuperset(self: *Self, other: *Self) bool {
            return other.isSubset(self);
        }

        /// Check if disjoint
        pub fn isDisjoint(self: *Self, other: *Self) bool {
            var it = self.iterator();
            while (it.next()) |item| {
                if (other.contains(item)) {
                    return false;
                }
            }
            return true;
        }

        /// Union with another set
        pub fn @"union"(self: *Self, other: *Self) !Self {
            var result = try self.copy();
            var it = other.iterator();
            while (it.next()) |item| {
                try result.add(item);
            }
            return result;
        }

        /// Intersection with another set
        pub fn intersection(self: *Self, other: *Self) !Self {
            var result = Self.init(self.allocator);
            var it = self.iterator();
            while (it.next()) |item| {
                if (other.contains(item)) {
                    try result.add(item);
                }
            }
            return result;
        }

        /// Difference with another set
        pub fn difference(self: *Self, other: *Self) !Self {
            var result = Self.init(self.allocator);
            var it = self.iterator();
            while (it.next()) |item| {
                if (!other.contains(item)) {
                    try result.add(item);
                }
            }
            return result;
        }

        /// Symmetric difference with another set
        pub fn symmetricDifference(self: *Self, other: *Self) !Self {
            var result = Self.init(self.allocator);
            var it = self.iterator();
            while (it.next()) |item| {
                if (!other.contains(item)) {
                    try result.add(item);
                }
            }
            var it2 = other.iterator();
            while (it2.next()) |item| {
                if (!self.contains(item)) {
                    try result.add(item);
                }
            }
            return result;
        }

        // ====================================================================
        // In-place operations
        // ====================================================================

        /// Update with union
        pub fn update(self: *Self, other: *Self) !void {
            var it = other.iterator();
            while (it.next()) |item| {
                try self.add(item);
            }
        }

        /// Update with intersection
        pub fn intersectionUpdate(self: *Self, other: *Self) void {
            var to_remove: std.ArrayList(usize) = .{};
            defer to_remove.deinit(self.allocator);

            var it = self.data.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.deref()) |obj| {
                    if (!other.contains(obj)) {
                        to_remove.append(self.allocator, entry.key_ptr.*) catch continue;
                    }
                }
            }

            for (to_remove.items) |key| {
                _ = self.data.remove(key);
            }
        }

        /// Update with difference
        pub fn differenceUpdate(self: *Self, other: *Self) void {
            var it = other.iterator();
            while (it.next()) |item| {
                self.discard(item);
            }
        }

        /// Update with symmetric difference
        pub fn symmetricDifferenceUpdate(self: *Self, other: *Self) !void {
            var it = other.iterator();
            while (it.next()) |item| {
                if (self.contains(item)) {
                    self.discard(item);
                } else {
                    try self.add(item);
                }
            }
        }
    };
}

// ============================================================================
// WeakKeyDictionary helper
// ============================================================================

/// Dictionary with weak keys
pub fn WeakKeyDictionary(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        data: std.AutoHashMap(usize, V),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .data = std.AutoHashMap(usize, V).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn get(self: *Self, key: *K) ?V {
            return self.data.get(@intFromPtr(key));
        }

        pub fn put(self: *Self, key: *K, value: V) !void {
            try self.data.put(@intFromPtr(key), value);
        }

        pub fn remove(self: *Self, key: *K) bool {
            return self.data.remove(@intFromPtr(key));
        }

        pub fn contains(self: *Self, key: *K) bool {
            return self.data.contains(@intFromPtr(key));
        }

        pub fn len(self: *Self) usize {
            return self.data.count();
        }
    };
}

// ============================================================================
// WeakValueDictionary helper
// ============================================================================

/// Dictionary with weak values
pub fn WeakValueDictionary(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const Ref = WeakRef(V);

        allocator: std.mem.Allocator,
        data: std.AutoHashMap(K, Ref),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .data = std.AutoHashMap(K, Ref).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn get(self: *Self, key: K) ?*V {
            if (self.data.get(key)) |ref| {
                return ref.deref();
            }
            return null;
        }

        pub fn put(self: *Self, key: K, value: *V) !void {
            const ref = Ref.init(value, null);
            try self.data.put(key, ref);
        }

        pub fn remove(self: *Self, key: K) bool {
            return self.data.remove(key);
        }

        pub fn contains(self: *Self, key: K) bool {
            if (self.data.get(key)) |ref| {
                return ref.isAlive();
            }
            return false;
        }

        pub fn len(self: *Self) usize {
            var count: usize = 0;
            var it = self.data.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.isAlive()) {
                    count += 1;
                }
            }
            return count;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "WeakRef basic" {
    var obj: u32 = 42;
    var ref = WeakRef(u32).init(&obj, null);

    try std.testing.expect(ref.isAlive());
    try std.testing.expectEqual(&obj, ref.deref().?);
}

test "WeakRef clear" {
    var obj: u32 = 42;
    var ref = WeakRef(u32).init(&obj, null);

    ref.clear();
    try std.testing.expect(!ref.isAlive());
    try std.testing.expect(ref.deref() == null);
}

test "WeakSet init and deinit" {
    const allocator = std.testing.allocator;
    var set = WeakSet(u32).init(allocator);
    defer set.deinit();

    try std.testing.expect(set.isEmpty());
}

test "WeakSet add and contains" {
    const allocator = std.testing.allocator;
    var set = WeakSet(u32).init(allocator);
    defer set.deinit();

    var obj: u32 = 42;
    try set.add(&obj);

    try std.testing.expect(set.contains(&obj));
    try std.testing.expectEqual(@as(usize, 1), set.len());
}

test "WeakSet remove" {
    const allocator = std.testing.allocator;
    var set = WeakSet(u32).init(allocator);
    defer set.deinit();

    var obj: u32 = 42;
    try set.add(&obj);
    try set.remove(&obj);

    try std.testing.expect(!set.contains(&obj));
    try std.testing.expect(set.isEmpty());
}

test "WeakSet clear" {
    const allocator = std.testing.allocator;
    var set = WeakSet(u32).init(allocator);
    defer set.deinit();

    var obj1: u32 = 1;
    var obj2: u32 = 2;
    try set.add(&obj1);
    try set.add(&obj2);

    set.clear();
    try std.testing.expect(set.isEmpty());
}

test "WeakKeyDictionary basic" {
    const allocator = std.testing.allocator;
    var dict = WeakKeyDictionary(u32, []const u8).init(allocator);
    defer dict.deinit();

    var key: u32 = 42;
    try dict.put(&key, "value");

    try std.testing.expectEqualStrings("value", dict.get(&key).?);
}

test "WeakValueDictionary basic" {
    const allocator = std.testing.allocator;
    var dict = WeakValueDictionary(u32, u32).init(allocator);
    defer dict.deinit();

    var val: u32 = 42;
    try dict.put(1, &val);

    try std.testing.expectEqual(&val, dict.get(1).?);
}
