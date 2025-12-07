/// hamt - Hash Array Mapped Trie
/// Mirrors cpython/Python/hamt.c
///
/// This module provides an immutable mapping using HAMT:
/// - O(1) copy via structural sharing
/// - O(log N) set/delete operations
/// - O(log N) lookups
/// - Memory efficient via bitmap compression

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Constants
// ============================================================================

/// Bits per level of the trie
pub const BITS_PER_LEVEL: u5 = 5;

/// Number of children per full node (2^5 = 32)
pub const BRANCH_FACTOR: usize = 1 << BITS_PER_LEVEL;

/// Mask for extracting bits at each level
pub const LEVEL_MASK: u32 = BRANCH_FACTOR - 1;

/// Maximum depth of the trie
pub const MAX_DEPTH: usize = 7; // 32 bits / 5 bits per level + collision level

/// Threshold for switching from bitmap to array node
pub const BITMAP_TO_ARRAY_THRESHOLD: usize = 16;

// ============================================================================
// Node Types
// ============================================================================

/// Generic key-value pair
pub fn KVPair(comptime K: type, comptime V: type) type {
    return struct {
        key: K,
        value: V,
        hash: u32,
    };
}

/// HAMT Node (immutable)
pub fn HamtNode(comptime K: type, comptime V: type) type {
    return union(enum) {
        bitmap: BitmapNode(K, V),
        array: ArrayNode(K, V),
        collision: CollisionNode(K, V),
        leaf: LeafNode(K, V),

        const Self = @This();

        pub fn deinit(self: *Self, allocator: Allocator) void {
            switch (self.*) {
                .bitmap => |*b| b.deinit(allocator),
                .array => |*a| a.deinit(allocator),
                .collision => |*c| c.deinit(allocator),
                .leaf => {}, // Nothing to free
            }
        }
    };
}

/// Leaf node - stores a single key-value pair
pub fn LeafNode(comptime K: type, comptime V: type) type {
    return struct {
        key: K,
        value: V,
        hash: u32,
    };
}

/// Bitmap node - compressed sparse array
pub fn BitmapNode(comptime K: type, comptime V: type) type {
    return struct {
        bitmap: u32, // Which positions are occupied
        entries: []Entry, // Compressed array of entries

        const Self = @This();
        const Node = HamtNode(K, V);

        pub const Entry = union(enum) {
            kv: struct { key: K, value: V },
            node: *Node,
        };

        pub fn init(allocator: Allocator, bitmap: u32, count: usize) !Self {
            return .{
                .bitmap = bitmap,
                .entries = try allocator.alloc(Entry, count),
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            for (self.entries) |*entry| {
                switch (entry.*) {
                    .node => |node| {
                        node.deinit(allocator);
                        allocator.destroy(node);
                    },
                    .kv => {},
                }
            }
            allocator.free(self.entries);
        }

        pub fn count(self: Self) usize {
            return @popCount(self.bitmap);
        }

        pub fn hasIndex(self: Self, idx: u5) bool {
            return (self.bitmap & (@as(u32, 1) << idx)) != 0;
        }

        pub fn getPosition(self: Self, idx: u5) usize {
            const mask = (@as(u32, 1) << idx) - 1;
            return @popCount(self.bitmap & mask);
        }

        pub fn get(self: Self, idx: u5) ?Entry {
            if (!self.hasIndex(idx)) return null;
            return self.entries[self.getPosition(idx)];
        }
    };
}

/// Array node - full 32-element array
pub fn ArrayNode(comptime K: type, comptime V: type) type {
    return struct {
        children: [BRANCH_FACTOR]?*HamtNode(K, V),
        count: usize, // Number of non-null children

        const Self = @This();
        const Node = HamtNode(K, V);

        pub fn init() Self {
            return .{
                .children = [_]?*Node{null} ** BRANCH_FACTOR,
                .count = 0,
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            for (&self.children) |*child_ptr| {
                if (child_ptr.*) |child| {
                    child.deinit(allocator);
                    allocator.destroy(child);
                }
            }
        }
    };
}

/// Collision node - handles hash collisions
pub fn CollisionNode(comptime K: type, comptime V: type) type {
    return struct {
        hash: u32, // Common hash value
        pairs: []KVPair(K, V),

        const Self = @This();
        const Pair = KVPair(K, V);

        pub fn init(allocator: Allocator, hash: u32, capacity: usize) !Self {
            return .{
                .hash = hash,
                .pairs = try allocator.alloc(Pair, capacity),
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.pairs);
        }

        pub fn find(self: Self, key: K, eql: fn (K, K) bool) ?V {
            for (self.pairs) |pair| {
                if (eql(pair.key, key)) {
                    return pair.value;
                }
            }
            return null;
        }
    };
}

// ============================================================================
// HAMT Map
// ============================================================================

/// Immutable Hash Array Mapped Trie
pub fn Hamt(comptime K: type, comptime V: type) type {
    return struct {
        allocator: Allocator,
        root: ?*Node,
        len: usize,
        hash_fn: *const fn (K) u32,
        eql_fn: *const fn (K, K) bool,

        const Self = @This();
        const Node = HamtNode(K, V);
        const Bitmap = BitmapNode(K, V);
        const Array = ArrayNode(K, V);
        const Collision = CollisionNode(K, V);
        const Leaf = LeafNode(K, V);

        /// Create empty HAMT
        pub fn init(
            allocator: Allocator,
            hash_fn: *const fn (K) u32,
            eql_fn: *const fn (K, K) bool,
        ) Self {
            return .{
                .allocator = allocator,
                .root = null,
                .len = 0,
                .hash_fn = hash_fn,
                .eql_fn = eql_fn,
            };
        }

        /// Free all nodes
        pub fn deinit(self: *Self) void {
            if (self.root) |root| {
                root.deinit(self.allocator);
                self.allocator.destroy(root);
            }
        }

        /// Get value for key
        pub fn get(self: Self, key: K) ?V {
            if (self.root == null) return null;

            const hash = self.hash_fn(key);
            return self.lookup(self.root.?, hash, key, 0);
        }

        fn lookup(self: Self, node: *Node, hash: u32, key: K, shift: u5) ?V {
            switch (node.*) {
                .leaf => |leaf| {
                    if (leaf.hash == hash and self.eql_fn(leaf.key, key)) {
                        return leaf.value;
                    }
                    return null;
                },
                .bitmap => |bm| {
                    const idx: u5 = @truncate((hash >> shift) & LEVEL_MASK);
                    const entry = bm.get(idx) orelse return null;
                    switch (entry) {
                        .kv => |kv| {
                            if (self.eql_fn(kv.key, key)) {
                                return kv.value;
                            }
                            return null;
                        },
                        .node => |child| {
                            return self.lookup(child, hash, key, shift +| BITS_PER_LEVEL);
                        },
                    }
                },
                .array => |arr| {
                    const idx: u5 = @truncate((hash >> shift) & LEVEL_MASK);
                    const child = arr.children[idx] orelse return null;
                    return self.lookup(child, hash, key, shift +| BITS_PER_LEVEL);
                },
                .collision => |col| {
                    return col.find(key, self.eql_fn);
                },
            }
        }

        /// Set a key-value pair, returning new HAMT
        pub fn set(self: Self, key: K, value: V) !Self {
            const hash = self.hash_fn(key);

            var new_root: *Node = undefined;
            var added: bool = undefined;

            if (self.root) |root| {
                const result = try self.insert(root, hash, key, value, 0);
                new_root = result.node;
                added = result.added;
            } else {
                // Create leaf node
                new_root = try self.allocator.create(Node);
                new_root.* = .{ .leaf = .{
                    .key = key,
                    .value = value,
                    .hash = hash,
                } };
                added = true;
            }

            return .{
                .allocator = self.allocator,
                .root = new_root,
                .len = if (added) self.len + 1 else self.len,
                .hash_fn = self.hash_fn,
                .eql_fn = self.eql_fn,
            };
        }

        const InsertResult = struct {
            node: *Node,
            added: bool, // True if new key was added
        };

        fn insert(self: Self, node: *Node, hash: u32, key: K, value: V, shift: u5) !InsertResult {
            switch (node.*) {
                .leaf => |leaf| {
                    if (leaf.hash == hash) {
                        if (self.eql_fn(leaf.key, key)) {
                            // Replace value
                            const new_node = try self.allocator.create(Node);
                            new_node.* = .{ .leaf = .{
                                .key = key,
                                .value = value,
                                .hash = hash,
                            } };
                            return .{ .node = new_node, .added = false };
                        } else {
                            // Hash collision - create collision node
                            const new_node = try self.allocator.create(Node);
                            var collision = try Collision.init(self.allocator, hash, 2);
                            collision.pairs[0] = .{ .key = leaf.key, .value = leaf.value, .hash = hash };
                            collision.pairs[1] = .{ .key = key, .value = value, .hash = hash };
                            new_node.* = .{ .collision = collision };
                            return .{ .node = new_node, .added = true };
                        }
                    } else {
                        // Different hashes - create bitmap node
                        return self.createBitmapWithTwo(leaf.hash, leaf.key, leaf.value, hash, key, value, shift);
                    }
                },
                .bitmap => |bm| {
                    return self.insertBitmap(bm, hash, key, value, shift);
                },
                .array => |arr| {
                    return self.insertArray(arr, hash, key, value, shift);
                },
                .collision => |col| {
                    return self.insertCollision(col, key, value);
                },
            }
        }

        fn createBitmapWithTwo(
            self: Self,
            hash1: u32,
            key1: K,
            value1: V,
            hash2: u32,
            key2: K,
            value2: V,
            shift: u5,
        ) !InsertResult {
            const idx1: u5 = @truncate((hash1 >> shift) & LEVEL_MASK);
            const idx2: u5 = @truncate((hash2 >> shift) & LEVEL_MASK);

            const new_node = try self.allocator.create(Node);

            if (idx1 == idx2) {
                // Same position - recurse
                const child = try self.createBitmapWithTwo(hash1, key1, value1, hash2, key2, value2, shift +| BITS_PER_LEVEL);
                var bitmap = try Bitmap.init(self.allocator, @as(u32, 1) << idx1, 1);
                bitmap.entries[0] = .{ .node = child.node };
                new_node.* = .{ .bitmap = bitmap };
            } else {
                // Different positions
                const bitmap_val = (@as(u32, 1) << idx1) | (@as(u32, 1) << idx2);
                var bitmap = try Bitmap.init(self.allocator, bitmap_val, 2);

                // Order by index
                if (idx1 < idx2) {
                    bitmap.entries[0] = .{ .kv = .{ .key = key1, .value = value1 } };
                    bitmap.entries[1] = .{ .kv = .{ .key = key2, .value = value2 } };
                } else {
                    bitmap.entries[0] = .{ .kv = .{ .key = key2, .value = value2 } };
                    bitmap.entries[1] = .{ .kv = .{ .key = key1, .value = value1 } };
                }
                new_node.* = .{ .bitmap = bitmap };
            }

            return .{ .node = new_node, .added = true };
        }

        fn insertBitmap(self: Self, bm: Bitmap, hash: u32, key: K, value: V, shift: u5) !InsertResult {
            const idx: u5 = @truncate((hash >> shift) & LEVEL_MASK);
            const pos = bm.getPosition(idx);

            const new_node = try self.allocator.create(Node);

            if (bm.hasIndex(idx)) {
                // Position exists
                const entry = bm.entries[pos];
                switch (entry) {
                    .kv => |kv| {
                        const old_hash = self.hash_fn(kv.key);
                        if (old_hash == hash and self.eql_fn(kv.key, key)) {
                            // Replace value
                            var new_bitmap = try Bitmap.init(self.allocator, bm.bitmap, bm.entries.len);
                            @memcpy(new_bitmap.entries, bm.entries);
                            new_bitmap.entries[pos] = .{ .kv = .{ .key = key, .value = value } };
                            new_node.* = .{ .bitmap = new_bitmap };
                            return .{ .node = new_node, .added = false };
                        } else {
                            // Different key - create child node
                            const child = try self.createBitmapWithTwo(
                                old_hash,
                                kv.key,
                                kv.value,
                                hash,
                                key,
                                value,
                                shift +| BITS_PER_LEVEL,
                            );
                            var new_bitmap = try Bitmap.init(self.allocator, bm.bitmap, bm.entries.len);
                            @memcpy(new_bitmap.entries, bm.entries);
                            new_bitmap.entries[pos] = .{ .node = child.node };
                            new_node.* = .{ .bitmap = new_bitmap };
                            return .{ .node = new_node, .added = true };
                        }
                    },
                    .node => |child| {
                        // Recurse into child
                        const result = try self.insert(child, hash, key, value, shift +| BITS_PER_LEVEL);
                        var new_bitmap = try Bitmap.init(self.allocator, bm.bitmap, bm.entries.len);
                        @memcpy(new_bitmap.entries, bm.entries);
                        new_bitmap.entries[pos] = .{ .node = result.node };
                        new_node.* = .{ .bitmap = new_bitmap };
                        return .{ .node = new_node, .added = result.added };
                    },
                }
            } else {
                // New position - expand bitmap
                const new_count = bm.entries.len + 1;
                const new_bitmap_val = bm.bitmap | (@as(u32, 1) << idx);

                if (new_count > BITMAP_TO_ARRAY_THRESHOLD) {
                    // Convert to array node
                    var array = Array.init();
                    // Copy existing entries
                    var j: usize = 0;
                    for (0..BRANCH_FACTOR) |i| {
                        const i5: u5 = @truncate(i);
                        if (bm.hasIndex(i5)) {
                            const arr_node = try self.allocator.create(Node);
                            switch (bm.entries[j]) {
                                .kv => |kv| {
                                    arr_node.* = .{ .leaf = .{
                                        .key = kv.key,
                                        .value = kv.value,
                                        .hash = self.hash_fn(kv.key),
                                    } };
                                },
                                .node => |n| {
                                    arr_node.* = n.*;
                                },
                            }
                            array.children[i] = arr_node;
                            array.count += 1;
                            j += 1;
                        }
                    }
                    // Add new entry
                    const new_entry = try self.allocator.create(Node);
                    new_entry.* = .{ .leaf = .{ .key = key, .value = value, .hash = hash } };
                    array.children[idx] = new_entry;
                    array.count += 1;

                    new_node.* = .{ .array = array };
                } else {
                    var new_bitmap = try Bitmap.init(self.allocator, new_bitmap_val, new_count);
                    // Copy entries before pos
                    for (0..pos) |i| {
                        new_bitmap.entries[i] = bm.entries[i];
                    }
                    // Insert new entry
                    new_bitmap.entries[pos] = .{ .kv = .{ .key = key, .value = value } };
                    // Copy entries after pos
                    for (pos..bm.entries.len) |i| {
                        new_bitmap.entries[i + 1] = bm.entries[i];
                    }
                    new_node.* = .{ .bitmap = new_bitmap };
                }
                return .{ .node = new_node, .added = true };
            }
        }

        fn insertArray(self: Self, arr: Array, hash: u32, key: K, value: V, shift: u5) !InsertResult {
            const idx: u5 = @truncate((hash >> shift) & LEVEL_MASK);

            const new_node = try self.allocator.create(Node);
            var new_array = arr; // Copy

            if (arr.children[idx]) |child| {
                const result = try self.insert(child, hash, key, value, shift +| BITS_PER_LEVEL);
                new_array.children[idx] = result.node;
                new_node.* = .{ .array = new_array };
                return .{ .node = new_node, .added = result.added };
            } else {
                const leaf = try self.allocator.create(Node);
                leaf.* = .{ .leaf = .{ .key = key, .value = value, .hash = hash } };
                new_array.children[idx] = leaf;
                new_array.count += 1;
                new_node.* = .{ .array = new_array };
                return .{ .node = new_node, .added = true };
            }
        }

        fn insertCollision(self: Self, col: Collision, key: K, value: V) !InsertResult {
            const new_node = try self.allocator.create(Node);

            // Check if key exists
            for (col.pairs, 0..) |pair, i| {
                if (self.eql_fn(pair.key, key)) {
                    // Replace
                    var new_col = try Collision.init(self.allocator, col.hash, col.pairs.len);
                    @memcpy(new_col.pairs, col.pairs);
                    new_col.pairs[i].value = value;
                    new_node.* = .{ .collision = new_col };
                    return .{ .node = new_node, .added = false };
                }
            }

            // Add new pair
            var new_col = try Collision.init(self.allocator, col.hash, col.pairs.len + 1);
            @memcpy(new_col.pairs[0..col.pairs.len], col.pairs);
            new_col.pairs[col.pairs.len] = .{ .key = key, .value = value, .hash = col.hash };
            new_node.* = .{ .collision = new_col };
            return .{ .node = new_node, .added = true };
        }

        /// Check if key exists
        pub fn contains(self: Self, key: K) bool {
            return self.get(key) != null;
        }

        /// Get number of items
        pub fn size(self: Self) usize {
            return self.len;
        }

        /// Check if empty
        pub fn isEmpty(self: Self) bool {
            return self.len == 0;
        }

        /// Create iterator
        pub fn iterator(self: Self) Iterator {
            return Iterator.init(self);
        }

        /// Iterator over key-value pairs
        pub const Iterator = struct {
            stack: [MAX_DEPTH]StackEntry,
            depth: usize,

            const StackEntry = struct {
                node: *Node,
                index: usize,
            };

            pub fn init(hamt: Self) Iterator {
                var it = Iterator{
                    .stack = undefined,
                    .depth = 0,
                };
                if (hamt.root) |root| {
                    it.stack[0] = .{ .node = root, .index = 0 };
                    it.depth = 1;
                }
                return it;
            }

            pub fn next(self: *Iterator) ?struct { key: K, value: V } {
                while (self.depth > 0) {
                    const entry = &self.stack[self.depth - 1];
                    switch (entry.node.*) {
                        .leaf => |leaf| {
                            self.depth -= 1;
                            return .{ .key = leaf.key, .value = leaf.value };
                        },
                        .bitmap => |bm| {
                            while (entry.index < bm.entries.len) {
                                const idx = entry.index;
                                entry.index += 1;
                                switch (bm.entries[idx]) {
                                    .kv => |kv| {
                                        return .{ .key = kv.key, .value = kv.value };
                                    },
                                    .node => |child| {
                                        self.stack[self.depth] = .{ .node = child, .index = 0 };
                                        self.depth += 1;
                                        break;
                                    },
                                }
                            } else {
                                self.depth -= 1;
                            }
                        },
                        .array => |arr| {
                            while (entry.index < BRANCH_FACTOR) {
                                const idx = entry.index;
                                entry.index += 1;
                                if (arr.children[idx]) |child| {
                                    self.stack[self.depth] = .{ .node = child, .index = 0 };
                                    self.depth += 1;
                                    break;
                                }
                            } else {
                                self.depth -= 1;
                            }
                        },
                        .collision => |col| {
                            if (entry.index < col.pairs.len) {
                                const pair = col.pairs[entry.index];
                                entry.index += 1;
                                return .{ .key = pair.key, .value = pair.value };
                            } else {
                                self.depth -= 1;
                            }
                        },
                    }
                }
                return null;
            }
        };
    };
}

// ============================================================================
// String HAMT (common use case)
// ============================================================================

fn stringHash(s: []const u8) u32 {
    var hash: u32 = 0;
    for (s) |c| {
        hash = hash *% 31 +% c;
    }
    return hash;
}

fn stringEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// String-keyed HAMT convenience type
pub fn StringHamt(comptime V: type) type {
    return Hamt([]const u8, V);
}

/// Create a new string-keyed HAMT
pub fn newStringHamt(comptime V: type, allocator: Allocator) StringHamt(V) {
    return StringHamt(V).init(allocator, stringHash, stringEql);
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "hamt basic" {
    const allocator = std.testing.allocator;

    var hamt = newStringHamt(i32, allocator);
    defer hamt.deinit();

    // Empty
    try std.testing.expect(hamt.isEmpty());
    try std.testing.expect(hamt.get("key") == null);

    // Insert
    var hamt2 = try hamt.set("key", 42);
    defer hamt2.deinit();

    try std.testing.expectEqual(@as(usize, 1), hamt2.size());
    try std.testing.expectEqual(@as(i32, 42), hamt2.get("key").?);

    // Original unchanged (immutable)
    try std.testing.expect(hamt.isEmpty());
}

test "hamt multiple" {
    const allocator = std.testing.allocator;

    var hamt = newStringHamt(i32, allocator);
    defer hamt.deinit();

    var h1 = try hamt.set("a", 1);
    defer h1.deinit();

    var h2 = try h1.set("b", 2);
    defer h2.deinit();

    var h3 = try h2.set("c", 3);
    defer h3.deinit();

    try std.testing.expectEqual(@as(usize, 3), h3.size());
    try std.testing.expectEqual(@as(i32, 1), h3.get("a").?);
    try std.testing.expectEqual(@as(i32, 2), h3.get("b").?);
    try std.testing.expectEqual(@as(i32, 3), h3.get("c").?);
}

test "hamt update" {
    const allocator = std.testing.allocator;

    var hamt = newStringHamt(i32, allocator);
    defer hamt.deinit();

    var h1 = try hamt.set("key", 1);
    defer h1.deinit();

    var h2 = try h1.set("key", 2);
    defer h2.deinit();

    // Size unchanged
    try std.testing.expectEqual(@as(usize, 1), h2.size());
    // Value updated
    try std.testing.expectEqual(@as(i32, 2), h2.get("key").?);
    // Original unchanged
    try std.testing.expectEqual(@as(i32, 1), h1.get("key").?);
}

test "hamt iterator" {
    const allocator = std.testing.allocator;

    var hamt = newStringHamt(i32, allocator);
    defer hamt.deinit();

    var h = try hamt.set("x", 10);
    defer h.deinit();

    var count: usize = 0;
    var it = h.iterator();
    while (it.next()) |_| {
        count += 1;
    }

    try std.testing.expectEqual(@as(usize, 1), count);
}
