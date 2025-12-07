/// hashtable - Generic Hash Table Implementation
/// Mirrors cpython/Python/hashtable.c
///
/// This module provides a generic hash table with:
/// - Configurable hash and compare functions
/// - Automatic resizing
/// - Iterator support
/// - Statistics tracking

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Constants
// ============================================================================

/// Initial hash table size (must be power of 2)
pub const INITIAL_SIZE: usize = 16;

/// Maximum load factor before resize (75%)
pub const MAX_LOAD_FACTOR: f64 = 0.75;

/// Minimum load factor before shrink (25%)
pub const MIN_LOAD_FACTOR: f64 = 0.25;

/// Minimum size to shrink to
pub const MIN_SIZE: usize = 16;

// ============================================================================
// Hash Functions
// ============================================================================

/// FNV-1a hash for bytes
pub fn fnvHash(data: []const u8) u64 {
    const FNV_OFFSET: u64 = 0xcbf29ce484222325;
    const FNV_PRIME: u64 = 0x100000001b3;

    var hash: u64 = FNV_OFFSET;
    for (data) |byte| {
        hash ^= byte;
        hash *%= FNV_PRIME;
    }
    return hash;
}

/// Hash for pointers
pub fn ptrHash(ptr: ?*const anyopaque) u64 {
    const addr = @intFromPtr(ptr);
    // Mix bits
    var h = addr;
    h ^= h >> 33;
    h *%= 0xff51afd7ed558ccd;
    h ^= h >> 33;
    h *%= 0xc4ceb9fe1a85ec53;
    h ^= h >> 33;
    return h;
}

/// Identity hash (for pre-hashed values)
pub fn identityHash(value: u64) u64 {
    return value;
}

// ============================================================================
// Generic Hash Table
// ============================================================================

/// Generic hash table with configurable key/value types
pub fn HashTable(comptime K: type, comptime V: type) type {
    return struct {
        allocator: Allocator,
        buckets: []?*Entry,
        size: usize = 0,
        capacity: usize = INITIAL_SIZE,

        // Statistics
        stats: Stats = .{},

        const Self = @This();

        /// Hash table entry
        pub const Entry = struct {
            key: K,
            value: V,
            hash: u64,
            next: ?*Entry = null,
        };

        /// Statistics
        pub const Stats = struct {
            inserts: u64 = 0,
            lookups: u64 = 0,
            collisions: u64 = 0,
            resizes: u64 = 0,
        };

        /// Initialize hash table
        pub fn init(allocator: Allocator) !Self {
            const buckets = try allocator.alloc(?*Entry, INITIAL_SIZE);
            @memset(buckets, null);

            return .{
                .allocator = allocator,
                .buckets = buckets,
            };
        }

        /// Initialize with specific capacity
        pub fn initCapacity(allocator: Allocator, capacity: usize) !Self {
            // Round up to power of 2
            const cap = std.math.ceilPowerOfTwo(usize, @max(capacity, INITIAL_SIZE)) catch INITIAL_SIZE;
            const buckets = try allocator.alloc(?*Entry, cap);
            @memset(buckets, null);

            return .{
                .allocator = allocator,
                .buckets = buckets,
                .capacity = cap,
            };
        }

        /// Deinitialize hash table
        pub fn deinit(self: *Self) void {
            // Free all entries
            for (self.buckets) |bucket| {
                var entry = bucket;
                while (entry) |e| {
                    const next_entry = e.next;
                    self.allocator.destroy(e);
                    entry = next_entry;
                }
            }
            self.allocator.free(self.buckets);
        }

        /// Get value for key
        pub fn get(self: *Self, key: K) ?V {
            self.stats.lookups += 1;
            const entry = self.getEntry(key);
            if (entry) |e| {
                return e.value;
            }
            return null;
        }

        /// Get entry for key
        pub fn getEntry(self: *Self, key: K) ?*Entry {
            const hash = hashKey(key);
            const idx = hash & (self.capacity - 1);

            var entry = self.buckets[idx];
            while (entry) |e| {
                if (e.hash == hash and keysEqual(e.key, key)) {
                    return e;
                }
                entry = e.next;
            }

            return null;
        }

        /// Put key-value pair
        pub fn put(self: *Self, key: K, value: V) !void {
            // Check for resize
            if (self.shouldGrow()) {
                try self.resize(self.capacity * 2);
            }

            const hash = hashKey(key);
            const idx = hash & (self.capacity - 1);

            // Check for existing key
            var entry = self.buckets[idx];
            while (entry) |e| {
                if (e.hash == hash and keysEqual(e.key, key)) {
                    e.value = value;
                    return;
                }
                entry = e.next;
            }

            // Create new entry
            const new_entry = try self.allocator.create(Entry);
            new_entry.* = .{
                .key = key,
                .value = value,
                .hash = hash,
                .next = self.buckets[idx],
            };

            if (self.buckets[idx] != null) {
                self.stats.collisions += 1;
            }

            self.buckets[idx] = new_entry;
            self.size += 1;
            self.stats.inserts += 1;
        }

        /// Remove key
        pub fn remove(self: *Self, key: K) bool {
            const hash = hashKey(key);
            const idx = hash & (self.capacity - 1);

            var prev: ?*Entry = null;
            var entry = self.buckets[idx];

            while (entry) |e| {
                if (e.hash == hash and keysEqual(e.key, key)) {
                    // Unlink
                    if (prev) |p| {
                        p.next = e.next;
                    } else {
                        self.buckets[idx] = e.next;
                    }

                    self.allocator.destroy(e);
                    self.size -= 1;

                    // Consider shrinking
                    if (self.shouldShrink()) {
                        self.resize(self.capacity / 2) catch {};
                    }

                    return true;
                }

                prev = e;
                entry = e.next;
            }

            return false;
        }

        /// Check if key exists
        pub fn contains(self: *Self, key: K) bool {
            return self.getEntry(key) != null;
        }

        /// Clear all entries
        pub fn clear(self: *Self) void {
            for (self.buckets) |*bucket| {
                var entry = bucket.*;
                while (entry) |e| {
                    const next_entry = e.next;
                    self.allocator.destroy(e);
                    entry = next_entry;
                }
                bucket.* = null;
            }
            self.size = 0;
        }

        /// Get number of entries
        pub fn count(self: Self) usize {
            return self.size;
        }

        /// Check if empty
        pub fn isEmpty(self: Self) bool {
            return self.size == 0;
        }

        /// Get load factor
        pub fn loadFactor(self: Self) f64 {
            return @as(f64, @floatFromInt(self.size)) / @as(f64, @floatFromInt(self.capacity));
        }

        // ====================================================================
        // Iteration
        // ====================================================================

        /// Iterator over entries
        pub const Iterator = struct {
            table: *Self,
            bucket_idx: usize = 0,
            current: ?*Entry = null,

            pub fn next(self: *Iterator) ?*Entry {
                // Continue in current chain
                if (self.current) |e| {
                    self.current = e.next;
                    if (self.current != null) {
                        return self.current;
                    }
                    self.bucket_idx += 1;
                }

                // Find next non-empty bucket
                while (self.bucket_idx < self.table.capacity) {
                    if (self.table.buckets[self.bucket_idx]) |e| {
                        self.current = e;
                        return e;
                    }
                    self.bucket_idx += 1;
                }

                return null;
            }
        };

        /// Get iterator
        pub fn iterator(self: *Self) Iterator {
            return .{ .table = self };
        }

        /// Get all keys
        pub fn keys(self: *Self, allocator: Allocator) ![]K {
            var result = try allocator.alloc(K, self.size);
            var i: usize = 0;

            var iter = self.iterator();
            while (iter.next()) |entry| {
                result[i] = entry.key;
                i += 1;
            }

            return result;
        }

        /// Get all values
        pub fn values(self: *Self, allocator: Allocator) ![]V {
            var result = try allocator.alloc(V, self.size);
            var i: usize = 0;

            var iter = self.iterator();
            while (iter.next()) |entry| {
                result[i] = entry.value;
                i += 1;
            }

            return result;
        }

        // ====================================================================
        // Internal
        // ====================================================================

        fn shouldGrow(self: Self) bool {
            return self.loadFactor() > MAX_LOAD_FACTOR;
        }

        fn shouldShrink(self: Self) bool {
            return self.capacity > MIN_SIZE and self.loadFactor() < MIN_LOAD_FACTOR;
        }

        fn resize(self: *Self, new_capacity: usize) !void {
            const old_buckets = self.buckets;

            // Allocate new buckets
            self.buckets = try self.allocator.alloc(?*Entry, new_capacity);
            @memset(self.buckets, null);
            self.capacity = new_capacity;
            self.stats.resizes += 1;

            // Rehash all entries
            for (old_buckets) |bucket| {
                var entry = bucket;
                while (entry) |e| {
                    const next_entry = e.next;
                    const idx = e.hash & (new_capacity - 1);

                    e.next = self.buckets[idx];
                    self.buckets[idx] = e;

                    entry = next_entry;
                }
            }

            self.allocator.free(old_buckets);
        }

        fn hashKey(key: K) u64 {
            if (K == []const u8) {
                return fnvHash(key);
            } else if (@typeInfo(K) == .pointer) {
                return ptrHash(@ptrCast(key));
            } else if (@typeInfo(K) == .int) {
                return identityHash(@intCast(key));
            } else {
                // Hash struct/array as bytes
                const bytes = std.mem.asBytes(&key);
                return fnvHash(bytes);
            }
        }

        fn keysEqual(a: K, b: K) bool {
            if (K == []const u8) {
                return std.mem.eql(u8, a, b);
            } else {
                return a == b;
            }
        }
    };
}

// ============================================================================
// Convenience Types
// ============================================================================

/// String to value hash table
pub fn StringHashTable(comptime V: type) type {
    return HashTable([]const u8, V);
}

/// Pointer to value hash table
pub fn PtrHashTable(comptime V: type) type {
    return HashTable(*anyopaque, V);
}

/// Integer to value hash table
pub fn IntHashTable(comptime V: type) type {
    return HashTable(u64, V);
}

// ============================================================================
// Set Implementation
// ============================================================================

/// Hash set (table with no values)
pub fn HashSet(comptime K: type) type {
    return struct {
        table: HashTable(K, void),

        const Self = @This();

        pub fn init(allocator: Allocator) !Self {
            return .{ .table = try HashTable(K, void).init(allocator) };
        }

        pub fn deinit(self: *Self) void {
            self.table.deinit();
        }

        pub fn add(self: *Self, key: K) !void {
            try self.table.put(key, {});
        }

        pub fn remove(self: *Self, key: K) bool {
            return self.table.remove(key);
        }

        pub fn contains(self: *Self, key: K) bool {
            return self.table.contains(key);
        }

        pub fn count(self: Self) usize {
            return self.table.size;
        }

        pub fn clear(self: *Self) void {
            self.table.clear();
        }
    };
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "basic operations" {
    var table = try HashTable(u64, []const u8).init(std.testing.allocator);
    defer table.deinit();

    try table.put(1, "one");
    try table.put(2, "two");
    try table.put(3, "three");

    try std.testing.expectEqual(@as(usize, 3), table.count());
    try std.testing.expectEqualStrings("one", table.get(1).?);
    try std.testing.expectEqualStrings("two", table.get(2).?);
    try std.testing.expect(table.get(999) == null);
}

test "string keys" {
    var table = try StringHashTable(i32).init(std.testing.allocator);
    defer table.deinit();

    try table.put("hello", 1);
    try table.put("world", 2);

    try std.testing.expectEqual(@as(i32, 1), table.get("hello").?);
    try std.testing.expectEqual(@as(i32, 2), table.get("world").?);
}

test "update value" {
    var table = try HashTable(u64, i32).init(std.testing.allocator);
    defer table.deinit();

    try table.put(1, 100);
    try std.testing.expectEqual(@as(i32, 100), table.get(1).?);

    try table.put(1, 200);
    try std.testing.expectEqual(@as(i32, 200), table.get(1).?);
    try std.testing.expectEqual(@as(usize, 1), table.count());
}

test "remove" {
    var table = try HashTable(u64, i32).init(std.testing.allocator);
    defer table.deinit();

    try table.put(1, 100);
    try table.put(2, 200);

    try std.testing.expect(table.remove(1));
    try std.testing.expect(table.get(1) == null);
    try std.testing.expectEqual(@as(usize, 1), table.count());

    try std.testing.expect(!table.remove(999));
}

test "iterator" {
    var table = try HashTable(u64, i32).init(std.testing.allocator);
    defer table.deinit();

    try table.put(1, 10);
    try table.put(2, 20);
    try table.put(3, 30);

    var sum: i32 = 0;
    var iter_count: usize = 0;

    var iter = table.iterator();
    while (iter.next()) |entry| {
        sum += entry.value;
        iter_count += 1;
    }

    try std.testing.expectEqual(@as(usize, 3), iter_count);
    try std.testing.expectEqual(@as(i32, 60), sum);
}

test "hash set" {
    var set = try HashSet(u64).init(std.testing.allocator);
    defer set.deinit();

    try set.add(1);
    try set.add(2);
    try set.add(3);
    try set.add(1); // Duplicate

    try std.testing.expectEqual(@as(usize, 3), set.count());
    try std.testing.expect(set.contains(1));
    try std.testing.expect(!set.contains(999));
}

test "resize" {
    var table = try HashTable(u64, u64).init(std.testing.allocator);
    defer table.deinit();

    // Insert enough to trigger resize
    for (0..100) |i| {
        try table.put(i, i * 10);
    }

    try std.testing.expectEqual(@as(usize, 100), table.count());

    // Verify all values
    for (0..100) |i| {
        try std.testing.expectEqual(@as(u64, i * 10), table.get(i).?);
    }
}
