//! GPU Hash Table for GROUP BY and Hash JOIN operations
//!
//! Uses Metal GPU kernels on macOS for parallel hash table operations:
//! - Build: Insert key-value pairs in parallel
//! - Probe: Look up keys in parallel
//! - Extract: Collect all key-value pairs
//!
//! On non-macOS platforms, falls back to CPU implementations.

const std = @import("std");
const builtin = @import("builtin");

/// Platform detection
pub const is_macos = builtin.os.tag == .macos;
pub const is_apple_silicon = is_macos and builtin.cpu.arch == .aarch64;

/// Hash table slot size in bytes: [key: u64, value: u64, occupied: u32, padding: u32]
pub const SLOT_SIZE: usize = 24;
pub const SLOT_UINTS: usize = SLOT_SIZE / 4;

/// GPU threshold - minimum size to use GPU
const GPU_THRESHOLD: usize = 10_000;

/// Metal C API bindings
const metal_c = if (is_macos) struct {
    extern fn lanceql_metal_init() c_int;
    extern fn lanceql_metal_hash_build(
        keys: [*]const u64,
        values: [*]const u64,
        table: [*]u32,
        capacity: c_uint,
        num_keys: c_uint,
    ) c_int;
    extern fn lanceql_metal_hash_probe(
        probe_keys: [*]const u64,
        table: [*]const u32,
        results: [*]u64,
        found: [*]c_int,
        capacity: c_uint,
        num_probes: c_uint,
    ) c_int;
    extern fn lanceql_metal_hash_extract(
        table: [*]const u32,
        out_keys: [*]u64,
        out_values: [*]u64,
        out_count: *c_uint,
        capacity: c_uint,
    ) c_int;
} else struct {};

/// Hash table errors
pub const HashTableError = error{
    OutOfMemory,
    TableFull,
    GPUError,
    InvalidCapacity,
};

/// Round up to next power of 2
fn nextPowerOfTwo(n: usize) usize {
    if (n == 0) return 1;
    var v = n - 1;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    v |= v >> 32;
    return v + 1;
}

/// FNV-1a hash for 64-bit keys
fn hashKey(key: u64) u64 {
    const FNV_PRIME: u64 = 0x100000001b3;
    const FNV_OFFSET: u64 = 0xcbf29ce484222325;

    var hash = FNV_OFFSET;
    hash ^= key;
    hash *%= FNV_PRIME;
    hash ^= (key >> 32);
    hash *%= FNV_PRIME;
    return hash;
}

/// GPU-accelerated hash table
/// Supports parallel build, probe, and extract operations
pub const GPUHashTable = struct {
    allocator: std.mem.Allocator,
    table: []u32, // [capacity * SLOT_UINTS]
    capacity: usize,
    count: usize,

    const Self = @This();

    /// Create a new hash table with given capacity (rounded to power of 2)
    pub fn init(allocator: std.mem.Allocator, min_capacity: usize) HashTableError!Self {
        const capacity = nextPowerOfTwo(@max(min_capacity, 16));
        const table = allocator.alloc(u32, capacity * SLOT_UINTS) catch
            return HashTableError.OutOfMemory;
        @memset(table, 0);

        return Self{
            .allocator = allocator,
            .table = table,
            .capacity = capacity,
            .count = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.table);
    }

    /// Build hash table from arrays of keys and values
    /// Uses GPU for large datasets on Apple Silicon
    pub fn build(self: *Self, keys: []const u64, values: []const u64) HashTableError!void {
        std.debug.assert(keys.len == values.len);

        // Check load factor - rehash if > 0.7
        const new_count = self.count + keys.len;
        if (new_count * 10 > self.capacity * 7) {
            try self.resize(nextPowerOfTwo(new_count * 2));
        }

        // GPU path for large batches on Apple Silicon
        if (comptime is_apple_silicon) {
            if (keys.len >= GPU_THRESHOLD) {
                if (self.gpuBuild(keys, values)) {
                    self.count = new_count;
                    return;
                }
            }
        }

        // CPU fallback
        try self.cpuBuild(keys, values);
        self.count = new_count;
    }

    /// Probe hash table for keys, return values and found flags
    pub fn probe(
        self: *const Self,
        probe_keys: []const u64,
        results: []u64,
        found: []bool,
    ) HashTableError!void {
        std.debug.assert(probe_keys.len == results.len);
        std.debug.assert(probe_keys.len == found.len);

        // GPU path
        if (comptime is_apple_silicon) {
            if (probe_keys.len >= GPU_THRESHOLD) {
                if (self.gpuProbe(probe_keys, results, found)) {
                    return;
                }
            }
        }

        // CPU fallback
        self.cpuProbe(probe_keys, results, found);
    }

    /// Extract all key-value pairs from the hash table
    pub fn extract(self: *const Self, out_keys: []u64, out_values: []u64) HashTableError!usize {
        std.debug.assert(out_keys.len >= self.count);
        std.debug.assert(out_values.len >= self.count);

        // GPU path
        if (comptime is_apple_silicon) {
            if (self.capacity >= GPU_THRESHOLD) {
                if (self.gpuExtract(out_keys, out_values)) |count| {
                    return count;
                }
            }
        }

        // CPU fallback
        return self.cpuExtract(out_keys, out_values);
    }

    /// Get a value for a single key (CPU only, for small lookups)
    pub fn get(self: *const Self, key: u64) ?u64 {
        const mask = self.capacity - 1;
        var slot = @as(usize, @truncate(hashKey(key))) & mask;

        var probes: usize = 0;
        while (probes < @min(self.capacity, 1024)) : (probes += 1) {
            const slot_base = slot * SLOT_UINTS;
            const occupied = self.table[slot_base + (16 / 4)];

            if (occupied == 0) return null;

            const slot_key = @as(*const u64, @ptrCast(@alignCast(&self.table[slot_base]))).*;
            if (slot_key == key) {
                return @as(*const u64, @ptrCast(@alignCast(&self.table[slot_base + 2]))).*;
            }

            slot = (slot + 1) & mask;
        }

        return null;
    }

    // =========================================================================
    // GPU implementations
    // =========================================================================

    fn gpuBuild(self: *Self, keys: []const u64, values: []const u64) bool {
        if (comptime !is_macos) return false;

        _ = metal_c.lanceql_metal_init();

        const result = metal_c.lanceql_metal_hash_build(
            keys.ptr,
            values.ptr,
            self.table.ptr,
            @intCast(self.capacity),
            @intCast(keys.len),
        );
        return result == 0;
    }

    fn gpuProbe(self: *const Self, probe_keys: []const u64, results: []u64, found: []bool) bool {
        if (comptime !is_macos) return false;

        // Metal uses c_int for found flags
        const found_ints = self.allocator.alloc(c_int, probe_keys.len) catch return false;
        defer self.allocator.free(found_ints);

        const result = metal_c.lanceql_metal_hash_probe(
            probe_keys.ptr,
            self.table.ptr,
            results.ptr,
            found_ints.ptr,
            @intCast(self.capacity),
            @intCast(probe_keys.len),
        );

        if (result != 0) return false;

        // Convert c_int to bool
        for (found_ints, 0..) |f, i| {
            found[i] = f != 0;
        }
        return true;
    }

    fn gpuExtract(self: *const Self, out_keys: []u64, out_values: []u64) ?usize {
        if (comptime !is_macos) return null;

        var count: c_uint = 0;
        const result = metal_c.lanceql_metal_hash_extract(
            self.table.ptr,
            out_keys.ptr,
            out_values.ptr,
            &count,
            @intCast(self.capacity),
        );

        if (result != 0) return null;
        return @intCast(count);
    }

    // =========================================================================
    // CPU fallback implementations
    // =========================================================================

    fn cpuBuild(self: *Self, keys: []const u64, values: []const u64) HashTableError!void {
        const mask = self.capacity - 1;

        for (keys, values) |key, value| {
            var slot = @as(usize, @truncate(hashKey(key))) & mask;
            var probes: usize = 0;

            while (probes < @min(self.capacity, 1024)) : (probes += 1) {
                const slot_base = slot * SLOT_UINTS;
                const occupied_ptr = &self.table[slot_base + (16 / 4)];

                if (occupied_ptr.* == 0) {
                    // Empty slot - claim it
                    const slot_key = @as(*u64, @ptrCast(@alignCast(&self.table[slot_base])));
                    const slot_val = @as(*u64, @ptrCast(@alignCast(&self.table[slot_base + 2])));
                    slot_key.* = key;
                    slot_val.* = value;
                    occupied_ptr.* = 1;
                    break;
                }

                // Check if same key (for aggregation)
                const existing_key = @as(*const u64, @ptrCast(@alignCast(&self.table[slot_base]))).*;
                if (existing_key == key) {
                    // Same key - add value (for SUM aggregation)
                    const slot_val = @as(*u64, @ptrCast(@alignCast(&self.table[slot_base + 2])));
                    slot_val.* +%= value;
                    break;
                }

                slot = (slot + 1) & mask;
            } else {
                return HashTableError.TableFull;
            }
        }
    }

    fn cpuProbe(self: *const Self, probe_keys: []const u64, results: []u64, found: []bool) void {
        const mask = self.capacity - 1;

        for (probe_keys, 0..) |key, i| {
            var slot = @as(usize, @truncate(hashKey(key))) & mask;
            var probes: usize = 0;

            found[i] = false;
            results[i] = 0;

            while (probes < @min(self.capacity, 1024)) : (probes += 1) {
                const slot_base = slot * SLOT_UINTS;
                const occupied = self.table[slot_base + (16 / 4)];

                if (occupied == 0) break;

                const slot_key = @as(*const u64, @ptrCast(@alignCast(&self.table[slot_base]))).*;
                if (slot_key == key) {
                    results[i] = @as(*const u64, @ptrCast(@alignCast(&self.table[slot_base + 2]))).*;
                    found[i] = true;
                    break;
                }

                slot = (slot + 1) & mask;
            }
        }
    }

    fn cpuExtract(self: *const Self, out_keys: []u64, out_values: []u64) usize {
        var count: usize = 0;

        for (0..self.capacity) |slot| {
            const slot_base = slot * SLOT_UINTS;
            const occupied = self.table[slot_base + (16 / 4)];

            if (occupied != 0) {
                out_keys[count] = @as(*const u64, @ptrCast(@alignCast(&self.table[slot_base]))).*;
                out_values[count] = @as(*const u64, @ptrCast(@alignCast(&self.table[slot_base + 2]))).*;
                count += 1;
            }
        }

        return count;
    }

    fn resize(self: *Self, new_capacity: usize) HashTableError!void {
        // Allocate new table
        const new_table = self.allocator.alloc(u32, new_capacity * SLOT_UINTS) catch
            return HashTableError.OutOfMemory;
        @memset(new_table, 0);

        // Rehash existing entries
        const old_table = self.table;
        const old_capacity = self.capacity;
        self.table = new_table;
        self.capacity = new_capacity;
        self.count = 0;

        const mask = new_capacity - 1;

        for (0..old_capacity) |slot| {
            const slot_base = slot * SLOT_UINTS;
            const occupied = old_table[slot_base + (16 / 4)];

            if (occupied != 0) {
                const key = @as(*const u64, @ptrCast(@alignCast(&old_table[slot_base]))).*;
                const value = @as(*const u64, @ptrCast(@alignCast(&old_table[slot_base + 2]))).*;

                // Insert into new table
                var new_slot = @as(usize, @truncate(hashKey(key))) & mask;
                var probes: usize = 0;

                while (probes < new_capacity) : (probes += 1) {
                    const new_slot_base = new_slot * SLOT_UINTS;
                    if (self.table[new_slot_base + (16 / 4)] == 0) {
                        const slot_key = @as(*u64, @ptrCast(@alignCast(&self.table[new_slot_base])));
                        const slot_val = @as(*u64, @ptrCast(@alignCast(&self.table[new_slot_base + 2])));
                        slot_key.* = key;
                        slot_val.* = value;
                        self.table[new_slot_base + (16 / 4)] = 1;
                        self.count += 1;
                        break;
                    }
                    new_slot = (new_slot + 1) & mask;
                }
            }
        }

        self.allocator.free(old_table);
    }
};

// =============================================================================
// Tests
// =============================================================================

test "GPUHashTable basic operations" {
    const allocator = std.testing.allocator;

    var ht = try GPUHashTable.init(allocator, 16);
    defer ht.deinit();

    // Build with some keys
    const keys = [_]u64{ 1, 2, 3, 4, 5 };
    const values = [_]u64{ 10, 20, 30, 40, 50 };

    try ht.build(&keys, &values);

    // Test get
    try std.testing.expectEqual(@as(?u64, 10), ht.get(1));
    try std.testing.expectEqual(@as(?u64, 30), ht.get(3));
    try std.testing.expectEqual(@as(?u64, null), ht.get(99));
}

test "GPUHashTable probe" {
    const allocator = std.testing.allocator;

    var ht = try GPUHashTable.init(allocator, 16);
    defer ht.deinit();

    const keys = [_]u64{ 100, 200, 300 };
    const values = [_]u64{ 1, 2, 3 };
    try ht.build(&keys, &values);

    // Probe
    const probe_keys = [_]u64{ 100, 200, 999 };
    var results: [3]u64 = undefined;
    var found: [3]bool = undefined;

    try ht.probe(&probe_keys, &results, &found);

    try std.testing.expect(found[0]);
    try std.testing.expect(found[1]);
    try std.testing.expect(!found[2]);
    try std.testing.expectEqual(@as(u64, 1), results[0]);
    try std.testing.expectEqual(@as(u64, 2), results[1]);
}

test "GPUHashTable extract" {
    const allocator = std.testing.allocator;

    var ht = try GPUHashTable.init(allocator, 16);
    defer ht.deinit();

    const keys = [_]u64{ 10, 20, 30 };
    const values = [_]u64{ 100, 200, 300 };
    try ht.build(&keys, &values);

    var out_keys: [16]u64 = undefined;
    var out_values: [16]u64 = undefined;

    const count = try ht.extract(&out_keys, &out_values);
    try std.testing.expectEqual(@as(usize, 3), count);

    // Verify all keys were extracted (order may differ)
    var found_count: usize = 0;
    for (out_keys[0..count]) |k| {
        if (k == 10 or k == 20 or k == 30) found_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), found_count);
}

test "GPUHashTable aggregation (same key)" {
    const allocator = std.testing.allocator;

    var ht = try GPUHashTable.init(allocator, 16);
    defer ht.deinit();

    // Same key multiple times - values should be summed
    const keys = [_]u64{ 1, 1, 1 };
    const values = [_]u64{ 10, 20, 30 };
    try ht.build(&keys, &values);

    try std.testing.expectEqual(@as(?u64, 60), ht.get(1));
}

test "GPUHashTable resize" {
    const allocator = std.testing.allocator;

    var ht = try GPUHashTable.init(allocator, 4);
    defer ht.deinit();

    // Insert more than capacity to trigger resize
    var keys: [20]u64 = undefined;
    var values: [20]u64 = undefined;
    for (0..20) |i| {
        keys[i] = @intCast(i);
        values[i] = @intCast(i * 10);
    }

    try ht.build(&keys, &values);

    // Verify all keys are still accessible
    for (0..20) |i| {
        try std.testing.expectEqual(@as(?u64, @intCast(i * 10)), ht.get(@intCast(i)));
    }
}
