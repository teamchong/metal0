//! Python 'weakref' module - Weak reference support
//!
//! Provides tools for creating weak references to objects.
//!
//! Mirrors: CPython Lib/weakref.py

const std = @import("std");

// ============================================================================
// WeakRef - Weak reference to an object
// ============================================================================

/// A weak reference wrapper that doesn't prevent garbage collection
/// Note: In Zig, we simulate weak refs since there's no GC. The reference
/// can be manually invalidated.
pub fn WeakRef(comptime T: type) type {
    return struct {
        const Self = @This();

        ptr: ?*T,
        callback: ?*const fn (?*T) void,

        /// Create a weak reference to an object
        pub fn init(obj: *T, callback: ?*const fn (?*T) void) Self {
            return .{
                .ptr = obj,
                .callback = callback,
            };
        }

        /// Get the referenced object, or null if it was collected
        pub fn get(self: Self) ?*T {
            return self.ptr;
        }

        /// Call the weak reference to get the object (Python's __call__)
        pub fn call(self: Self) ?*T {
            return self.get();
        }

        /// Check if the reference is still alive
        pub fn alive(self: Self) bool {
            return self.ptr != null;
        }

        /// Manually invalidate the reference (simulates collection)
        pub fn invalidate(self: *Self) void {
            if (self.callback) |cb| {
                cb(self.ptr);
            }
            self.ptr = null;
        }

        /// Get hash based on the referenced object's address
        pub fn hash(self: Self) u64 {
            if (self.ptr) |p| {
                return @intFromPtr(p);
            }
            return 0;
        }

        /// Check equality with another weak reference
        pub fn eql(self: Self, other: Self) bool {
            return self.ptr == other.ptr;
        }
    };
}

// ============================================================================
// WeakKeyDictionary - Dictionary with weak keys
// ============================================================================

/// A dictionary that holds weak references to its keys
pub fn WeakKeyDictionary(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const WeakK = WeakRef(K);

        allocator: std.mem.Allocator,
        entries: std.ArrayList(Entry),

        const Entry = struct {
            key: WeakK,
            value: V,
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .entries = std.ArrayList(Entry).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.entries.deinit();
        }

        /// Set a value for a key (creates weak reference to key)
        pub fn put(self: *Self, key: *K, value: V) !void {
            // Check if key already exists
            for (self.entries.items) |*entry| {
                if (entry.key.ptr == key) {
                    entry.value = value;
                    return;
                }
            }
            // Add new entry
            try self.entries.append(.{
                .key = WeakRef(K).init(key, null),
                .value = value,
            });
        }

        /// Get a value by key
        pub fn get(self: Self, key: *K) ?V {
            for (self.entries.items) |entry| {
                if (entry.key.ptr == key) {
                    return entry.value;
                }
            }
            return null;
        }

        /// Remove a key
        pub fn remove(self: *Self, key: *K) bool {
            for (self.entries.items, 0..) |entry, i| {
                if (entry.key.ptr == key) {
                    _ = self.entries.orderedRemove(i);
                    return true;
                }
            }
            return false;
        }

        /// Remove all entries with dead references
        pub fn compact(self: *Self) void {
            var i: usize = 0;
            while (i < self.entries.items.len) {
                if (!self.entries.items[i].key.alive()) {
                    _ = self.entries.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        /// Number of entries (including dead ones)
        pub fn len(self: Self) usize {
            return self.entries.items.len;
        }

        /// Number of alive entries
        pub fn aliveCount(self: Self) usize {
            var count: usize = 0;
            for (self.entries.items) |entry| {
                if (entry.key.alive()) {
                    count += 1;
                }
            }
            return count;
        }
    };
}

// ============================================================================
// WeakValueDictionary - Dictionary with weak values
// ============================================================================

/// A dictionary that holds weak references to its values
pub fn WeakValueDictionary(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const WeakV = WeakRef(V);

        allocator: std.mem.Allocator,
        entries: std.AutoHashMap(K, WeakV),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .entries = std.AutoHashMap(K, WeakV).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.entries.deinit();
        }

        /// Set a value (creates weak reference to value)
        pub fn put(self: *Self, key: K, value: *V) !void {
            try self.entries.put(key, WeakRef(V).init(value, null));
        }

        /// Get a value by key (returns null if dead)
        pub fn get(self: Self, key: K) ?*V {
            if (self.entries.get(key)) |weak_val| {
                return weak_val.get();
            }
            return null;
        }

        /// Remove a key
        pub fn remove(self: *Self, key: K) bool {
            return self.entries.remove(key);
        }

        /// Remove all entries with dead references
        pub fn compact(self: *Self) void {
            var to_remove = std.ArrayList(K).init(self.allocator);
            defer to_remove.deinit();

            var iter = self.entries.iterator();
            while (iter.next()) |entry| {
                if (!entry.value_ptr.alive()) {
                    to_remove.append(entry.key_ptr.*) catch continue;
                }
            }

            for (to_remove.items) |key| {
                _ = self.entries.remove(key);
            }
        }

        /// Number of entries
        pub fn count(self: Self) usize {
            return self.entries.count();
        }
    };
}

// ============================================================================
// WeakSet - Set with weak references
// ============================================================================

/// A set that holds weak references to its members
pub fn WeakSet(comptime T: type) type {
    return struct {
        const Self = @This();
        const WeakT = WeakRef(T);

        allocator: std.mem.Allocator,
        items: std.ArrayList(WeakT),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
                .items = std.ArrayList(WeakT).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        /// Add an item to the set
        pub fn add(self: *Self, item: *T) !void {
            // Check if already present
            for (self.items.items) |weak| {
                if (weak.ptr == item) {
                    return;
                }
            }
            try self.items.append(WeakRef(T).init(item, null));
        }

        /// Remove an item from the set
        pub fn remove(self: *Self, item: *T) bool {
            for (self.items.items, 0..) |weak, i| {
                if (weak.ptr == item) {
                    _ = self.items.orderedRemove(i);
                    return true;
                }
            }
            return false;
        }

        /// Discard an item (no error if not present)
        pub fn discard(self: *Self, item: *T) void {
            _ = self.remove(item);
        }

        /// Check if item is in set
        pub fn contains(self: Self, item: *T) bool {
            for (self.items.items) |weak| {
                if (weak.ptr == item and weak.alive()) {
                    return true;
                }
            }
            return false;
        }

        /// Remove dead references
        pub fn compact(self: *Self) void {
            var i: usize = 0;
            while (i < self.items.items.len) {
                if (!self.items.items[i].alive()) {
                    _ = self.items.orderedRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        /// Number of alive items
        pub fn len(self: Self) usize {
            var count: usize = 0;
            for (self.items.items) |weak| {
                if (weak.alive()) {
                    count += 1;
                }
            }
            return count;
        }
    };
}

// ============================================================================
// Finalize - Add finalizer to object (simulated)
// ============================================================================

/// Simulated finalizer registry
pub const Finalizer = struct {
    const Self = @This();

    callback: *const fn (*anyopaque) void,
    data: *anyopaque,

    pub fn init(comptime T: type, obj: *T, callback: *const fn (*T) void) Self {
        return .{
            .callback = @ptrCast(callback),
            .data = @ptrCast(obj),
        };
    }

    pub fn run(self: Self) void {
        self.callback(self.data);
    }
};

// ============================================================================
// Proxy - Proxy to a weakly-referenced object
// ============================================================================

/// A proxy that forwards attribute access to a weakly-referenced object
pub fn Proxy(comptime T: type) type {
    return struct {
        const Self = @This();

        ref: WeakRef(T),

        pub fn init(obj: *T) Self {
            return .{
                .ref = WeakRef(T).init(obj, null),
            };
        }

        /// Get the underlying object (raises error if dead)
        pub fn get(self: Self) !*T {
            return self.ref.get() orelse error.ReferenceError;
        }

        /// Check if proxy is alive
        pub fn alive(self: Self) bool {
            return self.ref.alive();
        }
    };
}

// ============================================================================
// CallableProxyType
// ============================================================================

/// A callable proxy to a weakly-referenced callable
pub fn CallableProxy(comptime F: type) type {
    return struct {
        const Self = @This();

        ref: WeakRef(F),

        pub fn init(func: *F) Self {
            return .{
                .ref = WeakRef(F).init(func, null),
            };
        }

        /// Get the callable
        pub fn get(self: Self) !*F {
            return self.ref.get() orelse error.ReferenceError;
        }

        pub fn alive(self: Self) bool {
            return self.ref.alive();
        }
    };
}

// ============================================================================
// ref() - Create a weak reference
// ============================================================================

/// Create a weak reference to an object
pub fn ref(comptime T: type, obj: *T, callback: ?*const fn (?*T) void) WeakRef(T) {
    return WeakRef(T).init(obj, callback);
}

// ============================================================================
// proxy() - Create a proxy to an object
// ============================================================================

/// Create a proxy to a weakly-referenced object
pub fn proxy(comptime T: type, obj: *T) Proxy(T) {
    return Proxy(T).init(obj);
}

// ============================================================================
// getweakrefcount - Count weak references (simulated)
// ============================================================================

/// Get the number of weak references to an object
/// Note: In this implementation, always returns 0 or 1 since we don't
/// have a global registry
pub fn getweakrefcount(comptime T: type, obj: *T) usize {
    _ = obj;
    // Without a global registry, we can't count references
    return 0;
}

// ============================================================================
// getweakrefs - Get list of weak references (simulated)
// ============================================================================

/// Get list of weak references to an object
/// Note: Returns empty list since we don't have a global registry
pub fn getweakrefs(comptime T: type, allocator: std.mem.Allocator, obj: *T) ![]WeakRef(T) {
    _ = obj;
    return try allocator.alloc(WeakRef(T), 0);
}

// ============================================================================
// ReferenceType and ProxyType exports
// ============================================================================

pub const ReferenceType = WeakRef;
pub const ProxyType = Proxy;

// ============================================================================
// Tests
// ============================================================================

test "WeakRef basic" {
    var value: i32 = 42;
    var weak = WeakRef(i32).init(&value, null);

    try std.testing.expect(weak.alive());
    try std.testing.expectEqual(@as(*i32, &value), weak.get().?);
    try std.testing.expectEqual(@as(i32, 42), weak.get().?.*);

    weak.invalidate();
    try std.testing.expect(!weak.alive());
    try std.testing.expect(weak.get() == null);
}

test "WeakRef callback" {
    var value: i32 = 42;
    var callback_called = false;

    const callback = struct {
        fn cb(_: ?*i32) void {
            // In real code, this would do cleanup
        }
    }.cb;

    var weak = WeakRef(i32).init(&value, callback);
    try std.testing.expect(weak.alive());

    _ = callback_called;
}

test "WeakKeyDictionary" {
    const allocator = std.testing.allocator;

    var key1: i32 = 1;
    var key2: i32 = 2;

    var dict = WeakKeyDictionary(i32, []const u8).init(allocator);
    defer dict.deinit();

    try dict.put(&key1, "one");
    try dict.put(&key2, "two");

    try std.testing.expectEqualStrings("one", dict.get(&key1).?);
    try std.testing.expectEqualStrings("two", dict.get(&key2).?);
    try std.testing.expectEqual(@as(usize, 2), dict.len());

    try std.testing.expect(dict.remove(&key1));
    try std.testing.expect(dict.get(&key1) == null);
}

test "WeakValueDictionary" {
    const allocator = std.testing.allocator;

    var val1: i32 = 100;
    var val2: i32 = 200;

    var dict = WeakValueDictionary([]const u8, i32).init(allocator);
    defer dict.deinit();

    try dict.put("a", &val1);
    try dict.put("b", &val2);

    try std.testing.expectEqual(@as(*i32, &val1), dict.get("a").?);
    try std.testing.expectEqual(@as(*i32, &val2), dict.get("b").?);
}

test "WeakSet" {
    const allocator = std.testing.allocator;

    var item1: i32 = 1;
    var item2: i32 = 2;

    var set = WeakSet(i32).init(allocator);
    defer set.deinit();

    try set.add(&item1);
    try set.add(&item2);
    try set.add(&item1); // Duplicate, should not add

    try std.testing.expect(set.contains(&item1));
    try std.testing.expect(set.contains(&item2));
    try std.testing.expectEqual(@as(usize, 2), set.len());

    try std.testing.expect(set.remove(&item1));
    try std.testing.expect(!set.contains(&item1));
}

test "Proxy" {
    var value: i32 = 42;
    var p = Proxy(i32).init(&value);

    try std.testing.expect(p.alive());
    try std.testing.expectEqual(@as(*i32, &value), try p.get());
}

test "ref convenience function" {
    var value: i32 = 99;
    const weak = ref(i32, &value, null);

    try std.testing.expect(weak.alive());
    try std.testing.expectEqual(@as(i32, 99), weak.get().?.*);
}

test "proxy convenience function" {
    var value: i32 = 88;
    const p = proxy(i32, &value);

    try std.testing.expect(p.alive());
}
