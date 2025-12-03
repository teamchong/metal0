/// Build functions for tokenizer (split table, Aho-Corasick, etc.)
/// Part of tokenizer.zig split (was lines 270-476)

const std = @import("std");
const Allocator = std.mem.Allocator;
const AhoCorasick = @import("aho_corasick.zig").AhoCorasick;
const ac_cache = @import("aho_corasick_cache.zig");
const helpers = @import("tokenizer_helpers.zig");
const Pair = helpers.Pair;
const PairContext = helpers.PairContext;
const StringHashContext = helpers.StringHashContext;
const FnvHashContext = @import("fnv_hash.zig").FnvHashContext;

/// Build split_table by reverse-engineering vocab (port of rs-bpe lines 289-320)
/// Now returns array indexed by token ID for O(1) access
pub fn buildSplitTable(
    vocab_r: *const std.AutoHashMap(u32, []const u8),
    vocab: anytype,
    pair_lookup: anytype,
    allocator: Allocator,
) ![]Pair {
    // Find max token ID to size array
    const vocab_size = vocab_r.count();

    // Allocate array
    const split_table = try allocator.alloc(Pair, vocab_size);

    // Initialize with sentinels (base tokens split to themselves)
    for (split_table, 0..) |*pair, i| {
        pair.* = .{ .left = @intCast(i), .right = @intCast(i) };
    }

    // For each token (by rank/id), find the split that created it
    var id: u32 = 0;
    while (id < vocab_size) : (id += 1) {
        const token_bytes = vocab_r.get(id) orelse {
            continue;
        };

        if (token_bytes.len <= 1) {
            continue;
        }

        // Simulate BPE on the token bytes to find the final merge
        var parts = try std.ArrayList(u32).initCapacity(allocator, token_bytes.len);
        defer parts.deinit(allocator);

        // Initialize with bytes
        for (token_bytes) |byte| {
            const byte_slice = @as(*const [1]u8, &byte)[0..1];
            const rank = vocab.get(byte_slice) orelse @as(u32, byte); // Should always be in vocab
            try parts.append(allocator, rank);
        }

        while (parts.items.len > 1) {
            var best_rank: u32 = std.math.maxInt(u32);
            var best_pos: usize = 0;
            var best_new_token: u32 = 0;

            // Find lowest rank pair
            var i: usize = 0;
            while (i + 1 < parts.items.len) : (i += 1) {
                const left = parts.items[i];
                const right = parts.items[i + 1];

                // Reconstruct bytes to look up rank
                // Note: This is slow but correct. Optimization: cache byte slices?
                // Or use pair_lookup if we process in order?
                // But we process by ID, which is rank order.
                // So sub-tokens should already be in pair_lookup?
                // Yes! If we process in rank order, components exist.

                var merged_rank: ?u32 = null;
                if (pair_lookup.get(Pair{ .left = left, .right = right })) |r| {
                    merged_rank = r;
                } else {
                    // Fallback: look up in vocab (slow path)
                    const left_bytes = vocab_r.get(left) orelse continue;
                    const right_bytes = vocab_r.get(right) orelse continue;
                    const total_len = left_bytes.len + right_bytes.len;

                    // We need a buffer for concatenation
                    const merged_bytes = try allocator.alloc(u8, total_len);
                    defer allocator.free(merged_bytes);
                    @memcpy(merged_bytes[0..left_bytes.len], left_bytes);
                    @memcpy(merged_bytes[left_bytes.len..total_len], right_bytes);

                    if (vocab.get(merged_bytes)) |r| {
                        merged_rank = r;
                    }
                }

                if (merged_rank) |rank| {
                    if (rank < best_rank) {
                        best_rank = rank;
                        best_pos = i;
                        best_new_token = rank;
                    }
                }
            }

            if (best_rank == std.math.maxInt(u32)) {
                break; // No more merges possible
            }

            // If the best merge IS the current token, we found the split!
            if (best_rank == id) {
                const left = parts.items[best_pos];
                const right = parts.items[best_pos + 1];
                split_table[id] = Pair{ .left = left, .right = right };
                try pair_lookup.put(Pair{ .left = left, .right = right }, id);
                break;
            }

            // Otherwise perform the merge and continue
            parts.items[best_pos] = best_new_token;
            _ = parts.orderedRemove(best_pos + 1);
        }
    }

    return split_table;
}

/// Build Aho-Corasick automaton from vocab for fast longest-match lookup
/// Uses binary cache for 430x faster loading (43s → <0.1s)
pub fn buildAhoCorasick(vocab_r: *const std.AutoHashMap(u32, []const u8), allocator: Allocator) !?AhoCorasick {
    return buildAhoCorasickCached(vocab_r, allocator, null);
}

/// Build Aho-Corasick with explicit cache path
pub fn buildAhoCorasickCached(
    vocab_r: *const std.AutoHashMap(u32, []const u8),
    allocator: Allocator,
    vocab_path: ?[]const u8,
) !?AhoCorasick {
    // Try loading from cache first
    const cache_path = if (vocab_path) |vp|
        try ac_cache.getCachePath(allocator, vp)
    else
        try allocator.dupe(u8, "/tmp/ac_cache_cl100k.bin");
    defer allocator.free(cache_path);

    // Try to load cached automaton
    if (ac_cache.load(allocator, cache_path)) |ac| {
        return ac;
    }

    // Cache miss - build from scratch (slow, 43s)
    var patterns = std.ArrayList([]const u8){};
    defer patterns.deinit(allocator);
    var token_ids = std.ArrayList(u32){};
    defer token_ids.deinit(allocator);

    var it = vocab_r.iterator();
    while (it.next()) |entry| {
        try patterns.append(allocator, entry.value_ptr.*);
        try token_ids.append(allocator, entry.key_ptr.*);
    }

    // Build automaton
    var ac = try AhoCorasick.build(allocator, patterns.items, token_ids.items);

    // Save to cache for next time
    ac_cache.save(&ac, cache_path) catch {}; // Ignore save errors

    return ac;
}

/// Build next_prefix_match table - Port of rs-bpe optimization
/// For each token, precompute the longest vocab token that matches token[0..len-1]
pub fn buildNextPrefixMatch(
    vocab_r: *const std.AutoHashMap(u32, []const u8),
    aho_corasick: AhoCorasick,
    allocator: Allocator
) ![]u32 {
    const vocab_size = vocab_r.count();
    const next_prefix_match = try allocator.alloc(u32, vocab_size);
    @memset(next_prefix_match, std.math.maxInt(u32)); // u32::MAX sentinel

    var token_id: u32 = 0;
    while (token_id < vocab_size) : (token_id += 1) {
        if (vocab_r.get(token_id)) |token_bytes| {
            if (token_bytes.len <= 1) continue; // No prefix for single byte

            // Search for longest match of token[0..len-1]
            const prefix = token_bytes[0..token_bytes.len - 1];
            if (aho_corasick.longestMatch(prefix, 0)) |prefix_token| {
                next_prefix_match[token_id] = prefix_token;
            }
        }
    }

    return next_prefix_match;
}

/// Port of rs-bpe's is_valid_token_pair (lines 112-148)
/// Returns true if token1 followed by token2 is a valid BPE encoding path
pub fn isValidTokenPair(
    pair_lookup: anytype,
    split_table: []const Pair,
    token1_arg: u32,
    token2_arg: u32,
) bool {
    var token1 = token1_arg;
    var token2 = token2_arg;
    var limit: u32 = std.math.maxInt(u32);

    while (true) {
        // Check if this pair exists in the merge rules
        if (pair_lookup.get(Pair{ .left = token1, .right = token2 })) |combined| {
            // If the combined token has lower rank than limit, this pair is invalid
            // (should have been merged earlier in BPE)
            return combined >= limit;
        }

        if (token1 > token2) {
            limit = token1;
            const split = split_table[token1];
            // Base token check: if token splits to itself, we've reached the bottom
            if (split.left == token1 and split.right == token1) {
                return true; // Base token - no merge restriction
            }
            token1 = split.right;
            if (token1 == limit) {
                limit = token2 + 1;
                const split2 = split_table[token2];
                // Base token check for token2
                if (split2.left == token2 and split2.right == token2) {
                    return true;
                }
                token2 = split2.left;
                if (token2 + 1 == limit) {
                    return true;
                }
            }
        } else {
            limit = token2 + 1;
            const split = split_table[token2];
            // Base token check: if token splits to itself, we've reached the bottom
            if (split.left == token2 and split.right == token2) {
                return true;
            }
            token2 = split.left;
            if (token2 + 1 == limit) {
                limit = token1;
                const split2 = split_table[token1];
                // Base token check for token1
                if (split2.left == token1 and split2.right == token1) {
                    return true;
                }
                token1 = split2.right;
                if (token1 == limit) {
                    return true;
                }
            }
        }
    }
}
