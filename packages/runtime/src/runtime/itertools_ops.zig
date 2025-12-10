/// Itertools operations runtime helpers
/// Extracted from codegen to prevent comptime explosion from repeated @TypeOf patterns
///
/// Problem: Each itertools call generated inline blocks with @TypeOf(_iter[0])
/// causing O(n²) monomorphization when many itertools operations exist.
///
/// Solution: These helpers are compiled once per element type, called N times.
const std = @import("std");

pub const ItertoolsError = error{
    OutOfMemory,
};

/// Compress - filter data based on selectors
pub fn compress(comptime T: type, allocator: std.mem.Allocator, data: []const T, selectors: []const i64) ItertoolsError!std.ArrayListUnmanaged(T) {
    var result: std.ArrayListUnmanaged(T) = .{};
    const len = @min(data.len, selectors.len);
    for (0..len) |i| {
        if (selectors[i] != 0) {
            result.append(allocator, data[i]) catch continue;
        }
    }
    return result;
}

/// Pairwise - return consecutive pairs
pub fn Pair(comptime T: type) type {
    return struct { first: T, second: T };
}

pub fn pairwise(comptime T: type, allocator: std.mem.Allocator, iter: []const T) ItertoolsError!std.ArrayListUnmanaged(Pair(T)) {
    var result: std.ArrayListUnmanaged(Pair(T)) = .{};
    if (iter.len > 1) {
        for (0..iter.len - 1) |i| {
            result.append(allocator, .{ .first = iter[i], .second = iter[i + 1] }) catch continue;
        }
    }
    return result;
}

/// Accumulate - running totals with optional function
pub fn accumulate(comptime T: type, allocator: std.mem.Allocator, iter: []const T, func: ?*const fn (T, T) T) ItertoolsError!std.ArrayListUnmanaged(T) {
    var result: std.ArrayListUnmanaged(T) = .{};
    if (iter.len == 0) return result;

    var acc: T = iter[0];
    result.append(allocator, acc) catch {};

    for (iter[1..]) |item| {
        if (func) |f| {
            acc = f(acc, item);
        } else {
            // Default: addition (only works for numeric types)
            acc = acc + item;
        }
        result.append(allocator, acc) catch continue;
    }
    return result;
}

/// Groupby result type
pub fn GroupbyEntry(comptime T: type) type {
    return struct {
        key: T,
        group: std.ArrayListUnmanaged(T),
    };
}

/// Groupby - group consecutive equal elements
pub fn groupby(comptime T: type, allocator: std.mem.Allocator, iter: []const T) ItertoolsError!std.ArrayListUnmanaged(GroupbyEntry(T)) {
    var result: std.ArrayListUnmanaged(GroupbyEntry(T)) = .{};
    if (iter.len == 0) return result;

    var cur_key = iter[0];
    var cur_group: std.ArrayListUnmanaged(T) = .{};
    cur_group.append(allocator, cur_key) catch {};

    for (iter[1..]) |item| {
        if (item == cur_key) {
            cur_group.append(allocator, item) catch continue;
        } else {
            result.append(allocator, .{ .key = cur_key, .group = cur_group }) catch {};
            cur_key = item;
            cur_group = .{};
            cur_group.append(allocator, item) catch {};
        }
    }
    result.append(allocator, .{ .key = cur_key, .group = cur_group }) catch {};
    return result;
}

/// Batched result type - batch of elements
pub fn batched(comptime T: type, allocator: std.mem.Allocator, iter: []const T, n: usize) ItertoolsError!std.ArrayListUnmanaged(std.ArrayListUnmanaged(T)) {
    var result: std.ArrayListUnmanaged(std.ArrayListUnmanaged(T)) = .{};
    var i: usize = 0;
    while (i < iter.len) : (i += n) {
        var batch: std.ArrayListUnmanaged(T) = .{};
        const end = @min(i + n, iter.len);
        for (iter[i..end]) |item| {
            batch.append(allocator, item) catch continue;
        }
        result.append(allocator, batch) catch continue;
    }
    return result;
}

/// Islice - slice of iterator
pub fn islice(comptime T: type, allocator: std.mem.Allocator, iter: []const T, stop: usize) ItertoolsError!std.ArrayListUnmanaged(T) {
    var result: std.ArrayListUnmanaged(T) = .{};
    const actual_stop = @min(stop, iter.len);
    for (iter[0..actual_stop]) |item| {
        result.append(allocator, item) catch continue;
    }
    return result;
}

/// Combinations result type - pair of elements
pub fn CombPair(comptime T: type) type {
    return struct { first: T, second: T };
}

/// Combinations - 2-combinations (most common case)
pub fn combinations(comptime T: type, allocator: std.mem.Allocator, iter: []const T) ItertoolsError!std.ArrayListUnmanaged(CombPair(T)) {
    var result: std.ArrayListUnmanaged(CombPair(T)) = .{};
    if (iter.len < 2) return result;

    for (0..iter.len - 1) |i| {
        for (iter[i + 1 ..]) |b| {
            result.append(allocator, .{ .first = iter[i], .second = b }) catch continue;
        }
    }
    return result;
}

/// Combinations with replacement - 2-combinations allowing same element twice
pub fn combinationsWithReplacement(comptime T: type, allocator: std.mem.Allocator, iter: []const T) ItertoolsError!std.ArrayListUnmanaged(CombPair(T)) {
    var result: std.ArrayListUnmanaged(CombPair(T)) = .{};
    for (iter, 0..) |a, i| {
        for (iter[i..]) |b| {
            result.append(allocator, .{ .first = a, .second = b }) catch continue;
        }
    }
    return result;
}

/// Permutations - 2-permutations (most common case)
pub fn permutations(comptime T: type, allocator: std.mem.Allocator, iter: []const T) ItertoolsError!std.ArrayListUnmanaged(CombPair(T)) {
    var result: std.ArrayListUnmanaged(CombPair(T)) = .{};
    for (iter, 0..) |a, i| {
        for (iter, 0..) |b, j| {
            if (i != j) {
                result.append(allocator, .{ .first = a, .second = b }) catch continue;
            }
        }
    }
    return result;
}

/// Product with repeat - cartesian product of iterable with itself N times
/// product(range(3), repeat=2) -> [(0,0), (0,1), (0,2), (1,0), (1,1), (1,2), (2,0), (2,1), (2,2)]
/// Returns slice of tuples represented as arrays
pub fn productRepeat(comptime T: type, allocator: std.mem.Allocator, iter: []const T, repeat: usize) ItertoolsError![][]T {
    if (repeat == 0 or iter.len == 0) {
        // Empty product
        return &[_][]T{};
    }

    // Calculate total number of combinations: len^repeat
    var total: usize = 1;
    for (0..repeat) |_| {
        total *= iter.len;
    }

    // Allocate result array
    var result = try allocator.alloc([]T, total);
    errdefer allocator.free(result);

    // Generate all combinations using indices
    var indices = try allocator.alloc(usize, repeat);
    defer allocator.free(indices);
    @memset(indices, 0);

    for (0..total) |i| {
        // Create tuple for current indices
        var tuple = try allocator.alloc(T, repeat);
        for (0..repeat) |j| {
            tuple[j] = iter[indices[j]];
        }
        result[i] = tuple;

        // Increment indices (like counting in base len)
        var pos: usize = repeat;
        while (pos > 0) {
            pos -= 1;
            indices[pos] += 1;
            if (indices[pos] < iter.len) {
                break;
            }
            indices[pos] = 0;
        }
    }

    return result;
}

// Tests
test "compress" {
    const allocator = std.testing.allocator;
    const data = [_]i64{ 1, 2, 3, 4, 5 };
    const selectors = [_]i64{ 1, 0, 1, 0, 1 };

    var result = try compress(i64, allocator, &data, &selectors);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), result.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.items[0]);
    try std.testing.expectEqual(@as(i64, 3), result.items[1]);
    try std.testing.expectEqual(@as(i64, 5), result.items[2]);
}

test "pairwise" {
    const allocator = std.testing.allocator;
    const data = [_]i64{ 1, 2, 3, 4 };

    var result = try pairwise(i64, allocator, &data);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), result.items.len);
    try std.testing.expectEqual(@as(i64, 1), result.items[0].first);
    try std.testing.expectEqual(@as(i64, 2), result.items[0].second);
}

test "combinations" {
    const allocator = std.testing.allocator;
    const data = [_]i64{ 1, 2, 3 };

    var result = try combinations(i64, allocator, &data);
    defer result.deinit(allocator);

    // C(3,2) = 3: (1,2), (1,3), (2,3)
    try std.testing.expectEqual(@as(usize, 3), result.items.len);
}

test "permutations" {
    const allocator = std.testing.allocator;
    const data = [_]i64{ 1, 2, 3 };

    var result = try permutations(i64, allocator, &data);
    defer result.deinit(allocator);

    // P(3,2) = 6: (1,2), (1,3), (2,1), (2,3), (3,1), (3,2)
    try std.testing.expectEqual(@as(usize, 6), result.items.len);
}

test "batched" {
    const allocator = std.testing.allocator;
    const data = [_]i64{ 1, 2, 3, 4, 5 };

    var result = try batched(i64, allocator, &data, 2);
    defer {
        for (result.items) |*batch| {
            batch.deinit(allocator);
        }
        result.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), result.items.len);
    try std.testing.expectEqual(@as(usize, 2), result.items[0].items.len);
    try std.testing.expectEqual(@as(usize, 2), result.items[1].items.len);
    try std.testing.expectEqual(@as(usize, 1), result.items[2].items.len);
}
