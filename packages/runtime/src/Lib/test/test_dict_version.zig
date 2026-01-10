//! test.test_dict_version - Dict version tests
//! CPython Reference: https://peps.python.org/pep-0509/
//!
//! This module provides tests for dictionary version tagging (PEP 509),
//! which allows efficient caching of dictionary lookups by tracking
//! when dictionaries are modified.

const std = @import("std");

// ============================================================================
// Version Types
// ============================================================================

/// Dictionary version tag (64-bit counter)
pub const DictVersion = u64;

/// Initial version (never used for actual dicts)
pub const INITIAL_VERSION: DictVersion = 0;

/// Maximum version before wrap-around
pub const MAX_VERSION: DictVersion = std.math.maxInt(DictVersion);

/// Global version counter (thread-local for thread safety)
threadlocal var global_version: DictVersion = 1;

/// Get next unique version number
pub fn nextVersion() DictVersion {
    const version = global_version;
    global_version +%= 1; // Wrap on overflow
    if (global_version == 0) global_version = 1; // Skip 0
    return version;
}

/// Reset global version counter (for testing)
pub fn resetVersionCounter() void {
    global_version = 1;
}

// ============================================================================
// Versioned Dictionary
// ============================================================================

/// A dictionary with version tracking
pub fn VersionedDict(comptime K: type, comptime V: type) type {
    return struct {
        /// Internal storage
        inner: std.AutoHashMap(K, V),
        /// Current version tag
        version: DictVersion,
        /// Version at last read operation
        last_read_version: DictVersion = 0,
        /// Number of modifications since creation
        modification_count: u64 = 0,
        /// Creation version
        creation_version: DictVersion,

        const Self = @This();

        /// Initialize a new versioned dictionary
        pub fn init(allocator: std.mem.Allocator) Self {
            const v = nextVersion();
            return .{
                .inner = std.AutoHashMap(K, V).init(allocator),
                .version = v,
                .creation_version = v,
            };
        }

        /// Deinitialize and free resources
        pub fn deinit(self: *Self) void {
            self.inner.deinit();
        }

        /// Get current version
        pub fn getVersion(self: *const Self) DictVersion {
            return self.version;
        }

        /// Check if dictionary was modified since a specific version
        pub fn wasModifiedSince(self: *const Self, since_version: DictVersion) bool {
            return self.version != since_version;
        }

        /// Put a key-value pair (updates version)
        pub fn put(self: *Self, key: K, value: V) !void {
            try self.inner.put(key, value);
            self.bumpVersion();
        }

        /// Get a value by key (does not update version)
        pub fn get(self: *Self, key: K) ?V {
            self.last_read_version = self.version;
            return self.inner.get(key);
        }

        /// Remove a key (updates version)
        pub fn remove(self: *Self, key: K) bool {
            const removed = self.inner.remove(key);
            if (removed) {
                self.bumpVersion();
            }
            return removed;
        }

        /// Clear all entries (updates version)
        pub fn clear(self: *Self) void {
            self.inner.clearAndFree();
            self.bumpVersion();
        }

        /// Get number of entries
        pub fn count(self: *const Self) u32 {
            return self.inner.count();
        }

        /// Check if dictionary contains a key
        pub fn contains(self: *const Self, key: K) bool {
            return self.inner.contains(key);
        }

        /// Update version after modification
        fn bumpVersion(self: *Self) void {
            self.version = nextVersion();
            self.modification_count += 1;
        }

        /// Create a copy with new version
        pub fn clone(self: *const Self, allocator: std.mem.Allocator) !Self {
            var new_dict = Self.init(allocator);

            var iter = self.inner.iterator();
            while (iter.next()) |entry| {
                try new_dict.inner.put(entry.key_ptr.*, entry.value_ptr.*);
            }

            return new_dict;
        }

        /// Merge another dictionary into this one
        pub fn merge(self: *Self, other: *const Self) !void {
            var iter = other.inner.iterator();
            while (iter.next()) |entry| {
                try self.inner.put(entry.key_ptr.*, entry.value_ptr.*);
            }
            self.bumpVersion();
        }
    };
}

// ============================================================================
// Cache Entry with Version Tracking
// ============================================================================

/// A cached value that tracks the dictionary version when cached
pub fn CacheEntry(comptime V: type) type {
    return struct {
        /// Cached value
        value: V,
        /// Version when this entry was cached
        cached_version: DictVersion,
        /// Number of cache hits
        hit_count: u64 = 0,
        /// Number of cache invalidations
        invalidation_count: u64 = 0,

        const Self = @This();

        /// Create a new cache entry
        pub fn init(value: V, version: DictVersion) Self {
            return .{
                .value = value,
                .cached_version = version,
            };
        }

        /// Check if cache is still valid for given dictionary version
        pub fn isValid(self: *const Self, current_version: DictVersion) bool {
            return self.cached_version == current_version;
        }

        /// Update cached value and version
        pub fn update(self: *Self, value: V, version: DictVersion) void {
            if (!self.isValid(version)) {
                self.invalidation_count += 1;
            }
            self.value = value;
            self.cached_version = version;
        }

        /// Record a cache hit
        pub fn recordHit(self: *Self) void {
            self.hit_count += 1;
        }

        /// Get cache hit ratio
        pub fn hitRatio(self: *const Self) f64 {
            const total = self.hit_count + self.invalidation_count;
            if (total == 0) return 0.0;
            return @as(f64, @floatFromInt(self.hit_count)) / @as(f64, @floatFromInt(total));
        }
    };
}

// ============================================================================
// Version-Aware Cache
// ============================================================================

/// A cache that tracks multiple dictionary versions
pub fn VersionAwareCache(comptime K: type, comptime V: type) type {
    return struct {
        /// Cached entries
        entries: std.AutoHashMap(K, CacheEntry(V)),
        /// Total cache hits
        total_hits: u64 = 0,
        /// Total cache misses
        total_misses: u64 = 0,
        /// Maximum cache size
        max_size: u32,
        /// Allocator
        allocator: std.mem.Allocator,

        const Self = @This();

        /// Initialize cache with maximum size
        pub fn init(allocator: std.mem.Allocator, max_size: u32) Self {
            return .{
                .entries = std.AutoHashMap(K, CacheEntry(V)).init(allocator),
                .max_size = max_size,
                .allocator = allocator,
            };
        }

        /// Deinitialize cache
        pub fn deinit(self: *Self) void {
            self.entries.deinit();
        }

        /// Get cached value if valid
        pub fn get(self: *Self, key: K, current_version: DictVersion) ?V {
            if (self.entries.getPtr(key)) |entry| {
                if (entry.isValid(current_version)) {
                    entry.recordHit();
                    self.total_hits += 1;
                    return entry.value;
                }
            }
            self.total_misses += 1;
            return null;
        }

        /// Put value in cache
        pub fn put(self: *Self, key: K, value: V, version: DictVersion) !void {
            // Evict if at capacity
            if (self.entries.count() >= self.max_size) {
                self.evictOne();
            }

            const result = try self.entries.getOrPut(key);
            if (result.found_existing) {
                result.value_ptr.update(value, version);
            } else {
                result.value_ptr.* = CacheEntry(V).init(value, version);
            }
        }

        /// Invalidate all entries
        pub fn invalidateAll(self: *Self) void {
            self.entries.clearAndFree();
        }

        /// Invalidate entries for specific version
        pub fn invalidateVersion(self: *Self, version: DictVersion) void {
            var to_remove = std.ArrayList(K).init(self.allocator);
            defer to_remove.deinit();

            var iter = self.entries.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.cached_version == version) {
                    to_remove.append(entry.key_ptr.*) catch continue;
                }
            }

            for (to_remove.items) |key| {
                _ = self.entries.remove(key);
            }
        }

        /// Get cache statistics
        pub fn getStats(self: *const Self) CacheStats {
            return .{
                .size = self.entries.count(),
                .max_size = self.max_size,
                .total_hits = self.total_hits,
                .total_misses = self.total_misses,
            };
        }

        /// Evict one entry (LRU-like: evict lowest hit count)
        fn evictOne(self: *Self) void {
            var min_hits: u64 = std.math.maxInt(u64);
            var evict_key: ?K = null;

            var iter = self.entries.iterator();
            while (iter.next()) |entry| {
                if (entry.value_ptr.hit_count < min_hits) {
                    min_hits = entry.value_ptr.hit_count;
                    evict_key = entry.key_ptr.*;
                }
            }

            if (evict_key) |key| {
                _ = self.entries.remove(key);
            }
        }
    };
}

/// Cache statistics
pub const CacheStats = struct {
    size: u32,
    max_size: u32,
    total_hits: u64,
    total_misses: u64,

    pub fn hitRatio(self: *const CacheStats) f64 {
        const total = self.total_hits + self.total_misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_hits)) / @as(f64, @floatFromInt(total));
    }
};

// ============================================================================
// Version Change Detector
// ============================================================================

/// Detects changes in dictionary version
pub const VersionChangeDetector = struct {
    /// Last observed version
    last_version: DictVersion = INITIAL_VERSION,
    /// Number of version changes detected
    change_count: u64 = 0,
    /// Timestamp of last change
    last_change_time_ns: i128 = 0,

    const Self = @This();

    /// Check if version changed and update tracking
    pub fn checkAndUpdate(self: *Self, current_version: DictVersion) bool {
        if (current_version != self.last_version) {
            self.last_version = current_version;
            self.change_count += 1;
            self.last_change_time_ns = std.time.nanoTimestamp();
            return true;
        }
        return false;
    }

    /// Get time since last change in nanoseconds
    pub fn timeSinceLastChange(self: *const Self) i128 {
        if (self.last_change_time_ns == 0) return 0;
        return std.time.nanoTimestamp() - self.last_change_time_ns;
    }

    /// Reset detector state
    pub fn reset(self: *Self) void {
        self.last_version = INITIAL_VERSION;
        self.change_count = 0;
        self.last_change_time_ns = 0;
    }
};

// ============================================================================
// Test Cases
// ============================================================================

/// Test case for version tracking
pub const VersionTestCase = struct {
    name: []const u8,
    operations: []const Operation,
    expected_version_changes: u32,

    pub const Operation = enum {
        put,
        get,
        remove,
        clear,
    };
};

/// Standard test cases
pub const standard_test_cases = [_]VersionTestCase{
    .{
        .name = "single_put",
        .operations = &[_]VersionTestCase.Operation{.put},
        .expected_version_changes = 1,
    },
    .{
        .name = "put_get",
        .operations = &[_]VersionTestCase.Operation{ .put, .get },
        .expected_version_changes = 1,
    },
    .{
        .name = "multiple_puts",
        .operations = &[_]VersionTestCase.Operation{ .put, .put, .put },
        .expected_version_changes = 3,
    },
    .{
        .name = "put_remove",
        .operations = &[_]VersionTestCase.Operation{ .put, .remove },
        .expected_version_changes = 2,
    },
    .{
        .name = "put_clear",
        .operations = &[_]VersionTestCase.Operation{ .put, .put, .clear },
        .expected_version_changes = 3,
    },
};

// ============================================================================
// Unit Tests
// ============================================================================

test "nextVersion uniqueness" {
    resetVersionCounter();

    const v1 = nextVersion();
    const v2 = nextVersion();
    const v3 = nextVersion();

    try std.testing.expect(v1 != v2);
    try std.testing.expect(v2 != v3);
    try std.testing.expect(v1 != v3);
}

test "nextVersion skips zero" {
    resetVersionCounter();

    // Set counter near max to test wrap-around
    global_version = MAX_VERSION;
    const v1 = nextVersion();
    try std.testing.expectEqual(MAX_VERSION, v1);

    const v2 = nextVersion();
    try std.testing.expect(v2 != 0);
    try std.testing.expectEqual(@as(DictVersion, 1), v2);
}

test "VersionedDict init" {
    const allocator = std.testing.allocator;
    resetVersionCounter();

    var dict = VersionedDict(i32, i32).init(allocator);
    defer dict.deinit();

    try std.testing.expect(dict.getVersion() > 0);
    try std.testing.expectEqual(@as(u32, 0), dict.count());
}

test "VersionedDict put updates version" {
    const allocator = std.testing.allocator;
    resetVersionCounter();

    var dict = VersionedDict(i32, i32).init(allocator);
    defer dict.deinit();

    const v1 = dict.getVersion();
    try dict.put(1, 100);
    const v2 = dict.getVersion();

    try std.testing.expect(v2 > v1);
    try std.testing.expectEqual(@as(u64, 1), dict.modification_count);
}

test "VersionedDict get does not update version" {
    const allocator = std.testing.allocator;
    resetVersionCounter();

    var dict = VersionedDict(i32, i32).init(allocator);
    defer dict.deinit();

    try dict.put(1, 100);
    const v1 = dict.getVersion();

    _ = dict.get(1);
    const v2 = dict.getVersion();

    try std.testing.expectEqual(v1, v2);
}

test "VersionedDict remove updates version" {
    const allocator = std.testing.allocator;
    resetVersionCounter();

    var dict = VersionedDict(i32, i32).init(allocator);
    defer dict.deinit();

    try dict.put(1, 100);
    const v1 = dict.getVersion();

    _ = dict.remove(1);
    const v2 = dict.getVersion();

    try std.testing.expect(v2 > v1);
}

test "VersionedDict clear updates version" {
    const allocator = std.testing.allocator;
    resetVersionCounter();

    var dict = VersionedDict(i32, i32).init(allocator);
    defer dict.deinit();

    try dict.put(1, 100);
    try dict.put(2, 200);
    const v1 = dict.getVersion();

    dict.clear();
    const v2 = dict.getVersion();

    try std.testing.expect(v2 > v1);
    try std.testing.expectEqual(@as(u32, 0), dict.count());
}

test "VersionedDict wasModifiedSince" {
    const allocator = std.testing.allocator;
    resetVersionCounter();

    var dict = VersionedDict(i32, i32).init(allocator);
    defer dict.deinit();

    const v1 = dict.getVersion();
    try std.testing.expect(!dict.wasModifiedSince(v1));

    try dict.put(1, 100);
    try std.testing.expect(dict.wasModifiedSince(v1));
    try std.testing.expect(!dict.wasModifiedSince(dict.getVersion()));
}

test "CacheEntry validity" {
    var entry = CacheEntry(i32).init(42, 100);

    try std.testing.expect(entry.isValid(100));
    try std.testing.expect(!entry.isValid(101));
}

test "CacheEntry hitRatio" {
    var entry = CacheEntry(i32).init(42, 100);

    entry.recordHit();
    entry.recordHit();
    entry.recordHit();
    entry.invalidation_count = 1;

    try std.testing.expectApproxEqAbs(@as(f64, 0.75), entry.hitRatio(), 0.001);
}

test "VersionAwareCache basic operations" {
    const allocator = std.testing.allocator;
    resetVersionCounter();

    var cache = VersionAwareCache(i32, i32).init(allocator, 10);
    defer cache.deinit();

    try cache.put(1, 100, 1);
    try cache.put(2, 200, 1);

    // Valid cache hit
    const val1 = cache.get(1, 1);
    try std.testing.expectEqual(@as(?i32, 100), val1);

    // Invalid due to version change
    const val2 = cache.get(1, 2);
    try std.testing.expect(val2 == null);
}

test "VersionAwareCache eviction" {
    const allocator = std.testing.allocator;

    var cache = VersionAwareCache(i32, i32).init(allocator, 2);
    defer cache.deinit();

    try cache.put(1, 100, 1);
    try cache.put(2, 200, 1);
    try cache.put(3, 300, 1); // Should evict one

    try std.testing.expect(cache.entries.count() <= 2);
}

test "VersionAwareCache statistics" {
    const allocator = std.testing.allocator;
    resetVersionCounter();

    var cache = VersionAwareCache(i32, i32).init(allocator, 10);
    defer cache.deinit();

    try cache.put(1, 100, 1);

    _ = cache.get(1, 1); // Hit
    _ = cache.get(1, 1); // Hit
    _ = cache.get(2, 1); // Miss
    _ = cache.get(1, 2); // Miss (version changed)

    const stats = cache.getStats();
    try std.testing.expectEqual(@as(u64, 2), stats.total_hits);
    try std.testing.expectEqual(@as(u64, 2), stats.total_misses);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), stats.hitRatio(), 0.001);
}

test "VersionChangeDetector" {
    var detector = VersionChangeDetector{};

    try std.testing.expect(detector.checkAndUpdate(1));
    try std.testing.expect(!detector.checkAndUpdate(1));
    try std.testing.expect(detector.checkAndUpdate(2));

    try std.testing.expectEqual(@as(u64, 2), detector.change_count);
}

test "VersionChangeDetector reset" {
    var detector = VersionChangeDetector{};

    _ = detector.checkAndUpdate(1);
    _ = detector.checkAndUpdate(2);

    detector.reset();

    try std.testing.expectEqual(@as(u64, 0), detector.change_count);
    try std.testing.expectEqual(INITIAL_VERSION, detector.last_version);
}

test "VersionedDict clone" {
    const allocator = std.testing.allocator;
    resetVersionCounter();

    var dict1 = VersionedDict(i32, i32).init(allocator);
    defer dict1.deinit();

    try dict1.put(1, 100);
    try dict1.put(2, 200);

    var dict2 = try dict1.clone(allocator);
    defer dict2.deinit();

    try std.testing.expect(dict2.getVersion() != dict1.getVersion());
    try std.testing.expectEqual(@as(?i32, 100), dict2.get(1));
    try std.testing.expectEqual(@as(?i32, 200), dict2.get(2));
}

test "VersionedDict merge" {
    const allocator = std.testing.allocator;
    resetVersionCounter();

    var dict1 = VersionedDict(i32, i32).init(allocator);
    defer dict1.deinit();
    try dict1.put(1, 100);

    var dict2 = VersionedDict(i32, i32).init(allocator);
    defer dict2.deinit();
    try dict2.put(2, 200);

    const v_before = dict1.getVersion();
    try dict1.merge(&dict2);
    const v_after = dict1.getVersion();

    try std.testing.expect(v_after > v_before);
    try std.testing.expectEqual(@as(u32, 2), dict1.count());
    try std.testing.expectEqual(@as(?i32, 100), dict1.get(1));
    try std.testing.expectEqual(@as(?i32, 200), dict1.get(2));
}
