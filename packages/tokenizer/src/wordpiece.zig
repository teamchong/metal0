/// WordPiece tokenizer - used by BERT, DistilBERT
/// Comptime: Only compiled in if you use Trainer(.WordPiece) or encode with WordPiece
const std = @import("std");
const hashmap_helper = @import("hashmap_helper.zig");
const Allocator = std.mem.Allocator;

/// WordPiece trainer configuration
pub const Config = struct {
    vocab_size: u32 = 30000,
    min_frequency: u32 = 2,
    /// Prefix for subword tokens (default: "##")
    continuing_subword_prefix: []const u8 = "##",
    /// Maximum input token length (tokens longer than this are marked [UNK])
    max_input_chars_per_word: u32 = 100,
};

/// WordPiece vocabulary and model
pub const WordPiece = struct {
    vocab: hashmap_helper.StringHashMap(u32), // token -> id
    vocab_r: std.AutoHashMap(u32, []const u8), // id -> token
    config: Config,
    allocator: Allocator,
    unk_token: []const u8 = "[UNK]",
    unk_token_id: u32 = 1,

    pub fn init(allocator: Allocator, config: Config) WordPiece {
        return WordPiece{
            .vocab = hashmap_helper.StringHashMap(u32).init(allocator),
            .vocab_r = std.AutoHashMap(u32, []const u8).init(allocator),
            .config = config,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *WordPiece) void {
        var it = self.vocab.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.vocab.deinit();
        self.vocab_r.deinit();
    }

    /// Train WordPiece from corpus
    /// Algorithm:
    /// 1. Start with character vocabulary
    /// 2. Iteratively merge most frequent adjacent pairs
    /// 3. Add ## prefix for subword continuations
    pub fn train(self: *WordPiece, texts: []const []const u8) !void {
        // Build initial character vocabulary
        try self.initVocabulary(texts);

        // Count word frequencies
        var word_counts = hashmap_helper.StringHashMap(u32).init(self.allocator);
        defer {
            var it = word_counts.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            word_counts.deinit();
        }

        for (texts) |text| {
            var words = std.mem.tokenizeAny(u8, text, " \t\n\r");
            while (words.next()) |word| {
                if (word.len == 0 or word.len > self.config.max_input_chars_per_word) continue;

                const gop = try word_counts.getOrPut(word);
                if (gop.found_existing) {
                    gop.value_ptr.* += 1;
                } else {
                    gop.key_ptr.* = try self.allocator.dupe(u8, word);
                    gop.value_ptr.* = 1;
                }
            }
        }

        // Iteratively merge most frequent pairs until vocab_size reached
        var current_vocab_size: u32 = @intCast(self.vocab.count());
        while (current_vocab_size < self.config.vocab_size) {
            if (try self.findBestPair(&word_counts)) |best_pair| {
                defer self.allocator.free(best_pair);
                try self.addToken(best_pair);
                current_vocab_size += 1;
            } else {
                break;
            }
        }
    }

    /// Initialize vocabulary with special tokens + characters
    fn initVocabulary(self: *WordPiece, texts: []const []const u8) !void {
        // Add special tokens
        try self.addSpecialToken("[PAD]", 0);
        try self.addSpecialToken("[UNK]", 1);
        try self.addSpecialToken("[CLS]", 2);
        try self.addSpecialToken("[SEP]", 3);
        try self.addSpecialToken("[MASK]", 4);

        self.unk_token_id = 1;

        // Collect all unique characters
        var char_set = std.AutoHashMap(u8, void).init(self.allocator);
        defer char_set.deinit();

        for (texts) |text| {
            for (text) |c| {
                try char_set.put(c, {});
            }
        }

        // Add characters to vocab
        var id: u32 = 5; // Start after special tokens
        var it = char_set.keyIterator();
        while (it.next()) |char_ptr| {
            const char_str = try self.allocator.alloc(u8, 1);
            char_str[0] = char_ptr.*;
            try self.vocab.put(char_str, id);
            try self.vocab_r.put(id, char_str);
            id += 1;
        }
    }

    fn addSpecialToken(self: *WordPiece, token: []const u8, id: u32) !void {
        const owned = try self.allocator.dupe(u8, token);
        try self.vocab.put(owned, id);
        try self.vocab_r.put(id, owned);
    }

    fn addToken(self: *WordPiece, token: []const u8) !void {
        const id: u32 = @intCast(self.vocab.count());
        const owned = try self.allocator.dupe(u8, token);

        // Check if key already exists and free old one
        const gop = try self.vocab.getOrPut(owned);
        if (gop.found_existing) {
            // Free the new allocation since we don't need it
            self.allocator.free(owned);
            // Don't add to vocab_r since it's already there
        } else {
            // New key - set value and add to reverse map
            gop.value_ptr.* = id;
            try self.vocab_r.put(id, gop.key_ptr.*);
        }
    }

    /// Find most frequent adjacent TOKEN pair in words
    /// CRITICAL: This must tokenize with current vocab, not just look at characters!
    fn findBestPair(self: *WordPiece, word_counts: *hashmap_helper.StringHashMap(u32)) !?[]const u8 {
        var pair_counts = hashmap_helper.StringHashMap(u32).init(self.allocator);
        defer {
            var it = pair_counts.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            pair_counts.deinit();
        }

        // Count all adjacent TOKEN pairs (not character pairs!)
        var word_it = word_counts.iterator();
        while (word_it.next()) |word_entry| {
            const word = word_entry.key_ptr.*;
            const count = word_entry.value_ptr.*;

            // Tokenize word with CURRENT vocabulary
            const tokens = try self.tokenizeWord(word);
            defer self.allocator.free(tokens);

            // Count adjacent token pairs
            if (tokens.len < 2) continue;

            for (0..tokens.len - 1) |i| {
                const left = tokens[i];
                const right = tokens[i + 1];

                // Create concatenated pair
                const pair = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ left, right });

                const gop = try pair_counts.getOrPut(pair);
                if (gop.found_existing) {
                    self.allocator.free(pair);
                    gop.value_ptr.* += count;
                } else {
                    gop.value_ptr.* = count;
                }
            }
        }

        // Find best pair (highest count, meeting min_frequency)
        var best_pair: ?[]const u8 = null;
        var best_count: u32 = self.config.min_frequency - 1;

        var pair_it = pair_counts.iterator();
        while (pair_it.next()) |entry| {
            if (entry.value_ptr.* > best_count) {
                best_count = entry.value_ptr.*;
                if (best_pair) |old| self.allocator.free(old);
                best_pair = try self.allocator.dupe(u8, entry.key_ptr.*);
            }
        }

        return best_pair;
    }

    /// Tokenize a single word using greedy longest-match
    fn tokenizeWord(self: *WordPiece, word: []const u8) ![][]const u8 {
        var result = std.ArrayList([]const u8){};
        errdefer result.deinit(self.allocator);

        if (word.len > self.config.max_input_chars_per_word) {
            try result.append(self.allocator, self.unk_token);
            return result.toOwnedSlice(self.allocator);
        }

        var start: usize = 0;
        var is_first = true;

        while (start < word.len) {
            var end = word.len;
            var found = false;

            // Greedy longest match
            while (end > start) {
                const substr = word[start..end];

                // Try without ## prefix for first subword
                if (is_first) {
                    if (self.vocab.contains(substr)) {
                        const vocab_key = self.vocab.getKey(substr).?;
                        try result.append(self.allocator, vocab_key);
                        found = true;
                        break;
                    }
                } else {
                    // Try with ## prefix first for continuation subwords
                    const prefixed = try std.fmt.allocPrint(
                        self.allocator,
                        "{s}{s}",
                        .{self.config.continuing_subword_prefix, substr}
                    );
                    defer self.allocator.free(prefixed);

                    if (self.vocab.contains(prefixed)) {
                        const vocab_key = self.vocab.getKey(prefixed).?;
                        try result.append(self.allocator, vocab_key);
                        found = true;
                        break;
                    }

                    // Also try without prefix (for single chars)
                    if (self.vocab.contains(substr)) {
                        const vocab_key = self.vocab.getKey(substr).?;
                        try result.append(self.allocator, vocab_key);
                        found = true;
                        break;
                    }
                }

                end -= 1;
            }

            if (!found) {
                // Can't tokenize this word - return [UNK] for whole word
                result.deinit(self.allocator);
                var unk_result = std.ArrayList([]const u8){};
                try unk_result.append(self.allocator, self.unk_token);
                return unk_result.toOwnedSlice(self.allocator);
            }

            start = end;
            is_first = false;
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Encode text to token IDs
    pub fn encode(self: *WordPiece, text: []const u8) ![]u32 {
        var result = std.ArrayList(u32){};
        errdefer result.deinit(self.allocator);

        var words = std.mem.tokenizeAny(u8, text, " \t\n\r");
        while (words.next()) |word| {
            const tokens = try self.tokenizeWord(word);
            defer self.allocator.free(tokens);

            for (tokens) |token| {
                const id = self.vocab.get(token) orelse self.unk_token_id;
                try result.append(self.allocator, id);
            }
        }

        return result.toOwnedSlice(self.allocator);
    }

    /// Decode token IDs to text
    pub fn decode(self: *WordPiece, ids: []const u32) ![]u8 {
        var result = std.ArrayList(u8){};
        errdefer result.deinit(self.allocator);

        for (ids) |id| {
            const token = self.vocab_r.get(id) orelse self.unk_token;

            // Skip special tokens in output
            if (std.mem.startsWith(u8, token, "[")) {
                continue;
            }

            // If token starts with ##, it's a continuation - just append without prefix
            if (std.mem.startsWith(u8, token, self.config.continuing_subword_prefix)) {
                try result.appendSlice(self.allocator, token[self.config.continuing_subword_prefix.len..]);
            } else {
                // Regular token - just append as-is (no space added within word)
                try result.appendSlice(self.allocator, token);
            }
        }

        return result.toOwnedSlice(self.allocator);
    }
};

test "WordPiece basic init" {
    const allocator = std.testing.allocator;

    var wp = WordPiece.init(allocator, .{});
    defer wp.deinit();

    try std.testing.expect(wp.vocab.count() == 0);
}

test "WordPiece train small corpus" {
    const allocator = std.testing.allocator;

    var wp = WordPiece.init(allocator, .{ .vocab_size = 50 });
    defer wp.deinit();

    const texts = [_][]const u8{
        "hello world",
        "hello there",
    };

    try wp.train(&texts);

    // Should have special tokens (5) + characters from corpus + some merges
    try std.testing.expect(wp.vocab.count() >= 5);
}

test "WordPiece encode/decode" {
    const allocator = std.testing.allocator;

    var wp = WordPiece.init(allocator, .{ .vocab_size = 100, .min_frequency = 1 });
    defer wp.deinit();

    // Larger corpus with repeated words to learn subwords
    const texts = [_][]const u8{
        "hello hello hello",
        "world world world",
        "hello world",
    };

    try wp.train(&texts);

    // Should be able to encode and decode "hello"
    const ids = try wp.encode("hello");
    defer allocator.free(ids);

    // Just verify we got some tokens (not empty)
    try std.testing.expect(ids.len > 0);

    // And verify it doesn't produce [UNK]
    for (ids) |id| {
        try std.testing.expect(id != wp.unk_token_id);
    }

    const decoded = try wp.decode(ids);
    defer allocator.free(decoded);

    try std.testing.expectEqualStrings("hello", decoded);
}
