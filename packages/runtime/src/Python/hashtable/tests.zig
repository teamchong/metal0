/// Tests for hash table implementation
/// Verifies functionality of HashTable and HashSet

const std = @import("std");
const hash_table = @import("hash_table.zig");
const convenience_types = @import("convenience_types.zig");
const hash_set = @import("hash_set.zig");

test "basic operations" {
    var table = try hash_table.HashTable(u64, []const u8).init(std.testing.allocator);
    defer table.deinit();

    try table.put(1, "one");
    try table.put(2, "two");
    try table.put(3, "three");

    try std.testing.expectEqual(@as(usize, 3), table.count());
    try std.testing.expectEqualStrings("one", table.get(1).?);
    try std.testing.expectEqualStrings("two", table.get(2).?);
    try std.testing.expect(table.get(999) == null);
}

test "string keys" {
    var table = try convenience_types.StringHashTable(i32).init(std.testing.allocator);
    defer table.deinit();

    try table.put("hello", 1);
    try table.put("world", 2);

    try std.testing.expectEqual(@as(i32, 1), table.get("hello").?);
    try std.testing.expectEqual(@as(i32, 2), table.get("world").?);
}

test "update value" {
    var table = try hash_table.HashTable(u64, i32).init(std.testing.allocator);
    defer table.deinit();

    try table.put(1, 100);
    try std.testing.expectEqual(@as(i32, 100), table.get(1).?);

    try table.put(1, 200);
    try std.testing.expectEqual(@as(i32, 200), table.get(1).?);
    try std.testing.expectEqual(@as(usize, 1), table.count());
}

test "remove" {
    var table = try hash_table.HashTable(u64, i32).init(std.testing.allocator);
    defer table.deinit();

    try table.put(1, 100);
    try table.put(2, 200);

    try std.testing.expect(table.remove(1));
    try std.testing.expect(table.get(1) == null);
    try std.testing.expectEqual(@as(usize, 1), table.count());

    try std.testing.expect(!table.remove(999));
}

test "iterator" {
    var table = try hash_table.HashTable(u64, i32).init(std.testing.allocator);
    defer table.deinit();

    try table.put(1, 10);
    try table.put(2, 20);
    try table.put(3, 30);

    var sum: i32 = 0;
    var iter_count: usize = 0;

    var iter = table.iterator();
    while (iter.next()) |entry| {
        sum += entry.value;
        iter_count += 1;
    }

    try std.testing.expectEqual(@as(usize, 3), iter_count);
    try std.testing.expectEqual(@as(i32, 60), sum);
}

test "hash set" {
    var set = try hash_set.HashSet(u64).init(std.testing.allocator);
    defer set.deinit();

    try set.add(1);
    try set.add(2);
    try set.add(3);
    try set.add(1); // Duplicate

    try std.testing.expectEqual(@as(usize, 3), set.count());
    try std.testing.expect(set.contains(1));
    try std.testing.expect(!set.contains(999));
}

test "resize" {
    var table = try hash_table.HashTable(u64, u64).init(std.testing.allocator);
    defer table.deinit();

    // Insert enough to trigger resize
    for (0..100) |i| {
        try table.put(i, i * 10);
    }

    try std.testing.expectEqual(@as(usize, 100), table.count());

    // Verify all values
    for (0..100) |i| {
        try std.testing.expectEqual(@as(u64, i * 10), table.get(i).?);
    }
}
