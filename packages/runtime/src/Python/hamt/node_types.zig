/// Node type definitions for HAMT
/// Mirrors cpython/Python/hamt.c

const std = @import("std");
const Allocator = std.mem.Allocator;
const constants = @import("constants.zig");

const BRANCH_FACTOR = constants.BRANCH_FACTOR;

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
