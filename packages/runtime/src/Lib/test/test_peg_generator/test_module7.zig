//! test.test_peg_generator.test_memoization - Packrat memoization tests
//!
//! This module tests memoization (packrat parsing) for PEG parsers,
//! including memo table management, cache invalidation, and performance.

const std = @import("std");

/// Result stored in memo table
pub const MemoResult = union(enum) {
    success: MemoSuccess,
    failure: MemoFailure,
    in_progress: void, // Currently being computed (for left recursion)

    pub fn isSuccess(self: MemoResult) bool {
        return self == .success;
    }

    pub fn isFailure(self: MemoResult) bool {
        return self == .failure;
    }

    pub fn isInProgress(self: MemoResult) bool {
        return self == .in_progress;
    }
};

/// Successful parse result in memo
pub const MemoSuccess = struct {
    value: []const u8,
    start_pos: usize,
    end_pos: usize,
    rule_name: []const u8,

    pub fn length(self: MemoSuccess) usize {
        return self.end_pos - self.start_pos;
    }
};

/// Failed parse result in memo
pub const MemoFailure = struct {
    position: usize,
    expected: []const u8,
    rule_name: []const u8,
};

/// Key for memo table entries
pub const MemoKey = struct {
    rule_name: []const u8,
    position: usize,

    pub fn hash(self: MemoKey) u64 {
        var h = std.hash.Wyhash.init(0);
        h.update(self.rule_name);
        h.update(std.mem.asBytes(&self.position));
        return h.final();
    }

    pub fn eql(a: MemoKey, b: MemoKey) bool {
        return a.position == b.position and std.mem.eql(u8, a.rule_name, b.rule_name);
    }
};

/// Context for hash map
const MemoKeyContext = struct {
    pub fn hash(_: MemoKeyContext, key: MemoKey) u64 {
        return key.hash();
    }

    pub fn eql(_: MemoKeyContext, a: MemoKey, b: MemoKey) bool {
        return a.eql(b);
    }
};

/// Memo table for packrat parsing
pub const MemoTable = struct {
    entries: std.HashMap(MemoKey, MemoEntry, MemoKeyContext, 80),
    stats: MemoStats,
    allocator: std.mem.Allocator,
    max_entries: usize,

    pub const MemoEntry = struct {
        result: MemoResult,
        timestamp: i64,
        hit_count: usize,
    };

    pub fn init(allocator: std.mem.Allocator) MemoTable {
        return .{
            .entries = std.HashMap(MemoKey, MemoEntry, MemoKeyContext, 80).init(allocator),
            .stats = MemoStats.init(),
            .allocator = allocator,
            .max_entries = 10000,
        };
    }

    pub fn deinit(self: *MemoTable) void {
        self.entries.deinit();
    }

    pub fn get(self: *MemoTable, rule_name: []const u8, position: usize) ?MemoResult {
        const key = MemoKey{ .rule_name = rule_name, .position = position };

        if (self.entries.getPtr(key)) |entry| {
            entry.hit_count += 1;
            self.stats.hits += 1;
            return entry.result;
        }

        self.stats.misses += 1;
        return null;
    }

    pub fn put(self: *MemoTable, rule_name: []const u8, position: usize, result: MemoResult) !void {
        const key = MemoKey{ .rule_name = rule_name, .position = position };

        // Check if we need to evict
        if (self.entries.count() >= self.max_entries) {
            self.evictOldest();
        }

        try self.entries.put(key, .{
            .result = result,
            .timestamp = std.time.milliTimestamp(),
            .hit_count = 0,
        });
        self.stats.stores += 1;
    }

    pub fn contains(self: MemoTable, rule_name: []const u8, position: usize) bool {
        const key = MemoKey{ .rule_name = rule_name, .position = position };
        return self.entries.contains(key);
    }

    pub fn remove(self: *MemoTable, rule_name: []const u8, position: usize) bool {
        const key = MemoKey{ .rule_name = rule_name, .position = position };
        return self.entries.remove(key);
    }

    pub fn clear(self: *MemoTable) void {
        self.entries.clearRetainingCapacity();
        self.stats.evictions += self.entries.count();
    }

    pub fn invalidateFrom(self: *MemoTable, position: usize) usize {
        var count: usize = 0;
        var iter = self.entries.iterator();
        var to_remove = std.ArrayList(MemoKey).init(self.allocator);
        defer to_remove.deinit();

        while (iter.next()) |entry| {
            if (entry.key_ptr.position >= position) {
                to_remove.append(entry.key_ptr.*) catch continue;
            }
        }

        for (to_remove.items) |key| {
            if (self.entries.remove(key)) {
                count += 1;
            }
        }

        self.stats.evictions += count;
        return count;
    }

    fn evictOldest(self: *MemoTable) void {
        var oldest_key: ?MemoKey = null;
        var oldest_time: i64 = std.math.maxInt(i64);

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.timestamp < oldest_time) {
                oldest_time = entry.value_ptr.timestamp;
                oldest_key = entry.key_ptr.*;
            }
        }

        if (oldest_key) |key| {
            _ = self.entries.remove(key);
            self.stats.evictions += 1;
        }
    }

    pub fn count(self: MemoTable) usize {
        return self.entries.count();
    }

    pub fn getStats(self: MemoTable) MemoStats {
        return self.stats;
    }
};

/// Statistics for memo table performance
pub const MemoStats = struct {
    hits: usize,
    misses: usize,
    stores: usize,
    evictions: usize,

    pub fn init() MemoStats {
        return .{
            .hits = 0,
            .misses = 0,
            .stores = 0,
            .evictions = 0,
        };
    }

    pub fn hitRate(self: MemoStats) f64 {
        const total = self.hits + self.misses;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total));
    }

    pub fn totalAccesses(self: MemoStats) usize {
        return self.hits + self.misses;
    }

    pub fn reset(self: *MemoStats) void {
        self.* = MemoStats.init();
    }
};

/// LRU cache for frequently accessed memo entries
pub const LRUMemoCache = struct {
    capacity: usize,
    entries: std.ArrayList(CacheEntry),
    allocator: std.mem.Allocator,

    pub const CacheEntry = struct {
        key: MemoKey,
        result: MemoResult,
        access_order: usize,
    };

    pub fn init(allocator: std.mem.Allocator, capacity: usize) LRUMemoCache {
        return .{
            .capacity = capacity,
            .entries = std.ArrayList(CacheEntry).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LRUMemoCache) void {
        self.entries.deinit();
    }

    pub fn get(self: *LRUMemoCache, key: MemoKey) ?MemoResult {
        for (self.entries.items, 0..) |*entry, i| {
            if (entry.key.eql(key)) {
                // Move to front (update access order)
                const result = entry.result;
                _ = self.entries.orderedRemove(i);
                self.entries.append(.{
                    .key = key,
                    .result = result,
                    .access_order = 0,
                }) catch return result;
                return result;
            }
        }
        return null;
    }

    pub fn put(self: *LRUMemoCache, key: MemoKey, result: MemoResult) !void {
        // Remove oldest if at capacity
        if (self.entries.items.len >= self.capacity) {
            _ = self.entries.orderedRemove(0);
        }

        try self.entries.append(.{
            .key = key,
            .result = result,
            .access_order = 0,
        });
    }

    pub fn count(self: LRUMemoCache) usize {
        return self.entries.items.len;
    }

    pub fn clear(self: *LRUMemoCache) void {
        self.entries.clearRetainingCapacity();
    }
};

/// Memoizing parser wrapper
pub const MemoizingParser = struct {
    memo_table: MemoTable,
    lru_cache: LRUMemoCache,
    use_lru: bool,

    pub fn init(allocator: std.mem.Allocator) MemoizingParser {
        return .{
            .memo_table = MemoTable.init(allocator),
            .lru_cache = LRUMemoCache.init(allocator, 100),
            .use_lru = true,
        };
    }

    pub fn deinit(self: *MemoizingParser) void {
        self.memo_table.deinit();
        self.lru_cache.deinit();
    }

    pub fn memoize(self: *MemoizingParser, rule_name: []const u8, position: usize, result: MemoResult) !void {
        try self.memo_table.put(rule_name, position, result);
        if (self.use_lru) {
            const key = MemoKey{ .rule_name = rule_name, .position = position };
            try self.lru_cache.put(key, result);
        }
    }

    pub fn recall(self: *MemoizingParser, rule_name: []const u8, position: usize) ?MemoResult {
        // Check LRU first (faster)
        if (self.use_lru) {
            const key = MemoKey{ .rule_name = rule_name, .position = position };
            if (self.lru_cache.get(key)) |result| {
                return result;
            }
        }

        // Fall back to main table
        return self.memo_table.get(rule_name, position);
    }

    pub fn getStats(self: MemoizingParser) MemoStats {
        return self.memo_table.getStats();
    }
};

// Tests
test "memo_result_types" {
    const success = MemoResult{ .success = .{
        .value = "test",
        .start_pos = 0,
        .end_pos = 4,
        .rule_name = "expr",
    } };
    try std.testing.expect(success.isSuccess());
    try std.testing.expect(!success.isFailure());

    const failure = MemoResult{ .failure = .{
        .position = 0,
        .expected = "number",
        .rule_name = "expr",
    } };
    try std.testing.expect(failure.isFailure());

    const in_progress = MemoResult{ .in_progress = {} };
    try std.testing.expect(in_progress.isInProgress());
}

test "memo_success_length" {
    const success = MemoSuccess{
        .value = "hello",
        .start_pos = 5,
        .end_pos = 10,
        .rule_name = "word",
    };
    try std.testing.expectEqual(@as(usize, 5), success.length());
}

test "memo_key_hash_equality" {
    const key1 = MemoKey{ .rule_name = "expr", .position = 10 };
    const key2 = MemoKey{ .rule_name = "expr", .position = 10 };
    const key3 = MemoKey{ .rule_name = "expr", .position = 20 };
    const key4 = MemoKey{ .rule_name = "term", .position = 10 };

    try std.testing.expect(key1.eql(key2));
    try std.testing.expect(!key1.eql(key3));
    try std.testing.expect(!key1.eql(key4));
    try std.testing.expectEqual(key1.hash(), key2.hash());
}

test "memo_table_put_get" {
    var table = MemoTable.init(std.testing.allocator);
    defer table.deinit();

    const result = MemoResult{ .success = .{
        .value = "parsed",
        .start_pos = 0,
        .end_pos = 6,
        .rule_name = "test",
    } };

    try table.put("expr", 0, result);

    const retrieved = table.get("expr", 0);
    try std.testing.expect(retrieved != null);
    try std.testing.expect(retrieved.?.isSuccess());
}

test "memo_table_miss" {
    var table = MemoTable.init(std.testing.allocator);
    defer table.deinit();

    const result = table.get("nonexistent", 0);
    try std.testing.expect(result == null);
}

test "memo_table_contains" {
    var table = MemoTable.init(std.testing.allocator);
    defer table.deinit();

    try table.put("expr", 5, MemoResult{ .in_progress = {} });

    try std.testing.expect(table.contains("expr", 5));
    try std.testing.expect(!table.contains("expr", 10));
    try std.testing.expect(!table.contains("term", 5));
}

test "memo_table_remove" {
    var table = MemoTable.init(std.testing.allocator);
    defer table.deinit();

    try table.put("expr", 0, MemoResult{ .in_progress = {} });
    try std.testing.expect(table.contains("expr", 0));

    const removed = table.remove("expr", 0);
    try std.testing.expect(removed);
    try std.testing.expect(!table.contains("expr", 0));
}

test "memo_table_clear" {
    var table = MemoTable.init(std.testing.allocator);
    defer table.deinit();

    try table.put("a", 0, MemoResult{ .in_progress = {} });
    try table.put("b", 1, MemoResult{ .in_progress = {} });
    try table.put("c", 2, MemoResult{ .in_progress = {} });

    try std.testing.expectEqual(@as(usize, 3), table.count());

    table.clear();
    try std.testing.expectEqual(@as(usize, 0), table.count());
}

test "memo_table_stats" {
    var table = MemoTable.init(std.testing.allocator);
    defer table.deinit();

    // Miss
    _ = table.get("expr", 0);
    try std.testing.expectEqual(@as(usize, 1), table.stats.misses);

    // Store
    try table.put("expr", 0, MemoResult{ .in_progress = {} });
    try std.testing.expectEqual(@as(usize, 1), table.stats.stores);

    // Hit
    _ = table.get("expr", 0);
    try std.testing.expectEqual(@as(usize, 1), table.stats.hits);
}

test "memo_stats_hit_rate" {
    var stats = MemoStats.init();

    stats.hits = 75;
    stats.misses = 25;

    try std.testing.expect(stats.hitRate() == 0.75);
    try std.testing.expectEqual(@as(usize, 100), stats.totalAccesses());
}

test "memo_stats_hit_rate_zero" {
    const stats = MemoStats.init();
    try std.testing.expect(stats.hitRate() == 0.0);
}

test "lru_cache_put_get" {
    var cache = LRUMemoCache.init(std.testing.allocator, 3);
    defer cache.deinit();

    const key = MemoKey{ .rule_name = "expr", .position = 0 };
    const result = MemoResult{ .in_progress = {} };

    try cache.put(key, result);

    const retrieved = cache.get(key);
    try std.testing.expect(retrieved != null);
}

test "lru_cache_eviction" {
    var cache = LRUMemoCache.init(std.testing.allocator, 2);
    defer cache.deinit();

    const key1 = MemoKey{ .rule_name = "a", .position = 0 };
    const key2 = MemoKey{ .rule_name = "b", .position = 0 };
    const key3 = MemoKey{ .rule_name = "c", .position = 0 };

    try cache.put(key1, MemoResult{ .in_progress = {} });
    try cache.put(key2, MemoResult{ .in_progress = {} });
    try cache.put(key3, MemoResult{ .in_progress = {} });

    // key1 should have been evicted
    try std.testing.expect(cache.get(key1) == null);
    try std.testing.expect(cache.get(key3) != null);
}

test "lru_cache_count" {
    var cache = LRUMemoCache.init(std.testing.allocator, 10);
    defer cache.deinit();

    try std.testing.expectEqual(@as(usize, 0), cache.count());

    try cache.put(MemoKey{ .rule_name = "a", .position = 0 }, MemoResult{ .in_progress = {} });
    try std.testing.expectEqual(@as(usize, 1), cache.count());
}

test "memoizing_parser_basic" {
    var parser = MemoizingParser.init(std.testing.allocator);
    defer parser.deinit();

    const result = MemoResult{ .success = .{
        .value = "test",
        .start_pos = 0,
        .end_pos = 4,
        .rule_name = "expr",
    } };

    try parser.memoize("expr", 0, result);

    const recalled = parser.recall("expr", 0);
    try std.testing.expect(recalled != null);
    try std.testing.expect(recalled.?.isSuccess());
}

test "memoizing_parser_stats" {
    var parser = MemoizingParser.init(std.testing.allocator);
    defer parser.deinit();

    _ = parser.recall("expr", 0); // miss
    try parser.memoize("expr", 0, MemoResult{ .in_progress = {} });
    _ = parser.recall("expr", 0); // hit

    const stats = parser.getStats();
    try std.testing.expectEqual(@as(usize, 1), stats.hits);
    try std.testing.expectEqual(@as(usize, 1), stats.misses);
}

test "memo_table_invalidate_from" {
    var table = MemoTable.init(std.testing.allocator);
    defer table.deinit();

    try table.put("a", 0, MemoResult{ .in_progress = {} });
    try table.put("b", 5, MemoResult{ .in_progress = {} });
    try table.put("c", 10, MemoResult{ .in_progress = {} });
    try table.put("d", 15, MemoResult{ .in_progress = {} });

    // Invalidate from position 10
    const invalidated = table.invalidateFrom(10);
    try std.testing.expectEqual(@as(usize, 2), invalidated);

    try std.testing.expect(table.contains("a", 0));
    try std.testing.expect(table.contains("b", 5));
    try std.testing.expect(!table.contains("c", 10));
    try std.testing.expect(!table.contains("d", 15));
}
