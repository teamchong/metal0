/// Build functions for tokenizer (split table, Aho-Corasick, etc.)
/// Part of tokenizer.zig split (was lines 270-476)

const std = @import("std");
const Allocator = std.mem.Allocator;
const AhoCorasick = @import("aho_corasick.zig").AhoCorasick;
const helpers = @import("tokenizer_helpers.zig");
const Pair = helpers.Pair;
const PairContext = helpers.PairContext;
const StringHashContext = helpers.StringHashContext;

/// Build split_table by reverse-engineering vocab (port of rs-bpe lines 289-320)
pub fn buildSplitTable(
    vocab_r: *const std.AutoHashMap(u32, []const u8),
    vocab: *const std.StringHashMap(u32),
    split_table: *std.AutoHashMap(u32, Pair),
    pair_lookup: *std.HashMap(Pair, u32, PairContext, std.hash_map.default_max_load_percentage),
    allocator: Allocator,
) !void {
    // For each token (by rank/id), find the split that created it
    var id: u32 = 0;
    while (id < vocab_r.count()) : (id += 1) {
        const token_bytes = vocab_r.get(id) orelse {
            try split_table.put(id, Pair{ .left = id, .right = id });
            continue;
        };

        if (token_bytes.len <= 1) {
            try split_table.put(id, Pair{ .left = id, .right = id });
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
                try split_table.put(id, Pair{ .left = left, .right = right });
                try pair_lookup.put(Pair{ .left = left, .right = right }, id);
                break;
            }

            // Otherwise perform the merge and continue
            parts.items[best_pos] = best_new_token;
            _ = parts.orderedRemove(best_pos + 1);
        }

        // If loop finished without finding split (e.g. base token or error), map to self
        if (!split_table.contains(id)) {
            try split_table.put(id, Pair{ .left = id, .right = id });
        }
    }
}

/// Build Aho-Corasick automaton from vocab for fast longest-match lookup
pub fn buildAhoCorasick(vocab_r: *const std.AutoHashMap(u32, []const u8), allocator: Allocator) !?AhoCorasick {
    // Collect all patterns and token IDs
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
    return try AhoCorasick.build(allocator, patterns.items, token_ids.items);
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
pub fn isValidTokenPair(
    pair_lookup: *const std.HashMap(Pair, u32, PairContext, std.hash_map.default_max_load_percentage),
    split_table: *const std.AutoHashMap(u32, Pair),
    token1_arg: u32,
    token2_arg: u32,
) bool {
    var token1 = token1_arg;
    var token2 = token2_arg;
    var limit: u32 = std.math.maxInt(u32);

    while (true) {
        // Check if this pair exists
        if (pair_lookup.get(Pair{ .left = token1, .right = token2 })) |combined| {
            if (combined < limit) {
                return false;
            }
            return true;
        }

        if (token1 > token2) {
            limit = token1;
            if (split_table.get(token1)) |split| {
                token1 = split.right;
                if (token1 == limit) {
                    limit = token2 + 1;
                    if (split_table.get(token2)) |split2| {
                        token2 = split2.left;
                        if (token2 + 1 == limit) {
                            return true;
                        }
                    } else {
                        return true;
                    }
                }
            } else {
                return true;
            }
        } else {
            limit = token2 + 1;
            if (split_table.get(token2)) |split| {
                token2 = split.left;
                if (token2 + 1 == limit) {
                    limit = token1;
                    if (split_table.get(token1)) |split2| {
                        token1 = split2.right;
                        if (token1 == limit) {
                            return true;
                        }
                    } else {
                        return true;
                    }
                }
            } else {
                return true;
            }
        }
    }
}
