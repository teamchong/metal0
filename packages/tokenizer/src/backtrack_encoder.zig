/// EXACT PORT of rs-bpe's backtrack_encoder.rs
/// Based on: rs-bpe/bpe/src/backtrack_encoder.rs lines 1-87
const std = @import("std");
const Allocator = std.mem.Allocator;
const AhoCorasick = @import("aho_corasick.zig").AhoCorasick;
const pool_mod = @import("pool.zig");

// MUST match tokenizer.Pair exactly
pub const Pair = struct {
    left: u32,
    right: u32,

    pub fn hash(self: Pair) u64 {
        return (@as(u64, self.left) << 32) | self.right;
    }

    pub fn eql(a: Pair, b: Pair) bool {
        return a.left == b.left and a.right == b.right;
    }
};

pub const PairContext = struct {
    pub fn hash(_: PairContext, p: Pair) u64 {
        return p.hash();
    }

    pub fn eql(_: PairContext, a: Pair, b: Pair) bool {
        return Pair.eql(a, b);
    }
};

/// Port of rs-bpe BacktrackEncoder struct
pub const BacktrackEncoder = struct {
    allocator: Allocator,
    result_allocator: Allocator, // Allocator for final result (arena vs permanent)
    text: []const u8,
    tokens: std.ArrayList(u32),
    next_token: ?u32,
    pos: usize,
    bitfield: BitField,
    bitfield_pool_node: ?*BitFieldPool.Node, // Pool node for releasing

    // BPE data
    aho_corasick: *const AhoCorasick,
    vocab_r: *const std.AutoHashMap(u32, []const u8),
    split_table: *const std.AutoHashMap(u32, Pair),
    pair_lookup: *const std.HashMap(Pair, u32, PairContext, std.hash_map.default_max_load_percentage),
    next_prefix_match: []const u32, // Precomputed prefix table

    /// Port of rs-bpe::new() with arena allocator for temporary allocations
    /// arena: Used for BitField and temporary ArrayList allocations
    /// result_allocator: Used for final result slice
    pub fn initArena(
        arena: Allocator,
        result_allocator: Allocator,
        text: []const u8,
        aho_corasick: *const AhoCorasick,
        vocab_r: *const std.AutoHashMap(u32, []const u8),
        split_table: *const std.AutoHashMap(u32, Pair),
        pair_lookup: *const std.HashMap(Pair, u32, PairContext, std.hash_map.default_max_load_percentage),
        next_prefix_match: []const u32,
    ) !BacktrackEncoder {
        var tokens = std.ArrayList(u32){};
        try tokens.ensureTotalCapacity(arena, text.len / 3);

        // bpe.next_match(text) (line 31)
        const first_token = aho_corasick.longestMatch(text, 0);

        // Get BitField from pool
        var bf_node = BitFieldPool.get(arena);

        // Resize if needed
        const needed_size = text.len + 1;
        if (bf_node.data.capacity < needed_size) {
            // Need larger BitField - reallocate
            bf_node.data.deinit();
            bf_node.data = try BitField.init(bf_node.allocator, needed_size);
        } else {
            // Reuse existing - just reset
            bf_node.data.reset();
        }

        return BacktrackEncoder{
            .allocator = arena,
            .result_allocator = result_allocator,
            .text = text,
            .tokens = tokens,
            .next_token = first_token,
            .pos = 0,
            .bitfield = bf_node.data,
            .bitfield_pool_node = bf_node,
            .aho_corasick = aho_corasick,
            .vocab_r = vocab_r,
            .split_table = split_table,
            .pair_lookup = pair_lookup,
            .next_prefix_match = next_prefix_match,
        };
    }

    /// Port of rs-bpe::new() (line 22-34)
    pub fn init(
        allocator: Allocator,
        text: []const u8,
        aho_corasick: *const AhoCorasick,
        vocab_r: *const std.AutoHashMap(u32, []const u8),
        split_table: *const std.AutoHashMap(u32, Pair),
        pair_lookup: *const std.HashMap(Pair, u32, PairContext, std.hash_map.default_max_load_percentage),
        next_prefix_match: []const u32,
    ) !BacktrackEncoder {
        var tokens = std.ArrayList(u32){};
        try tokens.ensureTotalCapacity(allocator, text.len / 3);

        // bpe.next_match(text) (line 31)
        const first_token = aho_corasick.longestMatch(text, 0);

        // Get BitField from pool
        var bf_node = BitFieldPool.get(allocator);

        // Resize if needed
        const needed_size = text.len + 1;
        if (bf_node.data.capacity < needed_size) {
            // Need larger BitField - reallocate
            bf_node.data.deinit();
            bf_node.data = try BitField.init(bf_node.allocator, needed_size);
        } else {
            // Reuse existing - just reset
            bf_node.data.reset();
        }

        return BacktrackEncoder{
            .allocator = allocator,
            .result_allocator = allocator,
            .text = text,
            .tokens = tokens,
            .next_token = first_token,
            .pos = 0,
            .bitfield = bf_node.data,
            .bitfield_pool_node = bf_node,
            .aho_corasick = aho_corasick,
            .vocab_r = vocab_r,
            .split_table = split_table,
            .pair_lookup = pair_lookup,
            .next_prefix_match = next_prefix_match,
        };
    }

    pub fn deinit(self: *BacktrackEncoder) void {
        self.tokens.deinit(self.allocator);
        // Return BitField to pool instead of freeing
        if (self.bitfield_pool_node) |node| {
            BitFieldPool.release(node);
        }
    }

    /// Port of rs-bpe step() (lines 37-70)
    pub fn step(self: *BacktrackEncoder) ?u32 {
        var token = self.next_token orelse return null;
        const last = if (self.tokens.items.len > 0) self.tokens.items[self.tokens.items.len - 1] else null;

        while (true) {
            const token_len = self.tokenLen(token);
            const end_pos = self.pos + token_len;

            // Check: bitfield.is_set(end_pos) && is_valid_token_pair(last, token)
            const bitfield_ok = self.bitfield.isSet(end_pos);
            const pair_ok = if (last) |last_token|
                isValidTokenPairImpl(self.pair_lookup, self.split_table, last_token, token)
            else
                true;

            if (bitfield_ok and pair_ok) {
                // Valid path - accept token
                self.tokens.append(self.allocator, token) catch return null;
                self.pos = end_pos;
                self.next_token = self.aho_corasick.longestMatch(self.text, end_pos);
                break;
            } else if (self.nextPrefix(token)) |shorter| {
                // Try shorter token
                token = shorter;
            } else {
                // Backtrack
                self.bitfield.clear(self.pos);
                if (self.tokens.items.len > 0) {
                    _ = self.tokens.pop();
                }
                self.pos -= if (last) |t| self.tokenLen(t) else 0;
                self.next_token = last;
                break;
            }
        }

        return self.next_token;
    }

    /// Encode full text (call step() until done)
    pub fn encode(self: *BacktrackEncoder) ![]u32 {
        while (self.step()) |_| {}

        // Copy result to result_allocator (important when using arena)
        const result = try self.result_allocator.alloc(u32, self.tokens.items.len);
        @memcpy(result, self.tokens.items);
        return result;
    }

    /// Get token length in bytes (port of bpe.token_len)
    fn tokenLen(self: *const BacktrackEncoder, token: u32) usize {
        if (self.vocab_r.get(token)) |bytes| {
            return bytes.len;
        }
        return 1; // Single byte fallback
    }

    /// Port of bpe.next_prefix - EXACT COPY from rs-bpe
    /// Returns precomputed next shorter prefix match
    fn nextPrefix(self: *const BacktrackEncoder, token: u32) ?u32 {
        const prefix = self.next_prefix_match[token];
        if (prefix == std.math.maxInt(u32)) {
            return null;
        } else {
            return prefix;
        }
    }
};

/// EXACT PORT of rs-bpe is_valid_token_pair (from byte_pair_encoding.rs lines 112-148)
fn isValidTokenPairImpl(
    pair_lookup: *const std.HashMap(Pair, u32, PairContext, std.hash_map.default_max_load_percentage),
    split_table: *const std.AutoHashMap(u32, Pair),
    token1_arg: u32,
    token2_arg: u32,
) bool {
    var token1 = token1_arg;
    var token2 = token2_arg;
    var limit: u32 = std.math.maxInt(u32);

    while (true) {
        // Check if this pair exists in pair_lookup
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

/// BitField for tracking visited positions
const BitField = struct {
    bits: []u64,
    allocator: Allocator,
    capacity: usize, // Track allocated capacity

    pub fn init(allocator: Allocator, size: usize) !BitField {
        const num_words = (size + 63) / 64;
        const bits = try allocator.alloc(u64, num_words);
        @memset(bits, 0xFFFFFFFFFFFFFFFF); // All bits set initially

        return BitField{
            .bits = bits,
            .allocator = allocator,
            .capacity = size,
        };
    }

    pub fn deinit(self: *BitField) void {
        self.allocator.free(self.bits);
    }

    pub fn reset(self: *BitField) void {
        // Reset all bits to 1 (all positions valid)
        @memset(self.bits, 0xFFFFFFFFFFFFFFFF);
    }

    pub inline fn isSet(self: *const BitField, pos: usize) bool {
        const word = pos >> 6;
        const bit = @as(u6, @truncate(pos));
        return (self.bits[word] & (@as(u64, 1) << bit)) != 0;
    }

    pub inline fn clear(self: *BitField, pos: usize) void {
        const word = pos >> 6;
        const bit = @as(u6, @truncate(pos));
        self.bits[word] &= ~(@as(u64, 1) << bit);
    }
};

// Pool for BitField reuse (threadsafe, max 8 cached)
const BitFieldPool = pool_mod.ObjectPool(BitField, null, true, 8);
