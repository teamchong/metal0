/// Generic hash table implementation (comptime configurable)
///
/// Pattern: Write once, specialize many!
/// - Native dicts (no refcount)
/// - PyObject dicts (with refcount)
/// - Different hash functions (wyhash, tp_hash)
/// - Zero runtime cost (comptime specialization)

const std = @import("std");

/// Generic dictionary implementation
///
/// Config must provide:
/// - KeyType: type
/// - ValueType: type
/// - hashKey(key: KeyType) u64
/// - keysEqual(a: KeyType, b: KeyType) bool
/// - retainKey(key: KeyType) KeyType
/// - releaseKey(key: KeyType) void
/// - retainValue(val: ValueType) ValueType
/// - releaseValue(val: ValueType) void
pub fn DictImpl(comptime Config: type) type {
    return struct {
        const Self = @This();

        entries: []Entry,
        size: usize,
        capacity: usize,
        allocator: std.mem.Allocator,

        const Entry = struct {
            key: Config.KeyType,
            value: Config.ValueType,
            hash: u64,
            used: bool,
            deleted: bool, // Tombstone for open addressing
        };

        /// Initialize empty dict
        pub fn init(allocator: std.mem.Allocator) !Self {
            const initial_capacity = 8;
            const entries = try allocator.alloc(Entry, initial_capacity);

            for (entries) |*entry| {
                entry.* = .{
                    .key = undefined,
                    .value = undefined,
                    .hash = 0,
                    .used = false,
                    .deleted = false,
                };
            }

            return Self{
                .entries = entries,
                .size = 0,
                .capacity = initial_capacity,
                .allocator = allocator,
            };
        }

        /// Set key-value pair
        pub fn set(self: *Self, key: Config.KeyType, value: Config.ValueType) !void {
            // Check load factor (resize at 75%)
            if (self.size * 4 >= self.capacity * 3) {
                try self.resize();
            }

            const hash = Config.hashKey(key);
            var idx = hash % self.capacity;
            var probe_count: usize = 0;

            // Linear probing with tombstones
            while (probe_count < self.capacity) : (probe_count += 1) {
                const entry = &self.entries[idx];

                if (!entry.used) {
                    // Empty slot - insert new
                    entry.* = .{
                        .key = Config.retainKey(key),
                        .value = Config.retainValue(value),
                        .hash = hash,
                        .used = true,
                        .deleted = false,
                    };
                    self.size += 1;
                    return;
                }

                if (entry.hash == hash and Config.keysEqual(entry.key, key)) {
                    // Update existing
                    Config.releaseValue(entry.value);
                    entry.value = Config.retainValue(value);
                    return;
                }

                // Continue probing
                idx = (idx + 1) % self.capacity;
            }

            // Should never reach here (resize prevents this)
            return error.TableFull;
        }

        /// Get value by key
        pub fn get(self: *Self, key: Config.KeyType) ?Config.ValueType {
            const hash = Config.hashKey(key);
            var idx = hash % self.capacity;
            var probe_count: usize = 0;

            while (probe_count < self.capacity) : (probe_count += 1) {
                const entry = &self.entries[idx];

                if (!entry.used and !entry.deleted) {
                    // Empty slot, not found
                    return null;
                }

                if (entry.used and entry.hash == hash and Config.keysEqual(entry.key, key)) {
                    return entry.value;
                }

                // Continue probing
                idx = (idx + 1) % self.capacity;
            }

            return null;
        }

        /// Check if key exists
        pub fn contains(self: *Self, key: Config.KeyType) bool {
            return self.get(key) != null;
        }

        /// Delete key-value pair
        pub fn delete(self: *Self, key: Config.KeyType) bool {
            const hash = Config.hashKey(key);
            var idx = hash % self.capacity;
            var probe_count: usize = 0;

            while (probe_count < self.capacity) : (probe_count += 1) {
                const entry = &self.entries[idx];

                if (!entry.used and !entry.deleted) {
                    // Not found
                    return false;
                }

                if (entry.used and entry.hash == hash and Config.keysEqual(entry.key, key)) {
                    // Found - mark as deleted (tombstone)
                    Config.releaseKey(entry.key);
                    Config.releaseValue(entry.value);
                    entry.used = false;
                    entry.deleted = true;
                    self.size -= 1;
                    return true;
                }

                // Continue probing
                idx = (idx + 1) % self.capacity;
            }

            return false;
        }

        /// Clear all entries
        pub fn clear(self: *Self) void {
            for (self.entries) |*entry| {
                if (entry.used) {
                    Config.releaseKey(entry.key);
                    Config.releaseValue(entry.value);
                }
                entry.* = .{
                    .key = undefined,
                    .value = undefined,
                    .hash = 0,
                    .used = false,
                    .deleted = false,
                };
            }
            self.size = 0;
        }

        /// Free all resources
        pub fn deinit(self: *Self) void {
            for (self.entries) |*entry| {
                if (entry.used) {
                    Config.releaseKey(entry.key);
                    Config.releaseValue(entry.value);
                }
            }
            self.allocator.free(self.entries);
        }

        /// Resize hash table (double capacity)
        fn resize(self: *Self) !void {
            const new_capacity = self.capacity * 2;
            const new_entries = try self.allocator.alloc(Entry, new_capacity);

            // Initialize new entries
            for (new_entries) |*entry| {
                entry.* = .{
                    .key = undefined,
                    .value = undefined,
                    .hash = 0,
                    .used = false,
                    .deleted = false,
                };
            }

            // Rehash all entries
            for (self.entries) |entry| {
                if (entry.used) {
                    var idx = entry.hash % new_capacity;
                    var probe_count: usize = 0;

                    while (probe_count < new_capacity) : (probe_count += 1) {
                        if (!new_entries[idx].used) {
                            new_entries[idx] = entry;
                            break;
                        }
                        idx = (idx + 1) % new_capacity;
                    }
                }
            }

            // Free old entries
            self.allocator.free(self.entries);

            // Update to new table
            self.entries = new_entries;
            self.capacity = new_capacity;
        }

        /// Iterator over key-value pairs
        pub const Iterator = struct {
            dict: *Self,
            index: usize,

            pub fn next(iter: *Iterator) ?struct { key: Config.KeyType, value: Config.ValueType } {
                while (iter.index < iter.dict.capacity) {
                    const entry = &iter.dict.entries[iter.index];
                    iter.index += 1;

                    if (entry.used) {
                        return .{ .key = entry.key, .value = entry.value };
                    }
                }

                return null;
            }
        };

        pub fn iterator(self: *Self) Iterator {
            return Iterator{
                .dict = self,
                .index = 0,
            };
        }
    };
}

// ============================================================================
//                         EXAMPLE CONFIGS
// ============================================================================

/// Native string-keyed dict (no refcount)
pub const NativeStringDictConfig = struct {
    pub const KeyType = []const u8;
    pub const ValueType = []const u8;

    pub fn hashKey(key: []const u8) u64 {
        // Use std.hash for now (can optimize with wyhash later)
        return std.hash.Wyhash.hash(0, key);
    }

    pub fn keysEqual(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }

    pub fn retainKey(key: []const u8) []const u8 {
        return key; // No refcount for native
    }

    pub fn releaseKey(key: []const u8) void {
        _ = key; // No refcount for native
    }

    pub fn retainValue(val: []const u8) []const u8 {
        return val; // No refcount for native
    }

    pub fn releaseValue(val: []const u8) void {
        _ = val; // No refcount for native
    }
};

/// PyObject dict config (with refcount)
/// NOTE: Actual implementation in pyobject_dict.zig
pub fn PyObjectDictConfig(comptime PyObject: type) type {
    return struct {
        pub const KeyType = *PyObject;
        pub const ValueType = *PyObject;

        pub fn hashKey(key: *PyObject) u64 {
            // For now: identity hash
            // TODO: Call tp_hash slot
            return @intFromPtr(key);
        }

        pub fn keysEqual(a: *PyObject, b: *PyObject) bool {
            // For now: pointer equality
            // TODO: Call tp_richcompare slot
            return a == b;
        }

        pub fn retainKey(key: *PyObject) *PyObject {
            key.ob_refcnt += 1; // INCREF
            return key;
        }

        pub fn releaseKey(key: *PyObject) void {
            key.ob_refcnt -= 1; // DECREF
            // TODO: Dealloc if refcnt == 0
        }

        pub fn retainValue(val: *PyObject) *PyObject {
            val.ob_refcnt += 1; // INCREF
            return val;
        }

        pub fn releaseValue(val: *PyObject) void {
            val.ob_refcnt -= 1; // DECREF
            // TODO: Dealloc if refcnt == 0
        }
    };
}

// ============================================================================
//                              TESTS
// ============================================================================

test "DictImpl - native string dict" {
    const Dict = DictImpl(NativeStringDictConfig);

    var dict = try Dict.init(std.testing.allocator);
    defer dict.deinit();

    // Test set/get
    try dict.set("foo", "bar");
    const val1 = dict.get("foo");
    try std.testing.expect(val1 != null);
    try std.testing.expectEqualStrings("bar", val1.?);

    // Test update
    try dict.set("foo", "baz");
    const val2 = dict.get("foo");
    try std.testing.expectEqualStrings("baz", val2.?);

    // Test multiple keys
    try dict.set("key1", "value1");
    try dict.set("key2", "value2");
    try std.testing.expectEqual(@as(usize, 3), dict.size);

    // Test delete
    try std.testing.expect(dict.delete("foo"));
    try std.testing.expectEqual(@as(usize, 2), dict.size);
    try std.testing.expect(dict.get("foo") == null);

    // Test contains
    try std.testing.expect(dict.contains("key1"));
    try std.testing.expect(!dict.contains("notfound"));
}

test "DictImpl - resize" {
    const Dict = DictImpl(NativeStringDictConfig);

    var dict = try Dict.init(std.testing.allocator);
    defer dict.deinit();

    // Insert many items to trigger resize
    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const key = try std.fmt.allocPrint(std.testing.allocator, "key{d}", .{i});
        defer std.testing.allocator.free(key);

        const value = try std.fmt.allocPrint(std.testing.allocator, "value{d}", .{i});
        defer std.testing.allocator.free(value);

        try dict.set(key, value);
    }

    try std.testing.expectEqual(@as(usize, 20), dict.size);

    // Verify all items still accessible
    i = 0;
    while (i < 20) : (i += 1) {
        const key = try std.fmt.allocPrint(std.testing.allocator, "key{d}", .{i});
        defer std.testing.allocator.free(key);

        try std.testing.expect(dict.contains(key));
    }
}

test "DictImpl - iterator" {
    const Dict = DictImpl(NativeStringDictConfig);

    var dict = try Dict.init(std.testing.allocator);
    defer dict.deinit();

    try dict.set("a", "1");
    try dict.set("b", "2");
    try dict.set("c", "3");

    var count: usize = 0;
    var iter = dict.iterator();
    while (iter.next()) |_| {
        count += 1;
    }

    try std.testing.expectEqual(@as(usize, 3), count);
}
