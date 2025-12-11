/// Generic hash table implementation
/// Mirrors cpython/Python/hashtable.c core functionality

const std = @import("std");
const Allocator = std.mem.Allocator;
const constants = @import("constants.zig");
const hash_functions = @import("hash_functions.zig");

/// Generic hash table with configurable key/value types
pub fn HashTable(comptime K: type, comptime V: type) type {
    return struct {
        allocator: Allocator,
        buckets: []?*Entry,
        size: usize = 0,
        capacity: usize = constants.INITIAL_SIZE,

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
            const buckets = try allocator.alloc(?*Entry, constants.INITIAL_SIZE);
            @memset(buckets, null);

            return .{
                .allocator = allocator,
                .buckets = buckets,
            };
        }

        /// Initialize with specific capacity
        pub fn initCapacity(allocator: Allocator, capacity: usize) !Self {
            // Round up to power of 2
            const cap = std.math.ceilPowerOfTwo(usize, @max(capacity, constants.INITIAL_SIZE)) catch constants.INITIAL_SIZE;
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
            return self.loadFactor() > constants.MAX_LOAD_FACTOR;
        }

        fn shouldShrink(self: Self) bool {
            return self.capacity > constants.MIN_SIZE and self.loadFactor() < constants.MIN_LOAD_FACTOR;
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
                return hash_functions.fnvHash(key);
            } else if (@typeInfo(K) == .pointer) {
                return hash_functions.ptrHash(@ptrCast(key));
            } else if (@typeInfo(K) == .int) {
                return hash_functions.identityHash(@intCast(key));
            } else {
                // Hash struct/array as bytes
                const bytes = std.mem.asBytes(&key);
                return hash_functions.fnvHash(bytes);
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
