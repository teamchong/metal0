/// Unigram Language Model for tokenization
/// Implements Viterbi decoding and training via EM algorithm
/// Ported from HuggingFace tokenizers/src/models/unigram/model.rs (640 lines)

const std = @import("std");
const hashmap_helper = @import("hashmap_helper.zig");
const Allocator = std.mem.Allocator;
const Lattice = @import("unigram_lattice.zig").Lattice;
const Trie = @import("unigram_trie.zig").Trie;

const K_UNK_PENALTY: f64 = 10.0;

/// Vocabulary entry: (token, log_probability)
pub const VocabEntry = struct {
    token: []const u8,
    score: f64,  // Log probability

    pub fn deinit(self: *VocabEntry, allocator: Allocator) void {
        allocator.free(self.token);
    }
};

/// Unigram model for encoding sentences
pub const Unigram = struct {
    vocab: []VocabEntry,        // Vocabulary with log probabilities
    token_to_ids: hashmap_helper.StringHashMap(u32), // Token → ID mapping
    trie: Trie(u8),             // Prefix trie for efficient lookup
    min_score: f64,             // Minimum score in vocabulary
    unk_id: ?usize,             // Unknown token ID
    bos_id: usize,              // Beginning of sentence ID
    eos_id: usize,              // End of sentence ID
    allocator: Allocator,

    pub fn init(allocator: Allocator, vocab_list: []const VocabEntry, unk_id: ?usize) !Unigram {
        const n = vocab_list.len;

        if (unk_id) |uid| {
            if (vocab_list.len == 0) {
                return error.EmptyVocabulary;
            }
            if (uid >= vocab_list.len) {
                return error.UnkIdNotInVocabulary;
            }
        }

        // Copy vocabulary
        var vocab = try allocator.alloc(VocabEntry, n);
        errdefer allocator.free(vocab);

        for (vocab_list, 0..) |entry, i| {
            vocab[i] = VocabEntry{
                .token = try allocator.dupe(u8, entry.token),
                .score = entry.score,
            };
        }

        // Build token → ID map
        var token_to_ids = hashmap_helper.StringHashMap(u32).init(allocator);
        errdefer token_to_ids.deinit();

        // Build trie
        var trie = try Trie(u8).init(allocator);
        errdefer trie.deinit();

        var min_score: f64 = std.math.inf(f64);
        for (vocab, 0..) |entry, id| {
            try token_to_ids.put(entry.token, @intCast(id));
            try trie.push(entry.token);
            if (entry.score < min_score) {
                min_score = entry.score;
            }
        }

        const bos_id = n + 1;
        const eos_id = n + 2;

        return Unigram{
            .vocab = vocab,
            .token_to_ids = token_to_ids,
            .trie = trie,
            .min_score = min_score,
            .unk_id = unk_id,
            .bos_id = bos_id,
            .eos_id = eos_id,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Unigram) void {
        for (self.vocab) |*entry| {
            entry.deinit(self.allocator);
        }
        self.allocator.free(self.vocab);
        self.token_to_ids.deinit();
        self.trie.deinit();
    }

    /// Populate lattice with candidate tokens from vocabulary
    pub fn populateNodes(self: *const Unigram, lattice: *Lattice) !void {
        const unk_score = self.min_score - K_UNK_PENALTY;
        const len = lattice.len;

        var begin_pos: usize = 0;
        while (begin_pos < len) {
            const remaining = lattice.sentence[begin_pos..];
            const mblen = std.unicode.utf8ByteSequenceLength(remaining[0]) catch break;

            var has_single_node = false;

            // Find all tokens matching this prefix
            var iter = self.trie.commonPrefixSearch(remaining);
            while (iter.next()) |prefix_len| {
                const tok = remaining[0..prefix_len];
                if (self.token_to_ids.get(tok)) |id| {
                    const score = self.vocab[id].score;
                    try lattice.insert(begin_pos, prefix_len, score, id);

                    if (!has_single_node and prefix_len == mblen) {
                        has_single_node = true;
                    }
                }
            }

            // Insert UNK if no single-character match found
            if (!has_single_node) {
                if (self.unk_id) |unk_id| {
                    try lattice.insert(begin_pos, mblen, unk_score, unk_id);
                }
            }

            begin_pos += mblen;
        }
    }

    /// Encode a sentence using Viterbi decoding
    pub fn encode(self: *const Unigram, allocator: Allocator, sentence: []const u8) ![][]const u8 {
        if (sentence.len == 0) {
            return try allocator.alloc([]const u8, 0);
        }

        // Create lattice
        var lattice = try Lattice.init(allocator, sentence, self.bos_id, self.eos_id);
        defer lattice.deinit();

        // Populate with token candidates
        try self.populateNodes(&lattice);

        // Find best path using Viterbi
        return try lattice.tokens(allocator);
    }

    /// Encode optimized version (faster, no full lattice)
    /// Uses dynamic programming without constructing full lattice
    pub fn encodeOptimized(self: *const Unigram, allocator: Allocator, sentence: []const u8) ![][]const u8 {
        if (sentence.len == 0) {
            return try allocator.alloc([]const u8, 0);
        }

        const BestPathNode = struct {
            id: usize,
            best_path_score: f64,
            starts_at: ?usize,
        };

        const size = sentence.len;
        const unk_score = self.min_score - K_UNK_PENALTY;

        // DP array: best_path_ends_at[i] = best path ending at position i
        var best_path_ends_at = try allocator.alloc(BestPathNode, size + 1);
        defer allocator.free(best_path_ends_at);

        @memset(best_path_ends_at, BestPathNode{
            .id = 0,
            .best_path_score = 0.0,
            .starts_at = null,
        });

        var starts_at: usize = 0;
        while (starts_at < size) {
            const best_path_score_till_here = best_path_ends_at[starts_at].best_path_score;
            const remaining = sentence[starts_at..];
            const mblen = std.unicode.utf8ByteSequenceLength(remaining[0]) catch break;
            var has_single_node = false;

            // Try all matching tokens
            var iter = self.trie.commonPrefixSearch(remaining);
            while (iter.next()) |prefix_len| {
                const key_pos = starts_at + prefix_len;
                const token = remaining[0..prefix_len];

                if (self.token_to_ids.get(token)) |id| {
                    const score = self.vocab[id].score;
                    const candidate_score = score + best_path_score_till_here;

                    var target = &best_path_ends_at[key_pos];
                    if (target.starts_at == null or candidate_score > target.best_path_score) {
                        target.best_path_score = candidate_score;
                        target.starts_at = starts_at;
                        target.id = id;
                    }

                    if (!has_single_node and prefix_len == mblen) {
                        has_single_node = true;
                    }
                }
            }

            // Handle UNK
            if (!has_single_node) {
                if (self.unk_id) |unk_id| {
                    const target_pos = starts_at + mblen;
                    const candidate_score = unk_score + best_path_score_till_here;
                    var target = &best_path_ends_at[target_pos];

                    if (target.starts_at == null or candidate_score > target.best_path_score) {
                        target.best_path_score = candidate_score;
                        target.starts_at = starts_at;
                        target.id = unk_id;
                    }
                }
            }

            starts_at += mblen;
        }

        // Backtrace to build result
        var result = std.ArrayList([]const u8){};
        errdefer result.deinit(allocator);

        var pos: usize = size;
        while (pos > 0) {
            const node = best_path_ends_at[pos];
            if (node.starts_at) |start| {
                const token = try allocator.dupe(u8, sentence[start..pos]);
                try result.append(allocator, token);
                pos = start;
            } else {
                break;
            }
        }

        // Reverse to get forward order
        std.mem.reverse([]const u8, result.items);
        return result.toOwnedSlice(allocator);
    }
};

// Tests
test "Unigram basic encoding" {
    const allocator = std.testing.allocator;

    // Create simple vocabulary: a, b, ab (where ab is preferred)
    const vocab_list = [_]VocabEntry{
        .{ .token = "<unk>", .score = 0.0 },
        .{ .token = "a", .score = -1.0 },
        .{ .token = "b", .score = -1.0 },
        .{ .token = "ab", .score = -0.1 }, // Better score
    };

    var model = try Unigram.init(allocator, &vocab_list, 0);
    defer model.deinit();

    // Encode "ab" - should prefer single token
    const result = try model.encodeOptimized(allocator, "ab");
    defer {
        for (result) |token| allocator.free(token);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("ab", result[0]);
}
