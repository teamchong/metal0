/// High-performance BPE tokenizer in pure Zig
/// Targets: 1.1-1.25x faster than Rust rustbpe
/// Features: SIMD, parallel processing, comptime optimization, zero-copy

const std = @import("std");
const Allocator = std.mem.Allocator;

// External dependencies
const BacktrackEncoder = @import("backtrack_encoder.zig").BacktrackEncoder;
const encodeGreedy = @import("greedy_encoder.zig").encodeGreedy;
const encodeOptimized = @import("optimized_hashmap_encoder.zig").encodeOptimized;
const cl100k_splitter = @import("cl100k_splitter.zig");
const AhoCorasick = @import("aho_corasick.zig").AhoCorasick;

// Re-export modular components
const helpers = @import("tokenizer_helpers.zig");
pub const Pair = helpers.Pair;
pub const PairContext = helpers.PairContext;
pub const BitField = helpers.BitField;
pub const TrieNode = helpers.TrieNode;
pub const countPairsSIMD = helpers.countPairsSIMD;
pub const mergePair = helpers.mergePair;

const builder = @import("tokenizer_builder.zig");
const buildSplitTable = builder.buildSplitTable;
const buildAhoCorasick = builder.buildAhoCorasick;
const buildNextPrefixMatch = builder.buildNextPrefixMatch;
const isValidTokenPair = builder.isValidTokenPair;

const parser = @import("tokenizer_parser.zig");

pub const Tokenizer = struct {
    vocab: std.StringHashMap(u32),
    vocab_r: std.AutoHashMap(u32, []const u8),
    merges: std.ArrayList(Pair),
    merges_map: std.HashMap(Pair, u32, PairContext, std.hash_map.default_max_load_percentage),
    split_table: std.AutoHashMap(u32, Pair), // For merge validation: token -> (left, right)
    pattern_str: []const u8,
    trie: ?*TrieNode, // Fast longest-match lookup (optional - uses lots of memory)
    aho_corasick: ?AhoCorasick, // Fast vocab lookup for backtracking encoder
    next_prefix_match: []u32, // Precomputed next_prefix table (rs-bpe optimization)
    allocator: Allocator,

    pub fn initFromData(json_data: []const u8, allocator: Allocator) !Tokenizer {
        const data = try parser.initFromData(json_data, allocator);
        return Tokenizer{
            .vocab = data.vocab,
            .vocab_r = data.vocab_r,
            .merges = data.merges,
            .merges_map = data.merges_map,
            .split_table = data.split_table,
            .pattern_str = data.pattern_str,
            .trie = data.trie,
            .aho_corasick = data.aho_corasick,
            .next_prefix_match = data.next_prefix_match,
            .allocator = data.allocator,
        };
    }

    pub fn init(tokenizer_path: []const u8, allocator: Allocator) !Tokenizer {
        const data = try parser.initFromFile(tokenizer_path, allocator);
        return Tokenizer{
            .vocab = data.vocab,
            .vocab_r = data.vocab_r,
            .merges = data.merges,
            .merges_map = data.merges_map,
            .split_table = data.split_table,
            .pattern_str = data.pattern_str,
            .trie = data.trie,
            .aho_corasick = data.aho_corasick,
            .next_prefix_match = data.next_prefix_match,
            .allocator = data.allocator,
        };
    }

    pub fn deinit(self: *Tokenizer) void {
        var vocab_it = self.vocab.iterator();
        while (vocab_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.vocab.deinit();
        self.vocab_r.deinit();
        self.merges.deinit(self.allocator);
        self.merges_map.deinit();
        self.split_table.deinit();
        self.allocator.free(self.pattern_str);
        if (self.trie) |t| t.deinit();
        if (self.aho_corasick) |*ac| ac.deinit();
        self.allocator.free(self.next_prefix_match);
    }

    /// HASH MAP optimization: O(n * k) instead of O(n * m)
    /// k = actual merges applied << m = total possible merges
    pub fn encodeHashMap(self: *Tokenizer, text: []const u8) ![]u32 {
        if (text.len <= 4096) {
            var stack_buffer: [4096]u32 = undefined;

            // Start with bytes - look up each byte's rank in vocab
            for (text, 0..) |byte, i| {
                const byte_slice = @as(*const [1]u8, &byte)[0..1];
                const rank = self.vocab.get(byte_slice) orelse byte; // Fallback to byte value
                stack_buffer[i] = rank;
            }

            const len = try self.applyMergesHashMap(stack_buffer[0..text.len]);

            const result = try self.allocator.alloc(u32, len);
            @memcpy(result, stack_buffer[0..len]);
            return result;
        }

        // Large text path
        var tokens = try std.ArrayList(u32).initCapacity(self.allocator, text.len);
        errdefer tokens.deinit(self.allocator);

        for (text) |byte| {
            const byte_slice = @as(*const [1]u8, &byte)[0..1];
            const rank = self.vocab.get(byte_slice) orelse byte;
            tokens.appendAssumeCapacity(rank);
        }

        try self.applyMergesHashMapArrayList(&tokens);
        return try tokens.toOwnedSlice(self.allocator);
    }

    /// Vocab-based BPE merging (tiktoken style) - OPTIMIZED O(n²)
    /// Uses skip array to avoid O(n) shifting on every merge
    fn applyMergesHashMap(self: *Tokenizer, tokens: []u32) !usize {
        @setRuntimeSafety(false);

        if (tokens.len < 2) return tokens.len;

        // Skip array: -1 = active, >= 0 = merged (skipped)
        var skip_buffer: [4096]i32 = undefined;
        var skip = skip_buffer[0..tokens.len];
        @memset(skip, -1); // All active initially

        var merge_buffer: [512]u8 = undefined;
        var active_count = tokens.len;

        while (active_count > 1) {
            var best_rank: u32 = std.math.maxInt(u32);
            var best_new_token: u32 = 0;
            var best_pos: usize = 0;

            // Scan active pairs (skip merged positions)
            var i: usize = 0;
            while (i < tokens.len) {
                if (skip[i] >= 0) {
                    i += 1;
                    continue;
                }

                // Find next active position
                var next = i + 1;
                while (next < tokens.len and skip[next] >= 0) : (next += 1) {}
                if (next >= tokens.len) break;

                const left_token = tokens[i];
                const right_token = tokens[next];

                const left_bytes = self.vocab_r.get(left_token) orelse {
                    i = next;
                    continue;
                };
                const right_bytes = self.vocab_r.get(right_token) orelse {
                    i = next;
                    continue;
                };

                const total_len = left_bytes.len + right_bytes.len;
                if (total_len <= merge_buffer.len) {
                    @memcpy(merge_buffer[0..left_bytes.len], left_bytes);
                    @memcpy(merge_buffer[left_bytes.len..total_len], right_bytes);

                    if (self.vocab.get(merge_buffer[0..total_len])) |merged_rank| {
                        if (merged_rank < best_rank) {
                            best_rank = merged_rank;
                            best_new_token = merged_rank;
                            best_pos = i;
                        }
                    }
                }

                i = next;
            }

            if (best_rank == std.math.maxInt(u32)) break;

            // Apply merge: replace left with merged, mark right as skipped
            tokens[best_pos] = best_new_token;

            // Find next active and mark as merged
            var next_active = best_pos + 1;
            while (next_active < tokens.len and skip[next_active] >= 0) : (next_active += 1) {}
            if (next_active < tokens.len) {
                skip[next_active] = @intCast(next_active);
                active_count -= 1;
            }
        }

        // Compact: collect only active tokens
        var write_pos: usize = 0;
        for (tokens, 0..) |token, i| {
            if (skip[i] < 0) {
                tokens[write_pos] = token;
                write_pos += 1;
            }
        }

        return write_pos;
    }

    fn applyMergesHashMapArrayList(self: *Tokenizer, tokens: *std.ArrayList(u32)) !void {
        var merge_buffer: [512]u8 = undefined;

        while (true) {
            var best_rank: u32 = std.math.maxInt(u32);
            var best_new_token: u32 = 0;
            var best_pos: usize = 0;

            var i: usize = 0;
            while (i + 1 < tokens.items.len) : (i += 1) {
                const left_token = tokens.items[i];
                const right_token = tokens.items[i + 1];

                const left_bytes = self.vocab_r.get(left_token) orelse continue;
                const right_bytes = self.vocab_r.get(right_token) orelse continue;

                const total_len = left_bytes.len + right_bytes.len;
                if (total_len > merge_buffer.len) continue;

                @memcpy(merge_buffer[0..left_bytes.len], left_bytes);
                @memcpy(merge_buffer[left_bytes.len..total_len], right_bytes);

                if (self.vocab.get(merge_buffer[0..total_len])) |merged_rank| {
                    if (merged_rank < best_rank) {
                        best_rank = merged_rank;
                        best_new_token = merged_rank;
                        best_pos = i;
                    }
                }
            }

            if (best_rank == std.math.maxInt(u32)) break;

            tokens.items[best_pos] = best_new_token;
            _ = tokens.orderedRemove(best_pos + 1);
        }
    }

    /// Trie-based longest-match encoding (fast + correct)
    /// Falls back to HashMap if trie not available (WASM)
    /// Encode using HashMap BPE (100% correct, 33x slower than rs-bpe)
    /// OPTIMIZED: Uses zero-allocation iterator + Arena allocator
    pub fn encode(self: *Tokenizer, text: []const u8) ![]u32 {
        @setRuntimeSafety(false);

        // Arena for this encoding session - bulk-freed at end
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const arena_alloc = arena.allocator();

        // Pre-allocate result (use original allocator for return value)
        var result = std.ArrayList(u32){};
        try result.ensureTotalCapacity(self.allocator, text.len / 4);
        errdefer result.deinit(self.allocator);

        // Iterate through chunks (zero allocations for splitting!)
        var chunk_iter = cl100k_splitter.chunks(text);
        while (chunk_iter.next()) |chunk| {
            const chunk_tokens = try self.encodeViaBacktrackingArena(chunk, arena_alloc);
            try result.appendSlice(self.allocator, chunk_tokens);
        }

        return try result.toOwnedSlice(self.allocator);
    }

    /// Port of rs-bpe's encode_via_backtracking with arena allocator
    fn encodeViaBacktrackingArena(self: *Tokenizer, text: []const u8, arena: Allocator) ![]u32 {
        if (text.len == 0) return try self.allocator.alloc(u32, 0);

        // Use Aho-Corasick + split_table + pair_lookup if available
        if (self.aho_corasick) |*ac| {
            var encoder = try BacktrackEncoder.initArena(
                arena,
                self.allocator,
                text,
                ac,
                &self.vocab_r,
                @ptrCast(&self.split_table),
                @ptrCast(&self.merges_map),
                self.next_prefix_match,
            );
            defer encoder.deinit();
            return try encoder.encode();
        }

        // Fallback: HashMap encoder (slow but works without Aho-Corasick)
        return try self.encodeHashMap(text);
    }

    /// Decode token IDs back to text
    pub fn decode(self: *Tokenizer, tokens: []const u32) ![]u8 {
        var result = std.ArrayList(u8){};
        errdefer result.deinit(self.allocator);

        for (tokens) |token_id| {
            if (self.vocab_r.get(token_id)) |token_str| {
                try result.appendSlice(self.allocator, token_str);
            } else if (token_id < 256) {
                // Raw byte
                try result.append(self.allocator, @intCast(token_id));
            }
        }

        return try result.toOwnedSlice(self.allocator);
    }
};

// Tests
test "SIMD pair counting" {
    const ids = [_]u32{ 1, 2, 3, 2, 3, 2, 3, 4 };
    const pair = Pair{ .left = 2, .right = 3 };
    const count = countPairsSIMD(&ids, pair);
    try std.testing.expectEqual(@as(u32, 3), count);
}

test "pair merging" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var tokens = std.ArrayList(u32){};
    try tokens.appendSlice(allocator, &[_]u32{ 1, 2, 3, 2, 3, 4 });

    const pair = Pair{ .left = 2, .right = 3 };
    try mergePair(&tokens, pair, 100, allocator);

    try std.testing.expectEqualSlices(u32, &[_]u32{ 1, 100, 100, 4 }, tokens.items);
}
