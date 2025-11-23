/// BPE Trainer - Full HuggingFace tokenizers port
/// Ported from: tokenizers/src/models/bpe/trainer.rs

const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Word = @import("bpe_word.zig").Word;
const Pair = @import("bpe_word.zig").Pair;
const Change = @import("bpe_word.zig").Change;
const hashmap_helper = @import("hashmap_helper.zig");

/// Merge result (pair → new_id)
const MergeResult = struct {
    pair: Pair,
    new_id: u32,
};

/// Merge candidate for priority queue
const MergeCandidate = struct {
    pair: Pair,
    count: u64,
    // Position set stored separately in where_to_update

    fn lessThan(_: void, a: MergeCandidate, b: MergeCandidate) std.math.Order {
        // Priority queue is max-heap, so reverse comparison
        if (a.count != b.count) {
            return std.math.order(b.count, a.count); // Higher count = higher priority
        }
        // Tie-breaker: lexicographic on pair (for determinism)
        if (a.pair.left != b.pair.left) {
            return std.math.order(a.pair.left, b.pair.left);
        }
        return std.math.order(a.pair.right, b.pair.right);
    }
};

/// BPE Trainer with all HuggingFace features
pub const BpeTrainer = struct {
    // Configuration
    min_frequency: u64,
    vocab_size: usize,
    special_tokens: []const []const u8,
    limit_alphabet: ?usize,
    initial_alphabet: std.AutoHashMap(u21, void), // char set
    continuing_subword_prefix: ?[]const u8, // e.g. "##" for BERT
    end_of_word_suffix: ?[]const u8,
    max_token_length: ?usize,

    // Training state
    allocator: Allocator,
    word_counts: hashmap_helper.StringHashMap(u64),

    pub fn init(vocab_size: usize, allocator: Allocator) !BpeTrainer {
        return BpeTrainer{
            .min_frequency = 0,
            .vocab_size = vocab_size,
            .special_tokens = &[_][]const u8{},
            .limit_alphabet = null,
            .initial_alphabet = std.AutoHashMap(u21, void).init(allocator),
            .continuing_subword_prefix = null,
            .end_of_word_suffix = null,
            .max_token_length = null,
            .allocator = allocator,
            .word_counts = hashmap_helper.StringHashMap(u64).init(allocator),
        };
    }

    pub fn deinit(self: *BpeTrainer) void {
        self.initial_alphabet.deinit();
        self.word_counts.deinit();
    }

    /// Add special tokens to vocabulary
    fn addSpecialTokens(
        self: *BpeTrainer,
        word_to_id: *hashmap_helper.StringHashMap(u32),
        id_to_word: *std.ArrayList([]const u8),
    ) !void {
        for (self.special_tokens) |token| {
            if (!word_to_id.contains(token)) {
                const id: u32 = @intCast(id_to_word.items.len);
                const owned = try self.allocator.dupe(u8, token);
                try id_to_word.append(self.allocator, owned);
                try word_to_id.put(owned, id);
            }
        }
    }

    /// Compute initial alphabet from word counts
    fn computeAlphabet(
        self: *BpeTrainer,
        word_to_id: *hashmap_helper.StringHashMap(u32),
        id_to_word: *std.ArrayList([]const u8),
    ) !void {
        // Count character frequencies
        var alphabet = std.AutoHashMap(u21, usize).init(self.allocator);
        defer alphabet.deinit();

        var it = self.word_counts.iterator();
        while (it.next()) |entry| {
            const word = entry.key_ptr.*;
            const count = entry.value_ptr.*;

            var utf8_view = std.unicode.Utf8View.init(word) catch continue;
            var char_it = utf8_view.iterator();
            while (char_it.nextCodepoint()) |codepoint| {
                const gop = try alphabet.getOrPut(codepoint);
                if (gop.found_existing) {
                    gop.value_ptr.* += @intCast(count);
                } else {
                    gop.value_ptr.* = @intCast(count);
                }
            }
        }

        // Add initial alphabet (max priority)
        var init_it = self.initial_alphabet.iterator();
        while (init_it.next()) |entry| {
            try alphabet.put(entry.key_ptr.*, std.math.maxInt(usize));
        }

        // Sort by frequency and keep top N if limit_alphabet is set
        var chars = std.ArrayList(struct { char: u21, count: usize }){};
        defer chars.deinit(self.allocator);

        var alpha_it = alphabet.iterator();
        while (alpha_it.next()) |entry| {
            try chars.append(self.allocator, .{ .char = entry.key_ptr.*, .count = entry.value_ptr.* });
        }

        // Sort by count (ascending) then by codepoint (for determinism)
        std.mem.sort(@TypeOf(chars.items[0]), chars.items, {}, struct {
            fn lessThan(_: void, a: @TypeOf(chars.items[0]), b: @TypeOf(chars.items[0])) bool {
                if (a.count != b.count) return a.count < b.count;
                return a.char < b.char;
            }
        }.lessThan);

        // Remove lowest frequency chars if needed
        if (self.limit_alphabet) |limit| {
            const to_remove = chars.items.len -| limit;
            if (to_remove > 0) {
                // Remove lowest frequency items
                for (0..to_remove) |_| {
                    _ = chars.orderedRemove(0);
                }
            }
        }

        // Sort by codepoint for deterministic vocab ordering
        std.mem.sort(@TypeOf(chars.items[0]), chars.items, {}, struct {
            fn lessThan(_: void, a: @TypeOf(chars.items[0]), b: @TypeOf(chars.items[0])) bool {
                return a.char < b.char;
            }
        }.lessThan);

        // Add to vocab
        for (chars.items) |item| {
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(item.char, &buf) catch continue;
            const char_str = try self.allocator.dupe(u8, buf[0..len]);

            if (!word_to_id.contains(char_str)) {
                const id: u32 = @intCast(id_to_word.items.len);
                try id_to_word.append(self.allocator, char_str);
                try word_to_id.put(char_str, id);
            } else {
                self.allocator.free(char_str);
            }
        }
    }

    /// Tokenize words into Word objects using current vocabulary
    fn tokenizeWords(
        self: *BpeTrainer,
        word_to_id: *const hashmap_helper.StringHashMap(u32),
        id_to_word: *const std.ArrayList([]const u8),
    ) !struct { words: []Word, counts: []u64 } {
        _ = id_to_word;

        var words = std.ArrayList(Word){};
        errdefer {
            for (words.items) |*word| word.deinit(self.allocator);
            words.deinit(self.allocator);
        }

        var counts = std.ArrayList(u64){};
        errdefer counts.deinit(self.allocator);

        var it = self.word_counts.iterator();
        while (it.next()) |entry| {
            const word_str = entry.key_ptr.*;
            const count = entry.value_ptr.*;

            var current_word = Word.init();
            errdefer current_word.deinit(self.allocator);

            var utf8_view = std.unicode.Utf8View.init(word_str) catch continue;
            var char_it = utf8_view.iterator();
            var is_first = true;
            var last_char_pos: usize = 0;

            while (char_it.nextCodepoint()) |codepoint| {
                const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
                const char_start = char_it.i - @as(usize, char_len);
                const is_last = (char_it.i >= word_str.len);

                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(codepoint, &buf) catch continue;
                var token_buf: [256]u8 = undefined;
                var token_len: usize = 0;

                // Add continuing_subword_prefix if not first
                if (!is_first and self.continuing_subword_prefix != null) {
                    const prefix = self.continuing_subword_prefix.?;
                    @memcpy(token_buf[token_len..][0..prefix.len], prefix);
                    token_len += prefix.len;
                }

                // Add the character
                @memcpy(token_buf[token_len..][0..len], buf[0..len]);
                token_len += len;

                // Add end_of_word_suffix if last
                if (is_last and self.end_of_word_suffix != null) {
                    const suffix = self.end_of_word_suffix.?;
                    @memcpy(token_buf[token_len..][0..suffix.len], suffix);
                    token_len += suffix.len;
                }

                const token = token_buf[0..token_len];

                // Look up or add to vocab (happens during alphabet computation)
                if (word_to_id.get(token)) |id| {
                    try current_word.add(self.allocator, id, len);
                }

                is_first = false;
                last_char_pos = char_start;
            }

            try words.append(self.allocator, current_word);
            try counts.append(self.allocator, count);
        }

        return .{
            .words = try words.toOwnedSlice(self.allocator),
            .counts = try counts.toOwnedSlice(self.allocator),
        };
    }

    /// Count all pairs in words
    fn countPairs(
        self: *BpeTrainer,
        words: []const Word,
        counts: []const u64,
    ) !struct {
        pair_counts: std.AutoHashMap(u64, i32),
        where_to_update: std.AutoHashMap(u64, std.AutoHashMap(usize, void)),
    } {
        var pair_counts = std.AutoHashMap(u64, i32).init(self.allocator);
        errdefer pair_counts.deinit();

        var where_to_update = std.AutoHashMap(u64, std.AutoHashMap(usize, void)).init(self.allocator);
        errdefer {
            var it = where_to_update.iterator();
            while (it.next()) |entry| entry.value_ptr.deinit();
            where_to_update.deinit();
        }

        for (words, 0..) |word, i| {
            if (word.symbols.items.len < 2) continue;

            for (0..word.symbols.items.len - 1) |j| {
                const pair = Pair{
                    .left = word.symbols.items[j].c,
                    .right = word.symbols.items[j + 1].c,
                };
                const hash = pair.hash();

                // Update pair count
                const gop_count = try pair_counts.getOrPut(hash);
                if (gop_count.found_existing) {
                    gop_count.value_ptr.* += @intCast(counts[i]);
                } else {
                    gop_count.value_ptr.* = @intCast(counts[i]);
                }

                // Track which words contain this pair
                const gop_pos = try where_to_update.getOrPut(hash);
                if (!gop_pos.found_existing) {
                    gop_pos.value_ptr.* = std.AutoHashMap(usize, void).init(self.allocator);
                }
                try gop_pos.value_ptr.put(i, {});
            }
        }

        return .{ .pair_counts = pair_counts, .where_to_update = where_to_update };
    }

    /// Main training function
    pub fn trainFromIterator(self: *BpeTrainer, texts: []const []const u8) !Tokenizer {
        // Count words
        for (texts) |text| {
            const gop = try self.word_counts.getOrPut(text);
            if (gop.found_existing) {
                gop.value_ptr.* += 1;
            } else {
                const owned = try self.allocator.dupe(u8, text);
                gop.key_ptr.* = owned;
                gop.value_ptr.* = 1;
            }
        }

        var word_to_id = hashmap_helper.StringHashMap(u32).init(self.allocator);
        defer word_to_id.deinit();

        var id_to_word = std.ArrayList([]const u8){};
        defer {
            for (id_to_word.items) |word| self.allocator.free(word);
            id_to_word.deinit(self.allocator);
        }

        const max_token_length = self.max_token_length orelse std.math.maxInt(usize);

        // 1. Add special tokens
        try self.addSpecialTokens(&word_to_id, &id_to_word);

        // 2. Compute alphabet
        try self.computeAlphabet(&word_to_id, &id_to_word);

        // 3. Tokenize words
        const tokenized = try self.tokenizeWords(&word_to_id, &id_to_word);
        var words = tokenized.words;
        defer {
            for (words) |*word| word.deinit(self.allocator);
            self.allocator.free(words);
        }
        const word_counts_arr = tokenized.counts;
        defer self.allocator.free(word_counts_arr);

        // 4. Count pairs
        var pair_state = try self.countPairs(words, word_counts_arr);
        defer pair_state.pair_counts.deinit();
        defer {
            var it = pair_state.where_to_update.iterator();
            while (it.next()) |entry| entry.value_ptr.deinit();
            pair_state.where_to_update.deinit();
        }

        // 5. Build priority queue
        var queue = std.PriorityQueue(MergeCandidate, void, MergeCandidate.lessThan).init(self.allocator, {});
        defer queue.deinit();

        var wtu_it = pair_state.where_to_update.iterator();
        while (wtu_it.next()) |entry| {
            const pair_hash = entry.key_ptr.*;
            const count = pair_state.pair_counts.get(pair_hash) orelse continue;
            if (count > 0) {
                const pair = Pair{
                    .left = @intCast(pair_hash >> 32),
                    .right = @intCast(pair_hash & 0xFFFFFFFF),
                };
                try queue.add(MergeCandidate{
                    .pair = pair,
                    .count = @intCast(count),
                });
            }
        }

        // 6. Main merge loop
        var merges = std.ArrayList(MergeResult){};
        defer merges.deinit(self.allocator);

        while (word_to_id.count() < self.vocab_size) {
            const top_opt = queue.removeOrNull();
            if (top_opt == null) break;
            var top = top_opt.?;

            // Check if count is stale
            const current_count = pair_state.pair_counts.get(top.pair.hash()) orelse 0;
            if (top.count != current_count) {
                if (current_count > 0) {
                    top.count = @intCast(current_count);
                    try queue.add(top);
                }
                continue;
            }

            if (current_count < 1 or top.count < self.min_frequency) break;

            // Build new token
            const part_a = id_to_word.items[top.pair.left];
            var part_b = id_to_word.items[top.pair.right];

            // Strip continuing_subword_prefix from part_b if present
            if (self.continuing_subword_prefix) |prefix| {
                if (std.mem.startsWith(u8, part_b, prefix)) {
                    part_b = part_b[prefix.len..];
                }
            }

            const new_token = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ part_a, part_b });

            // Add to vocab
            const new_token_id = word_to_id.get(new_token) orelse blk: {
                const id: u32 = @intCast(id_to_word.items.len);
                try id_to_word.append(self.allocator, new_token);
                try word_to_id.put(new_token, id);
                break :blk id;
            };

            try merges.append(self.allocator, .{ .pair = top.pair, .new_id = new_token_id });

            // Merge in all affected words
            const positions = pair_state.where_to_update.get(top.pair.hash()) orelse continue;

            var pos_it = positions.iterator();
            while (pos_it.next()) |pos_entry| {
                const word_idx = pos_entry.key_ptr.*;
                const changes = try words[word_idx].merge(
                    self.allocator,
                    top.pair.left,
                    top.pair.right,
                    new_token_id,
                    max_token_length,
                );
                defer self.allocator.free(changes);

                // Update pair counts
                for (changes) |change| {
                    const change_hash = change.pair.hash();
                    const gop = try pair_state.pair_counts.getOrPut(change_hash);
                    if (gop.found_existing) {
                        gop.value_ptr.* += change.delta;
                    } else {
                        gop.value_ptr.* = change.delta;
                    }

                    if (change.delta > 0) {
                        const wtu_gop = try pair_state.where_to_update.getOrPut(change_hash);
                        if (!wtu_gop.found_existing) {
                            wtu_gop.value_ptr.* = std.AutoHashMap(usize, void).init(self.allocator);
                        }
                        try wtu_gop.value_ptr.put(word_idx, {});
                    }
                }
            }

            // Add new pairs to queue
            var new_wtu_it = pair_state.where_to_update.iterator();
            while (new_wtu_it.next()) |entry| {
                const pair_hash = entry.key_ptr.*;
                const count = pair_state.pair_counts.get(pair_hash) orelse 0;
                if (count > 0) {
                    const pair = Pair{
                        .left = @intCast(pair_hash >> 32),
                        .right = @intCast(pair_hash & 0xFFFFFFFF),
                    };
                    try queue.add(MergeCandidate{
                        .pair = pair,
                        .count = @intCast(count),
                    });
                }
            }
            pair_state.where_to_update.clearRetainingCapacity();
        }

        // 7. Build Tokenizer from trained vocab and merges
        return try self.buildTokenizer(&word_to_id, &id_to_word, merges.items);
    }

    /// Build a Tokenizer from training results
    fn buildTokenizer(
        self: *BpeTrainer,
        word_to_id: *const hashmap_helper.StringHashMap(u32),
        id_to_word: *const std.ArrayList([]const u8),
        merge_list: []const MergeResult,
    ) !Tokenizer {
        const helpers = @import("tokenizer_helpers.zig");
        const FnvHashContext = @import("fnv_hash.zig").FnvHashContext;

        // Build vocab (HashMap with FNV hash)
        var vocab = std.HashMap(
            []const u8,
            u32,
            FnvHashContext([]const u8),
            std.hash_map.default_max_load_percentage,
        ).init(self.allocator);

        var it = word_to_id.iterator();
        while (it.next()) |entry| {
            const token = try self.allocator.dupe(u8, entry.key_ptr.*);
            try vocab.put(token, entry.value_ptr.*);
        }

        // Build vocab_r (reverse map)
        var vocab_r = std.AutoHashMap(u32, []const u8).init(self.allocator);
        for (id_to_word.items, 0..) |token, i| {
            const owned = try self.allocator.dupe(u8, token);
            try vocab_r.put(@intCast(i), owned);
        }

        // Build merges (ArrayList of Pairs)
        var merges = std.ArrayList(helpers.Pair){};
        for (merge_list) |merge| {
            try merges.append(self.allocator, .{
                .left = merge.pair.left,
                .right = merge.pair.right,
            });
        }

        // Build merges_map (Pair -> rank)
        var merges_map = std.HashMap(
            helpers.Pair,
            u32,
            FnvHashContext(helpers.Pair),
            std.hash_map.default_max_load_percentage,
        ).init(self.allocator);
        for (merge_list, 0..) |merge, i| {
            try merges_map.put(.{
                .left = merge.pair.left,
                .right = merge.pair.right,
            }, @intCast(i));
        }

        // Build split_table
        const builder = @import("tokenizer_builder.zig");
        const split_table = try builder.buildSplitTable(&vocab_r, &vocab, &merges_map, self.allocator);

        // Pattern string (empty for now - training doesn't use it)
        const pattern_str = try self.allocator.dupe(u8, "");

        // TODO: Build Aho-Corasick for fast vocab lookup
        // For now, set to null (encoder will fall back to HashMap)
        const aho_corasick: ?@import("aho_corasick.zig").AhoCorasick = null;

        // TODO: Build next_prefix_match table (requires aho_corasick)
        // For now, allocate empty array
        const next_prefix_match = try self.allocator.alloc(u32, vocab_r.count());
        @memset(next_prefix_match, 0);

        return Tokenizer{
            .vocab = vocab,
            .vocab_r = vocab_r,
            .merges = merges,
            .merges_map = merges_map,
            .split_table = split_table,
            .pattern_str = pattern_str,
            .trie = null, // Don't build trie (uses lots of memory)
            .aho_corasick = aho_corasick,
            .next_prefix_match = next_prefix_match,
            .allocator = self.allocator,
            .encode_arena = std.heap.ArenaAllocator.init(self.allocator),
        };
    }
};
