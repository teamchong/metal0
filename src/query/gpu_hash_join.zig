//! GPU-accelerated Hash JOIN operations
//!
//! Uses Metal GPU hash tables for parallel join on macOS.
//! Falls back to CPU implementation on other platforms.
//!
//! Supports:
//! - INNER JOIN on int64 keys
//! - LEFT OUTER JOIN
//! - Build-probe pattern for efficient joining
//!
//! Usage:
//! ```zig
//! var hash_join = try GPUHashJoin.init(allocator);
//! defer hash_join.deinit();
//!
//! // Build phase: index the smaller table
//! try hash_join.build(build_keys, build_row_ids);
//!
//! // Probe phase: find matches from the larger table
//! const results = try hash_join.innerJoin(probe_keys, probe_row_ids);
//! defer allocator.free(results.build_indices);
//! defer allocator.free(results.probe_indices);
//! ```

const std = @import("std");
const metal = @import("lanceql.metal");

/// Join result containing matching row indices from both tables
pub const JoinResult = struct {
    /// Row indices from the build table (right side)
    build_indices: []usize,
    /// Row indices from the probe table (left side)
    probe_indices: []usize,
    /// Number of matching pairs
    count: usize,
};

/// Left outer join result with null indicators
pub const LeftJoinResult = struct {
    /// Row indices from the build table (right side), 0 for no match
    build_indices: []usize,
    /// Row indices from the probe table (left side)
    probe_indices: []usize,
    /// true if this probe row had a match
    matched: []bool,
    /// Number of result rows (same as probe table rows for left join)
    count: usize,
};

/// GPU-accelerated Hash JOIN for int64 keys
pub const GPUHashJoin = struct {
    allocator: std.mem.Allocator,
    hash_table: metal.GPUHashTable,
    /// Stores build row IDs for lookup (value in hash table is index into this)
    build_row_ids: ?[]const usize,

    const Self = @This();

    /// Initialize Hash JOIN
    pub fn init(allocator: std.mem.Allocator) metal.HashTableError!Self {
        return Self{
            .allocator = allocator,
            .hash_table = try metal.GPUHashTable.init(allocator, 1024),
            .build_row_ids = null,
        };
    }

    /// Initialize with capacity hint for build table size
    pub fn initWithCapacity(allocator: std.mem.Allocator, build_size: usize) metal.HashTableError!Self {
        return Self{
            .allocator = allocator,
            // Use 4x capacity for good load factor
            .hash_table = try metal.GPUHashTable.init(allocator, build_size * 4),
            .build_row_ids = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.hash_table.deinit();
    }

    /// Build phase: Create hash table from build keys
    /// Stores row indices (0..n) as values
    ///
    /// Note: For duplicate keys, only the last row ID is retained.
    /// For full duplicate handling, use buildWithDuplicates.
    pub fn build(self: *Self, keys: []const u64, row_ids: []const usize) metal.HashTableError!void {
        std.debug.assert(keys.len == row_ids.len);

        self.build_row_ids = row_ids;

        // Convert row IDs to u64 for hash table
        const values = self.allocator.alloc(u64, keys.len) catch
            return metal.HashTableError.OutOfMemory;
        defer self.allocator.free(values);

        for (row_ids, 0..) |row_id, i| {
            values[i] = @intCast(row_id);
        }

        try self.hash_table.build(keys, values);
    }

    /// Inner join: Return only matching rows from both tables
    pub fn innerJoin(self: *Self, probe_keys: []const u64, probe_row_ids: []const usize) metal.HashTableError!JoinResult {
        std.debug.assert(probe_keys.len == probe_row_ids.len);

        // Probe the hash table
        const probe_results = self.allocator.alloc(u64, probe_keys.len) catch
            return metal.HashTableError.OutOfMemory;
        defer self.allocator.free(probe_results);

        const found = self.allocator.alloc(bool, probe_keys.len) catch
            return metal.HashTableError.OutOfMemory;
        defer self.allocator.free(found);

        try self.hash_table.probe(probe_keys, probe_results, found);

        // Count matches
        var match_count: usize = 0;
        for (found) |f| {
            if (f) match_count += 1;
        }

        // Allocate result arrays
        const build_indices = self.allocator.alloc(usize, match_count) catch
            return metal.HashTableError.OutOfMemory;
        errdefer self.allocator.free(build_indices);

        const probe_indices = self.allocator.alloc(usize, match_count) catch {
            self.allocator.free(build_indices);
            return metal.HashTableError.OutOfMemory;
        };
        errdefer self.allocator.free(probe_indices);

        // Fill result arrays
        var result_idx: usize = 0;
        for (found, 0..) |f, i| {
            if (f) {
                build_indices[result_idx] = @intCast(probe_results[i]);
                probe_indices[result_idx] = probe_row_ids[i];
                result_idx += 1;
            }
        }

        return JoinResult{
            .build_indices = build_indices,
            .probe_indices = probe_indices,
            .count = match_count,
        };
    }

    /// Left outer join: Return all probe rows, with nulls for non-matches
    pub fn leftJoin(self: *Self, probe_keys: []const u64, probe_row_ids: []const usize) metal.HashTableError!LeftJoinResult {
        std.debug.assert(probe_keys.len == probe_row_ids.len);

        // Probe the hash table
        const probe_results = self.allocator.alloc(u64, probe_keys.len) catch
            return metal.HashTableError.OutOfMemory;
        defer self.allocator.free(probe_results);

        const found = self.allocator.alloc(bool, probe_keys.len) catch
            return metal.HashTableError.OutOfMemory;
        defer self.allocator.free(found);

        try self.hash_table.probe(probe_keys, probe_results, found);

        // Allocate result arrays (same size as probe table)
        const build_indices = self.allocator.alloc(usize, probe_keys.len) catch
            return metal.HashTableError.OutOfMemory;
        errdefer self.allocator.free(build_indices);

        const probe_indices = self.allocator.alloc(usize, probe_keys.len) catch {
            self.allocator.free(build_indices);
            return metal.HashTableError.OutOfMemory;
        };
        errdefer self.allocator.free(probe_indices);

        const matched = self.allocator.alloc(bool, probe_keys.len) catch {
            self.allocator.free(build_indices);
            self.allocator.free(probe_indices);
            return metal.HashTableError.OutOfMemory;
        };

        // Fill result arrays
        for (0..probe_keys.len) |i| {
            probe_indices[i] = probe_row_ids[i];
            matched[i] = found[i];
            if (found[i]) {
                build_indices[i] = @intCast(probe_results[i]);
            } else {
                build_indices[i] = 0; // Null indicator (caller uses matched[] to distinguish)
            }
        }

        return LeftJoinResult{
            .build_indices = build_indices,
            .probe_indices = probe_indices,
            .matched = matched,
            .count = probe_keys.len,
        };
    }

    /// Check if a key exists in the build table
    pub fn contains(self: *const Self, key: u64) bool {
        return self.hash_table.get(key) != null;
    }

    /// Get the build row ID for a key (or null if not found)
    pub fn getBuildRow(self: *const Self, key: u64) ?usize {
        if (self.hash_table.get(key)) |row_id| {
            return @intCast(row_id);
        }
        return null;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "GPUHashJoin inner join basic" {
    const allocator = std.testing.allocator;

    var hash_join = try GPUHashJoin.init(allocator);
    defer hash_join.deinit();

    // Build table: keys 10, 20, 30 with row IDs 0, 1, 2
    const build_keys = [_]u64{ 10, 20, 30 };
    const build_row_ids = [_]usize{ 0, 1, 2 };
    try hash_join.build(&build_keys, &build_row_ids);

    // Probe table: keys 20, 30, 40 with row IDs 100, 101, 102
    const probe_keys = [_]u64{ 20, 30, 40 };
    const probe_row_ids = [_]usize{ 100, 101, 102 };

    const result = try hash_join.innerJoin(&probe_keys, &probe_row_ids);
    defer allocator.free(result.build_indices);
    defer allocator.free(result.probe_indices);

    // Should match: (20 -> 1, 100), (30 -> 2, 101)
    try std.testing.expectEqual(@as(usize, 2), result.count);

    // Verify matches (order may vary based on probing)
    var found_20 = false;
    var found_30 = false;
    for (0..result.count) |i| {
        if (result.probe_indices[i] == 100) {
            try std.testing.expectEqual(@as(usize, 1), result.build_indices[i]);
            found_20 = true;
        }
        if (result.probe_indices[i] == 101) {
            try std.testing.expectEqual(@as(usize, 2), result.build_indices[i]);
            found_30 = true;
        }
    }
    try std.testing.expect(found_20);
    try std.testing.expect(found_30);
}

test "GPUHashJoin left join" {
    const allocator = std.testing.allocator;

    var hash_join = try GPUHashJoin.init(allocator);
    defer hash_join.deinit();

    // Build table: keys 10, 20 with row IDs 0, 1
    const build_keys = [_]u64{ 10, 20 };
    const build_row_ids = [_]usize{ 0, 1 };
    try hash_join.build(&build_keys, &build_row_ids);

    // Probe table: keys 10, 30 with row IDs 100, 101
    const probe_keys = [_]u64{ 10, 30 };
    const probe_row_ids = [_]usize{ 100, 101 };

    const result = try hash_join.leftJoin(&probe_keys, &probe_row_ids);
    defer allocator.free(result.build_indices);
    defer allocator.free(result.probe_indices);
    defer allocator.free(result.matched);

    // Left join: all probe rows returned
    try std.testing.expectEqual(@as(usize, 2), result.count);

    // Row 100 (key 10) should match
    try std.testing.expectEqual(@as(usize, 100), result.probe_indices[0]);
    try std.testing.expect(result.matched[0]);
    try std.testing.expectEqual(@as(usize, 0), result.build_indices[0]);

    // Row 101 (key 30) should not match
    try std.testing.expectEqual(@as(usize, 101), result.probe_indices[1]);
    try std.testing.expect(!result.matched[1]);
}

test "GPUHashJoin contains and getBuildRow" {
    const allocator = std.testing.allocator;

    var hash_join = try GPUHashJoin.init(allocator);
    defer hash_join.deinit();

    const build_keys = [_]u64{ 100, 200, 300 };
    const build_row_ids = [_]usize{ 5, 10, 15 };
    try hash_join.build(&build_keys, &build_row_ids);

    // Test contains
    try std.testing.expect(hash_join.contains(100));
    try std.testing.expect(hash_join.contains(200));
    try std.testing.expect(!hash_join.contains(400));

    // Test getBuildRow
    try std.testing.expectEqual(@as(?usize, 5), hash_join.getBuildRow(100));
    try std.testing.expectEqual(@as(?usize, 10), hash_join.getBuildRow(200));
    try std.testing.expectEqual(@as(?usize, 15), hash_join.getBuildRow(300));
    try std.testing.expectEqual(@as(?usize, null), hash_join.getBuildRow(999));
}

test "GPUHashJoin large join" {
    const allocator = std.testing.allocator;

    // Build table: 500 rows
    const build_size: usize = 500;
    var hash_join = try GPUHashJoin.initWithCapacity(allocator, build_size);
    defer hash_join.deinit();

    var build_keys = try allocator.alloc(u64, build_size);
    defer allocator.free(build_keys);
    var build_row_ids = try allocator.alloc(usize, build_size);
    defer allocator.free(build_row_ids);

    for (0..build_size) |i| {
        build_keys[i] = @intCast(i * 2); // Even keys: 0, 2, 4, ...
        build_row_ids[i] = i;
    }
    try hash_join.build(build_keys, build_row_ids);

    // Probe table: 1000 rows (all keys 0-999)
    const probe_size: usize = 1000;
    var probe_keys = try allocator.alloc(u64, probe_size);
    defer allocator.free(probe_keys);
    var probe_row_ids = try allocator.alloc(usize, probe_size);
    defer allocator.free(probe_row_ids);

    for (0..probe_size) |i| {
        probe_keys[i] = @intCast(i);
        probe_row_ids[i] = i + 10000;
    }

    const result = try hash_join.innerJoin(probe_keys, probe_row_ids);
    defer allocator.free(result.build_indices);
    defer allocator.free(result.probe_indices);

    // Should match all even keys: 0, 2, 4, ..., 998 = 500 matches
    try std.testing.expectEqual(@as(usize, 500), result.count);
}
