//! test.test_free_threading.test_dict - Concurrent dictionary access
//!
//! This module tests thread-safe dictionary operations for free-threaded Python.
//! It provides a concurrent hash map implementation with fine-grained locking
//! and tests for common concurrent access patterns.
const std = @import("std");

/// A thread-safe dictionary with per-bucket locking for better concurrency
pub fn ConcurrentDict(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const BUCKET_COUNT = 16;

        const Bucket = struct {
            map: std.AutoHashMap(K, V),
            mutex: std.Thread.Mutex,

            fn init(allocator: std.mem.Allocator) Bucket {
                return .{
                    .map = std.AutoHashMap(K, V).init(allocator),
                    .mutex = .{},
                };
            }

            fn deinit(self: *Bucket) void {
                self.map.deinit();
            }
        };

        buckets: [BUCKET_COUNT]Bucket,
        allocator: std.mem.Allocator,
        size: std.atomic.Value(usize),

        pub fn init(allocator: std.mem.Allocator) Self {
            var buckets: [BUCKET_COUNT]Bucket = undefined;
            for (&buckets) |*b| {
                b.* = Bucket.init(allocator);
            }
            return .{
                .buckets = buckets,
                .allocator = allocator,
                .size = std.atomic.Value(usize).init(0),
            };
        }

        pub fn deinit(self: *Self) void {
            for (&self.buckets) |*b| {
                b.deinit();
            }
        }

        fn getBucketIndex(key: K) usize {
            const hash = std.hash.Wyhash.hash(0, std.mem.asBytes(&key));
            return @intCast(hash % BUCKET_COUNT);
        }

        pub fn put(self: *Self, key: K, value: V) !void {
            const idx = getBucketIndex(key);
            self.buckets[idx].mutex.lock();
            defer self.buckets[idx].mutex.unlock();

            const result = try self.buckets[idx].map.getOrPut(key);
            if (!result.found_existing) {
                _ = self.size.fetchAdd(1, .monotonic);
            }
            result.value_ptr.* = value;
        }

        pub fn get(self: *Self, key: K) ?V {
            const idx = getBucketIndex(key);
            self.buckets[idx].mutex.lock();
            defer self.buckets[idx].mutex.unlock();
            return self.buckets[idx].map.get(key);
        }

        pub fn remove(self: *Self, key: K) bool {
            const idx = getBucketIndex(key);
            self.buckets[idx].mutex.lock();
            defer self.buckets[idx].mutex.unlock();

            if (self.buckets[idx].map.fetchRemove(key)) |_| {
                _ = self.size.fetchSub(1, .monotonic);
                return true;
            }
            return false;
        }

        pub fn contains(self: *Self, key: K) bool {
            const idx = getBucketIndex(key);
            self.buckets[idx].mutex.lock();
            defer self.buckets[idx].mutex.unlock();
            return self.buckets[idx].map.contains(key);
        }

        pub fn len(self: *const Self) usize {
            return self.size.load(.acquire);
        }

        pub fn getOrPut(self: *Self, key: K, default: V) !V {
            const idx = getBucketIndex(key);
            self.buckets[idx].mutex.lock();
            defer self.buckets[idx].mutex.unlock();

            const result = try self.buckets[idx].map.getOrPut(key);
            if (!result.found_existing) {
                result.value_ptr.* = default;
                _ = self.size.fetchAdd(1, .monotonic);
            }
            return result.value_ptr.*;
        }

        pub fn update(self: *Self, key: K, updateFn: *const fn (V) V) !bool {
            const idx = getBucketIndex(key);
            self.buckets[idx].mutex.lock();
            defer self.buckets[idx].mutex.unlock();

            if (self.buckets[idx].map.getPtr(key)) |value_ptr| {
                value_ptr.* = updateFn(value_ptr.*);
                return true;
            }
            return false;
        }
    };
}

/// String-keyed concurrent dictionary
pub const ConcurrentStringDict = struct {
    const Self = @This();
    const BUCKET_COUNT = 32;

    const Entry = struct {
        key: []const u8,
        value: []const u8,
        next: ?*Entry,
    };

    const Bucket = struct {
        head: ?*Entry,
        mutex: std.Thread.Mutex,

        fn init() Bucket {
            return .{ .head = null, .mutex = .{} };
        }
    };

    buckets: [BUCKET_COUNT]Bucket,
    allocator: std.mem.Allocator,
    size: std.atomic.Value(usize),

    pub fn init(allocator: std.mem.Allocator) Self {
        var buckets: [BUCKET_COUNT]Bucket = undefined;
        for (&buckets) |*b| {
            b.* = Bucket.init();
        }
        return .{
            .buckets = buckets,
            .allocator = allocator,
            .size = std.atomic.Value(usize).init(0),
        };
    }

    pub fn deinit(self: *Self) void {
        for (&self.buckets) |*bucket| {
            bucket.mutex.lock();
            var current = bucket.head;
            while (current) |entry| {
                const next = entry.next;
                self.allocator.free(entry.key);
                self.allocator.free(entry.value);
                self.allocator.destroy(entry);
                current = next;
            }
            bucket.mutex.unlock();
        }
    }

    fn hash(key: []const u8) usize {
        return @intCast(std.hash.Wyhash.hash(0, key) % BUCKET_COUNT);
    }

    pub fn put(self: *Self, key: []const u8, value: []const u8) !void {
        const idx = hash(key);
        self.buckets[idx].mutex.lock();
        defer self.buckets[idx].mutex.unlock();

        // Check for existing key
        var current = self.buckets[idx].head;
        while (current) |entry| : (current = entry.next) {
            if (std.mem.eql(u8, entry.key, key)) {
                // Update existing value
                self.allocator.free(entry.value);
                entry.value = try self.allocator.dupe(u8, value);
                return;
            }
        }

        // Add new entry
        const new_entry = try self.allocator.create(Entry);
        new_entry.* = .{
            .key = try self.allocator.dupe(u8, key),
            .value = try self.allocator.dupe(u8, value),
            .next = self.buckets[idx].head,
        };
        self.buckets[idx].head = new_entry;
        _ = self.size.fetchAdd(1, .monotonic);
    }

    pub fn get(self: *Self, key: []const u8) ?[]const u8 {
        const idx = hash(key);
        self.buckets[idx].mutex.lock();
        defer self.buckets[idx].mutex.unlock();

        var current = self.buckets[idx].head;
        while (current) |entry| : (current = entry.next) {
            if (std.mem.eql(u8, entry.key, key)) {
                return entry.value;
            }
        }
        return null;
    }

    pub fn remove(self: *Self, key: []const u8) bool {
        const idx = hash(key);
        self.buckets[idx].mutex.lock();
        defer self.buckets[idx].mutex.unlock();

        var prev: ?*Entry = null;
        var current = self.buckets[idx].head;

        while (current) |entry| {
            if (std.mem.eql(u8, entry.key, key)) {
                if (prev) |p| {
                    p.next = entry.next;
                } else {
                    self.buckets[idx].head = entry.next;
                }
                self.allocator.free(entry.key);
                self.allocator.free(entry.value);
                self.allocator.destroy(entry);
                _ = self.size.fetchSub(1, .monotonic);
                return true;
            }
            prev = entry;
            current = entry.next;
        }
        return false;
    }

    pub fn len(self: *const Self) usize {
        return self.size.load(.acquire);
    }
};

/// Read-optimized dictionary using RWLock
pub fn ReadOptimizedDict(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();

        map: std.AutoHashMap(K, V),
        rwlock: std.Thread.RwLock,
        read_count: std.atomic.Value(usize),
        write_count: std.atomic.Value(usize),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .map = std.AutoHashMap(K, V).init(allocator),
                .rwlock = .{},
                .read_count = std.atomic.Value(usize).init(0),
                .write_count = std.atomic.Value(usize).init(0),
            };
        }

        pub fn deinit(self: *Self) void {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            self.map.deinit();
        }

        pub fn get(self: *Self, key: K) ?V {
            self.rwlock.lockShared();
            defer self.rwlock.unlockShared();
            _ = self.read_count.fetchAdd(1, .monotonic);
            return self.map.get(key);
        }

        pub fn put(self: *Self, key: K, value: V) !void {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            _ = self.write_count.fetchAdd(1, .monotonic);
            try self.map.put(key, value);
        }

        pub fn remove(self: *Self, key: K) bool {
            self.rwlock.lock();
            defer self.rwlock.unlock();
            _ = self.write_count.fetchAdd(1, .monotonic);
            return self.map.remove(key);
        }

        pub fn stats(self: *const Self) struct { reads: usize, writes: usize } {
            return .{
                .reads = self.read_count.load(.acquire),
                .writes = self.write_count.load(.acquire),
            };
        }
    };
}

/// Copy-on-write dictionary for snapshot isolation
pub fn CowDict(comptime K: type, comptime V: type) type {
    return struct {
        const Self = @This();
        const Map = std.AutoHashMap(K, V);

        map: *Map,
        allocator: std.mem.Allocator,
        refcount: std.atomic.Value(usize),
        mutex: std.Thread.Mutex,

        pub fn init(allocator: std.mem.Allocator) !Self {
            const map = try allocator.create(Map);
            map.* = Map.init(allocator);
            return .{
                .map = map,
                .allocator = allocator,
                .refcount = std.atomic.Value(usize).init(1),
                .mutex = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            const count = self.refcount.fetchSub(1, .release);
            if (count == 1) {
                std.atomic.fence(.acquire);
                self.map.deinit();
                self.allocator.destroy(self.map);
            }
        }

        pub fn get(self: *Self, key: K) ?V {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.map.get(key);
        }

        pub fn put(self: *Self, key: K, value: V) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Copy on write if shared
            if (self.refcount.load(.acquire) > 1) {
                const new_map = try self.allocator.create(Map);
                new_map.* = Map.init(self.allocator);

                var iter = self.map.iterator();
                while (iter.next()) |entry| {
                    try new_map.put(entry.key_ptr.*, entry.value_ptr.*);
                }

                _ = self.refcount.fetchSub(1, .release);
                self.map = new_map;
                self.refcount.store(1, .release);
            }

            try self.map.put(key, value);
        }

        pub fn snapshot(self: *Self) Self {
            self.mutex.lock();
            defer self.mutex.unlock();
            _ = self.refcount.fetchAdd(1, .monotonic);
            return .{
                .map = self.map,
                .allocator = self.allocator,
                .refcount = self.refcount,
                .mutex = .{},
            };
        }
    };
}

/// Test context for concurrent dictionary operations
pub const DictTestContext = struct {
    allocator: std.mem.Allocator,
    operations: std.atomic.Value(usize),
    errors: std.atomic.Value(usize),

    pub fn init(allocator: std.mem.Allocator) DictTestContext {
        return .{
            .allocator = allocator,
            .operations = std.atomic.Value(usize).init(0),
            .errors = std.atomic.Value(usize).init(0),
        };
    }

    pub fn recordOperation(self: *DictTestContext) void {
        _ = self.operations.fetchAdd(1, .monotonic);
    }

    pub fn recordError(self: *DictTestContext) void {
        _ = self.errors.fetchAdd(1, .monotonic);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "concurrent_dict_basic" {
    const allocator = std.testing.allocator;
    var dict = ConcurrentDict(i32, []const u8).init(allocator);
    defer dict.deinit();

    try dict.put(1, "one");
    try dict.put(2, "two");
    try dict.put(3, "three");

    try std.testing.expectEqual(@as(usize, 3), dict.len());
    try std.testing.expectEqualStrings("one", dict.get(1).?);
    try std.testing.expectEqualStrings("two", dict.get(2).?);
    try std.testing.expect(dict.get(4) == null);
}

test "concurrent_dict_update" {
    const allocator = std.testing.allocator;
    var dict = ConcurrentDict(i32, i32).init(allocator);
    defer dict.deinit();

    try dict.put(1, 100);
    try dict.put(1, 200); // Update

    try std.testing.expectEqual(@as(usize, 1), dict.len());
    try std.testing.expectEqual(@as(?i32, 200), dict.get(1));
}

test "concurrent_dict_remove" {
    const allocator = std.testing.allocator;
    var dict = ConcurrentDict(i32, i32).init(allocator);
    defer dict.deinit();

    try dict.put(1, 10);
    try dict.put(2, 20);

    try std.testing.expect(dict.remove(1));
    try std.testing.expect(!dict.remove(3));
    try std.testing.expectEqual(@as(usize, 1), dict.len());
}

test "concurrent_dict_get_or_put" {
    const allocator = std.testing.allocator;
    var dict = ConcurrentDict(i32, i32).init(allocator);
    defer dict.deinit();

    const val1 = try dict.getOrPut(1, 100);
    try std.testing.expectEqual(@as(i32, 100), val1);

    try dict.put(1, 200);
    const val2 = try dict.getOrPut(1, 300);
    try std.testing.expectEqual(@as(i32, 200), val2);
}

test "concurrent_string_dict_basic" {
    const allocator = std.testing.allocator;
    var dict = ConcurrentStringDict.init(allocator);
    defer dict.deinit();

    try dict.put("hello", "world");
    try dict.put("foo", "bar");

    try std.testing.expectEqualStrings("world", dict.get("hello").?);
    try std.testing.expectEqualStrings("bar", dict.get("foo").?);
    try std.testing.expect(dict.get("missing") == null);
}

test "concurrent_string_dict_update" {
    const allocator = std.testing.allocator;
    var dict = ConcurrentStringDict.init(allocator);
    defer dict.deinit();

    try dict.put("key", "value1");
    try dict.put("key", "value2");

    try std.testing.expectEqual(@as(usize, 1), dict.len());
    try std.testing.expectEqualStrings("value2", dict.get("key").?);
}

test "read_optimized_dict_stats" {
    const allocator = std.testing.allocator;
    var dict = ReadOptimizedDict(i32, i32).init(allocator);
    defer dict.deinit();

    try dict.put(1, 10);
    try dict.put(2, 20);
    _ = dict.get(1);
    _ = dict.get(2);
    _ = dict.get(1);

    const s = dict.stats();
    try std.testing.expectEqual(@as(usize, 2), s.writes);
    try std.testing.expectEqual(@as(usize, 3), s.reads);
}

test "cow_dict_snapshot" {
    const allocator = std.testing.allocator;
    var dict = try CowDict(i32, i32).init(allocator);
    defer dict.deinit();

    try dict.put(1, 100);
    try dict.put(2, 200);

    var snapshot = dict.snapshot();
    defer snapshot.deinit();

    try dict.put(1, 999); // Modify original

    try std.testing.expectEqual(@as(?i32, 999), dict.get(1));
    try std.testing.expectEqual(@as(?i32, 100), snapshot.get(1)); // Snapshot unchanged
}

test "concurrent_dict_multithread" {
    const allocator = std.testing.allocator;
    var dict = ConcurrentDict(usize, usize).init(allocator);
    defer dict.deinit();

    const num_threads = 4;
    const ops_per_thread = 100;
    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, struct {
            fn run(d: *ConcurrentDict(usize, usize), tid: usize) void {
                for (0..ops_per_thread) |j| {
                    const key = tid * ops_per_thread + j;
                    d.put(key, key * 2) catch {};
                    _ = d.get(key);
                }
            }
        }.run, .{ &dict, i }) catch unreachable;
    }

    for (&threads) |*t| {
        t.join();
    }

    // All keys should be present
    try std.testing.expectEqual(@as(usize, num_threads * ops_per_thread), dict.len());
}

test "dict_test_context" {
    const allocator = std.testing.allocator;
    var ctx = DictTestContext.init(allocator);

    ctx.recordOperation();
    ctx.recordOperation();
    ctx.recordError();

    try std.testing.expectEqual(@as(usize, 2), ctx.operations.load(.acquire));
    try std.testing.expectEqual(@as(usize, 1), ctx.errors.load(.acquire));
}
