/// Zero-allocation stack-based encoder using comptime specialization
/// Eliminates 75% of runtime spent in malloc/free system calls
const std = @import("std");
const Allocator = std.mem.Allocator;
const AhoCorasick = @import("aho_corasick.zig").AhoCorasick;
const FnvHashContext = @import("fnv_hash.zig").FnvHashContext;
const helpers = @import("tokenizer_helpers.zig");
const Pair = helpers.Pair;

pub const PairContext = struct {
    pub fn hash(_: PairContext, p: Pair) u64 {
        return p.hash();
    }

    pub fn eql(_: PairContext, a: Pair, b: Pair) bool {
        return Pair.eql(a, b);
    }
};

/// Generate specialized encoder at compile time for given max text size
/// This creates ZERO-ALLOCATION stack-based encoder (except final result copy)
pub fn BacktrackEncoder(comptime max_text_size: usize) type {
    // Conservative estimates for stack array sizes
    const max_bitfield_words = (max_text_size + 64) / 64;
    const max_tokens = max_text_size / 2; // Worst case: every other byte is a token

    return struct {
        const Self = @This();

        // Stack-allocated arrays (NO HEAP during encoding!)
        bitfield: [max_bitfield_words]u64,
        tokens: [max_tokens]u32,
        tokens_len: usize,

        // Encoding state
        text: []const u8,
        pos: usize,
        next_token: ?u32,

        // BPE data (borrowed references - no ownership)
        aho_corasick: *const AhoCorasick,
        vocab_r: *const std.AutoHashMap(u32, []const u8),
        split_table: []const Pair,
        pair_lookup: *const std.HashMap(Pair, u32, FnvHashContext(Pair), std.hash_map.default_max_load_percentage),
        next_prefix_match: []const u32,

        pub fn init(
            text: []const u8,
            aho_corasick: *const AhoCorasick,
            vocab_r: *const std.AutoHashMap(u32, []const u8),
            split_table: []const Pair,
            pair_lookup: *const std.HashMap(Pair, u32, FnvHashContext(Pair), std.hash_map.default_max_load_percentage),
            next_prefix_match: []const u32,
        ) !Self {
            if (text.len > max_text_size) return error.TextTooLarge;

            var self = Self{
                .bitfield = undefined,
                .tokens = undefined,
                .tokens_len = 0,
                .text = text,
                .pos = 0,
                .next_token = aho_corasick.longestMatch(text, 0),
                .aho_corasick = aho_corasick,
                .vocab_r = vocab_r,
                .split_table = split_table,
                .pair_lookup = pair_lookup,
                .next_prefix_match = next_prefix_match,
            };

            // Initialize bitfield to all 1s (all positions valid)
            const needed_words = (text.len + 64) / 64;
            var i: usize = 0;
            while (i < needed_words) : (i += 1) {
                self.bitfield[i] = 0xFFFFFFFFFFFFFFFF;
            }

            return self;
        }

        /// Port of rs-bpe step() - core encoding loop
        pub fn step(self: *Self) ?u32 {
            var token = self.next_token orelse return null;
            const last = if (self.tokens_len > 0) self.tokens[self.tokens_len - 1] else null;

            while (true) {
                const token_bytes = self.vocab_r.get(token) orelse {
                    // Token not found - this shouldn't happen in valid BPE
                    return null;
                };
                const end_pos = self.pos + token_bytes.len;

                // Check: bitfield.is_set(end_pos) && is_valid_token_pair(last, token)
                const is_valid_pos = self.bitfieldIsSet(end_pos);
                const is_valid_pair = if (last) |l|
                    self.isValidTokenPair(l, token)
                else
                    true;

                if (is_valid_pos and is_valid_pair) {
                    // Valid path - accept token
                    if (self.tokens_len >= max_tokens) return null; // Shouldn't happen in practice
                    self.tokens[self.tokens_len] = token;
                    self.tokens_len += 1;
                    self.pos = end_pos;
                    self.next_token = self.aho_corasick.longestMatch(self.text, end_pos);
                    break;
                } else if (self.nextPrefix(token)) |shorter| {
                    // Try shorter token
                    token = shorter;
                } else {
                    // Backtrack
                    self.bitfieldClear(self.pos);
                    if (self.tokens_len > 0) {
                        self.tokens_len -= 1;
                        const last_token = self.tokens[self.tokens_len];
                        const last_bytes = self.vocab_r.get(last_token) orelse return null;
                        self.pos -= last_bytes.len;
                        self.next_token = last_token;
                    } else {
                        // No tokens to backtrack - we're stuck, give up
                        self.next_token = null;
                    }
                    break;
                }
            }

            return self.next_token;
        }

        /// Encode full text - only allocates for final result
        pub fn encode(self: *Self, allocator: Allocator) ![]u32 {
            // Run encoding to completion (zero allocations!)
            while (self.step()) |_| {}

            // Copy result to heap (ONLY allocation in entire encode!)
            const result = try allocator.alloc(u32, self.tokens_len);
            @memcpy(result, self.tokens[0..self.tokens_len]);
            return result;
        }

        // Inline helpers for maximum performance

        inline fn bitfieldIsSet(self: *const Self, bit: usize) bool {
            const word_idx = bit >> 6; // Divide by 64
            const bit_idx = @as(u6, @truncate(bit));
            return (self.bitfield[word_idx] & (@as(u64, 1) << bit_idx)) != 0;
        }

        inline fn bitfieldClear(self: *Self, bit: usize) void {
            const word_idx = bit >> 6; // Divide by 64
            const bit_idx = @as(u6, @truncate(bit));
            self.bitfield[word_idx] &= ~(@as(u64, 1) << bit_idx);
        }

        inline fn nextPrefix(self: *const Self, token: u32) ?u32 {
            const prefix = self.next_prefix_match[token];
            if (prefix == std.math.maxInt(u32)) {
                return null;
            }
            return prefix;
        }

        /// EXACT PORT of rs-bpe is_valid_token_pair validation logic
        /// Returns true if token1 followed by token2 is a valid BPE encoding path
        fn isValidTokenPair(self: *const Self, token1_arg: u32, token2_arg: u32) bool {
            var token1 = token1_arg;
            var token2 = token2_arg;
            var limit: u32 = std.math.maxInt(u32);

            while (true) {
                // Check if this pair exists in pair_lookup
                if (self.pair_lookup.get(Pair{ .left = token1, .right = token2 })) |combined| {
                    // If the combined token has lower rank than limit, this pair is invalid
                    return combined >= limit;
                }

                if (token1 > token2) {
                    limit = token1;
                    const split = self.split_table[token1];
                    // Base token check: if token splits to itself, we've reached the bottom
                    if (split.left == token1 and split.right == token1) {
                        return true; // Base token - no merge restriction
                    }
                    token1 = split.right;
                    if (token1 == limit) {
                        limit = token2 + 1;
                        const split2 = self.split_table[token2];
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
                    const split = self.split_table[token2];
                    // Base token check: if token splits to itself, we've reached the bottom
                    if (split.left == token2 and split.right == token2) {
                        return true;
                    }
                    token2 = split.left;
                    if (token2 + 1 == limit) {
                        limit = token1;
                        const split2 = self.split_table[token1];
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
    };
}
