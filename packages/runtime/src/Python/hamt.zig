/// hamt - Hash Array Mapped Trie
/// Mirrors cpython/Python/hamt.c
///
/// This module provides an immutable mapping using HAMT:
/// - O(1) copy via structural sharing
/// - O(log N) set/delete operations
/// - O(log N) lookups
/// - Memory efficient via bitmap compression

const std = @import("std");

// Re-export submodules
pub const constants = @import("hamt/constants.zig");
pub const node_types = @import("hamt/node_types.zig");
pub const core = @import("hamt/core.zig");
pub const string_hamt = @import("hamt/string_hamt.zig");

// Re-export constants
pub const BITS_PER_LEVEL = constants.BITS_PER_LEVEL;
pub const BRANCH_FACTOR = constants.BRANCH_FACTOR;
pub const LEVEL_MASK = constants.LEVEL_MASK;
pub const MAX_DEPTH = constants.MAX_DEPTH;
pub const BITMAP_TO_ARRAY_THRESHOLD = constants.BITMAP_TO_ARRAY_THRESHOLD;

// Re-export node types
pub const KVPair = node_types.KVPair;
pub const HamtNode = node_types.HamtNode;
pub const LeafNode = node_types.LeafNode;
pub const BitmapNode = node_types.BitmapNode;
pub const ArrayNode = node_types.ArrayNode;
pub const CollisionNode = node_types.CollisionNode;

// Re-export core HAMT
pub const Hamt = core.Hamt;

// Re-export string helpers
pub const StringHamt = string_hamt.StringHamt;
pub const newStringHamt = string_hamt.newStringHamt;

// Initialization
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
