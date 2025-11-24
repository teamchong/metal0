/// WordPiece Trainer - BERT-style tokenization training
/// Ported from HuggingFace tokenizers WordPiece implementation

const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const WordPiece = @import("wordpiece.zig").WordPiece;

/// WordPiece Trainer (compatible with comptime trainer interface)
pub const WordPieceTrainer = struct {
    vocab_size: usize,
    allocator: Allocator,
    continuing_subword_prefix: []const u8,
    special_tokens: []const []const u8,

    pub fn init(vocab_size: usize, allocator: Allocator) !WordPieceTrainer {
        return WordPieceTrainer{
            .vocab_size = vocab_size,
            .allocator = allocator,
            .continuing_subword_prefix = "##",
            .special_tokens = &[_][]const u8{},
        };
    }

    pub fn deinit(self: *WordPieceTrainer) void {
        _ = self;
        // No cleanup needed in this simple wrapper
    }

    /// Train WordPiece tokenizer from texts
    pub fn trainFromIterator(self: *WordPieceTrainer, texts: []const []const u8) !Tokenizer {
        const wp_mod = @import("wordpiece.zig");
        const config = wp_mod.Config{
            .vocab_size = @intCast(self.vocab_size),
            .min_frequency = 2,
            .continuing_subword_prefix = self.continuing_subword_prefix,
        };

        var wordpiece = WordPiece.init(self.allocator, config);
        defer wordpiece.deinit();

        // Train on texts
        try wordpiece.train(texts);

        // Build Tokenizer from WordPiece model
        return try self.buildTokenizer(&wordpiece);
    }

    /// Build a Tokenizer from trained WordPiece model
    fn buildTokenizer(self: *WordPieceTrainer, wordpiece: *const WordPiece) !Tokenizer {
        const helpers = @import("tokenizer_helpers.zig");
        const FnvHashContext = @import("fnv_hash.zig").FnvHashContext;

        // Build vocab (HashMap with FNV hash)
        var vocab = std.HashMap(
            []const u8,
            u32,
            FnvHashContext([]const u8),
            std.hash_map.default_max_load_percentage,
        ).init(self.allocator);

        var it = wordpiece.vocab.iterator();
        while (it.next()) |entry| {
            const token = try self.allocator.dupe(u8, entry.key_ptr.*);
            try vocab.put(token, entry.value_ptr.*);
        }

        // Build vocab_r (reverse map)
        var vocab_r = std.AutoHashMap(u32, []const u8).init(self.allocator);
        var it_r = wordpiece.vocab_r.iterator();
        while (it_r.next()) |entry| {
            const token = try self.allocator.dupe(u8, entry.value_ptr.*);
            try vocab_r.put(entry.key_ptr.*, token);
        }

        // Empty merges/merges_map (WordPiece doesn't use merges)
        const merges = std.ArrayList(helpers.Pair){};
        const merges_map = std.HashMap(
            helpers.Pair,
            u32,
            FnvHashContext(helpers.Pair),
            std.hash_map.default_max_load_percentage,
        ).init(self.allocator);

        // Empty split_table
        const split_table = try self.allocator.alloc(helpers.Pair, 0);

        // Pattern string
        const pattern_str = try self.allocator.dupe(u8, "");

        // No Aho-Corasick for now
        const aho_corasick = null;

        // Empty next_prefix_match
        const next_prefix_match = try self.allocator.alloc(u32, vocab_r.count());
        @memset(next_prefix_match, 0);

        return Tokenizer{
            .vocab = vocab,
            .vocab_r = vocab_r,
            .merges = merges,
            .merges_map = merges_map,
            .split_table = split_table,
            .pattern_str = pattern_str,
            .trie = null,
            .aho_corasick = aho_corasick,
            .next_prefix_match = next_prefix_match,
            .allocator = self.allocator,
            .encode_arena = std.heap.ArenaAllocator.init(self.allocator),
        };
    }
};
