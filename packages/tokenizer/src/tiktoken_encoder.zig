/// Tiktoken-compatible BPE encoder
/// Direct line-by-line port of tiktoken's lib.rs for 100% correctness
///
/// Reference: https://github.com/openai/tiktoken/blob/main/src/lib.rs
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Rank = u32;
const MAX_RANK = std.math.maxInt(Rank);

/// Part struct - equivalent to Rust's (usize, Rank) tuple
const Part = struct {
    start: usize,
    rank: Rank,
};

/// Core BPE merge algorithm - direct port from tiktoken lib.rs:17-73
/// fn _byte_pair_merge(ranks: &HashMap<Vec<u8>, Rank>, piece: &[u8]) -> Vec<(usize, Rank)>
fn _byte_pair_merge(
    piece: []const u8,
    ranks: anytype, // HashMap with get() method
    allocator: Allocator,
) !std.ArrayList(Part) {
    // This is a vector of (start, rank).
    // The rank is of the pair starting at position start.
    // lib.rs:20: let mut parts = Vec::with_capacity(piece.len + 1);
    var parts = try std.ArrayList(Part).initCapacity(allocator, piece.len + 1);
    errdefer parts.deinit(allocator);

    // Note that we hash bytes when indexing into `ranks`, not token pairs.
    // lib.rs:25: let mut min_rank: (Rank, usize) = (Rank::MAX, usize::MAX);
    var min_rank: Rank = MAX_RANK;
    var min_idx: usize = std.math.maxInt(usize);

    // lib.rs:26-32: Initialize parts with ranks for 2-byte windows
    var i: usize = 0;
    while (i < piece.len -| 1) : (i += 1) {
        const rank = ranks.get(piece[i .. i + 2]) orelse MAX_RANK;
        if (rank < min_rank) {
            min_rank = rank;
            min_idx = i;
        }
        try parts.append(allocator, .{ .start = i, .rank = rank });
    }
    // lib.rs:33-34
    try parts.append(allocator, .{ .start = piece.len -| 1, .rank = MAX_RANK });
    try parts.append(allocator, .{ .start = piece.len, .rank = MAX_RANK });

    // lib.rs:36-49: get_rank closure
    const get_rank = struct {
        fn f(r: anytype, p: []const u8, pts: []Part, idx: usize) Rank {
            // lib.rs:39: if (i + 3) < parts.len()
            if (idx + 3 < pts.len) {
                // lib.rs:42-44: ranks.get(&piece[parts[i].0..parts[i + 3].0])
                return r.get(p[pts[idx].start..pts[idx + 3].start]) orelse MAX_RANK;
            }
            return MAX_RANK;
        }
    }.f;

    // lib.rs:55-71: Main merge loop - O(mn) where m=merges, n=parts
    // while min_rank.0 != Rank::MAX
    while (min_rank != MAX_RANK) {
        const idx = min_idx;

        // lib.rs:59-61: Update parts[i] and parts[i-1] before removing parts[i+1]
        if (idx > 0) {
            parts.items[idx - 1].rank = get_rank(ranks, piece, parts.items, idx - 1);
        }
        parts.items[idx].rank = get_rank(ranks, piece, parts.items, idx);

        // lib.rs:63: parts.remove(i + 1)
        _ = parts.orderedRemove(idx + 1);

        // lib.rs:65-70: Find new minimum
        min_rank = MAX_RANK;
        min_idx = std.math.maxInt(usize);
        for (parts.items[0 .. parts.items.len -| 1], 0..) |part, j| {
            if (part.rank < min_rank) {
                min_rank = part.rank;
                min_idx = j;
            }
        }
    }

    return parts;
}

/// Encode a piece using BPE - direct port from tiktoken lib.rs:75-83
/// pub fn byte_pair_encode(piece: &[u8], ranks: &HashMap<Vec<u8>, Rank>) -> Vec<Rank>
pub fn byte_pair_encode(
    piece: []const u8,
    ranks: anytype, // HashMap with get() method
    allocator: Allocator,
) ![]Rank {
    // lib.rs:76-78: Single byte fast path
    if (piece.len == 1) {
        const result = try allocator.alloc(Rank, 1);
        result[0] = ranks.get(piece) orelse return error.TokenNotFound;
        return result;
    }

    // Empty input
    if (piece.len == 0) {
        return try allocator.alloc(Rank, 0);
    }

    // lib.rs:79-82: Run merge and convert to tokens
    var parts = try _byte_pair_merge(piece, ranks, allocator);
    defer parts.deinit(allocator);

    // .windows(2).map(|part| ranks[&piece[part[0].0..part[1].0]])
    var tokens = try std.ArrayList(Rank).initCapacity(allocator, parts.items.len -| 1);
    errdefer tokens.deinit(allocator);

    var i: usize = 0;
    while (i + 1 < parts.items.len) : (i += 1) {
        const slice = piece[parts.items[i].start..parts.items[i + 1].start];
        const token = ranks.get(slice) orelse return error.TokenNotFound;
        try tokens.append(allocator, token);
    }

    return try tokens.toOwnedSlice(allocator);
}

/// Encode text with regex splitting - equivalent to encode_ordinary (lib.rs:232-245)
/// This is the main entry point that matches tiktoken's behavior exactly
pub fn encode_ordinary(
    encoder: anytype, // vocab HashMap
    regex_split: anytype, // chunk iterator
    allocator: Allocator,
) ![]Rank {
    var ret = std.ArrayList(Rank){};
    errdefer ret.deinit(allocator);

    // lib.rs:237-244: for mat in regex.find_iter(text)
    while (regex_split.next()) |piece| {
        // lib.rs:239-241: Try direct lookup first
        if (encoder.get(piece)) |token| {
            try ret.append(allocator, token);
        } else {
            // lib.rs:241: ret.extend(&byte_pair_encode(piece, &self.encoder))
            const tokens = try byte_pair_encode(piece, encoder, allocator);
            defer allocator.free(tokens);
            try ret.appendSlice(allocator, tokens);
        }
    }

    return try ret.toOwnedSlice(allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "byte_pair_encode - simple merge" {
    const allocator = std.testing.allocator;

    // Create a simple vocab
    const TestMap = std.StringHashMap(Rank);
    var ranks = TestMap.init(allocator);
    defer ranks.deinit();

    try ranks.put("a", 0);
    try ranks.put("b", 1);
    try ranks.put("c", 2);
    try ranks.put("d", 3);
    try ranks.put("ab", 4);
    try ranks.put("cd", 5);

    const result = try byte_pair_encode("abcd", &ranks, allocator);
    defer allocator.free(result);

    // "abcd" -> "ab" + "cd" -> tokens [4, 5]
    try std.testing.expectEqualSlices(Rank, &[_]Rank{ 4, 5 }, result);
}

test "byte_pair_encode - single byte" {
    const allocator = std.testing.allocator;

    const TestMap = std.StringHashMap(Rank);
    var ranks = TestMap.init(allocator);
    defer ranks.deinit();

    try ranks.put("x", 42);

    const result = try byte_pair_encode("x", &ranks, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualSlices(Rank, &[_]Rank{42}, result);
}

test "byte_pair_encode - no merges" {
    const allocator = std.testing.allocator;

    const TestMap = std.StringHashMap(Rank);
    var ranks = TestMap.init(allocator);
    defer ranks.deinit();

    try ranks.put("a", 0);
    try ranks.put("b", 1);
    try ranks.put("c", 2);
    // No "ab", "bc", or "abc" merges

    const result = try byte_pair_encode("abc", &ranks, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualSlices(Rank, &[_]Rank{ 0, 1, 2 }, result);
}
