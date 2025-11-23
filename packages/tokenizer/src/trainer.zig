/// BPE Training - Learn merges from corpus
/// Parallel processing with SIMD optimization
/// Matches rustbpe training API for nanochat compatibility

const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Pair = @import("tokenizer.zig").Pair;
const PairContext = @import("tokenizer.zig").PairContext;
const StringHashContext = @import("tokenizer.zig").StringHashContext;
const countPairsSIMD = @import("tokenizer.zig").countPairsSIMD;

// Import helper structures and functions from trainer_stats.zig
const trainer_stats = @import("trainer_stats.zig");
const Word = trainer_stats.Word;
const countPairsParallel = trainer_stats.countPairsParallel;
const mergePairInPlace = trainer_stats.mergePairInPlace;

/// BPE Trainer - matches rustbpe API
pub const Trainer = struct {
    vocab_size: u32,
    pattern_str: []const u8,
    allocator: Allocator,

    pub fn init(vocab_size: u32, allocator: Allocator) !Trainer {
        if (vocab_size < 256) return error.VocabSizeTooSmall;

        const pattern_str = try allocator.dupe(u8,
            "'s|'t|'re|'ve|'m|'ll|'d| ?[[:alpha:]]+| ?[[:digit:]]+| ?[^[:alnum:][:space:]]+| +[[:space:]]*| +"
        );

        return Trainer{
            .vocab_size = vocab_size,
            .pattern_str = pattern_str,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Trainer) void {
        self.allocator.free(self.pattern_str);
    }

    /// Train from text iterator (parallel processing)
    /// Compatible with rustbpe's train_from_iterator
    pub fn trainFromIterator(
        self: *Trainer,
        texts: []const []const u8,
    ) !Tokenizer {
        std.debug.print("Starting BPE training: {} merges to compute\n", .{self.vocab_size - 256});

        // Step 1: Collect word frequencies (parallel)
        const start_collect = std.time.nanoTimestamp();
        std.debug.print("Processing {} texts...\n", .{texts.len});
        var word_counts = try self.collectWordCounts(texts);
        const collect_ms = @divFloor(std.time.nanoTimestamp() - start_collect, 1_000_000);
        std.debug.print("  → Word collection: {}ms\n", .{collect_ms});
        defer {
            var it = word_counts.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
            }
            word_counts.deinit();
        }

        std.debug.print("Found {} unique words\n", .{word_counts.count()});

        // Step 2: Convert to Word structs
        var words = try std.ArrayList(Word).initCapacity(self.allocator, word_counts.count());
        defer {
            for (words.items) |*word| word.deinit(self.allocator);
            words.deinit(self.allocator);
        }

        var wc_it = word_counts.iterator();
        while (wc_it.next()) |entry| {
            const ids = try self.allocator.alloc(u32, entry.key_ptr.*.len);
            for (entry.key_ptr.*, 0..) |byte, i| {
                ids[i] = byte;
            }

            try words.append(self.allocator, Word{
                .ids = ids,
                .count = entry.value_ptr.*,
                .original_allocation = ids, // Keep reference to original allocation
            });
        }

        // Step 3: Learn merges (SIMPLE like Rust - no fancy optimizations!)
        var merges = std.ArrayList(Pair){};

        const num_merges = self.vocab_size - 256;

        std.debug.print("Starting SIMPLE merge loop (like Rust)...\n", .{});

        const start_merges = std.time.nanoTimestamp();
        var total_count_time: i128 = 0;
        var total_apply_time: i128 = 0;

        // Main merge loop: Simple and fast like Rust!
        var merges_done: u32 = 0;
        while (merges_done < num_merges) {
            // Count all pairs (fresh every iteration - simple!)
            const count_start = std.time.nanoTimestamp();
            var pair_counts = try countPairsParallel(words.items, self.allocator);
            defer pair_counts.deinit();
            total_count_time += std.time.nanoTimestamp() - count_start;

            // Find best pair (max frequency)
            var best_pair: ?Pair = null;
            var best_freq: i32 = 0;

            var it = pair_counts.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.* > best_freq) {
                    best_freq = entry.value_ptr.*;
                    best_pair = entry.key_ptr.*;
                }
            }

            if (best_pair == null or best_freq == 0) break;

            const pair = best_pair.?;
            try merges.append(self.allocator, pair);
            const new_id = 256 + merges_done;

            // Apply merge to all words (in-place, simple!)
            const apply_start = std.time.nanoTimestamp();
            for (words.items) |*word| {
                _ = mergePairInPlace(word, pair, new_id);
            }
            total_apply_time += std.time.nanoTimestamp() - apply_start;

            merges_done += 1;

            // Progress logging (every 1%)
            if (merges_done % @max(1, num_merges / 100) == 0 or merges_done == num_merges) {
                const percent = (merges_done * 100) / num_merges;
                std.debug.print("Progress: {}% ({}/{} merges) - Last: ({}, {}) -> {} (freq: {})\n", .{
                    percent,
                    merges_done,
                    num_merges,
                    pair.left,
                    pair.right,
                    new_id,
                    best_freq,
                });
            }
        }

        const total_merge_ms = @divFloor(std.time.nanoTimestamp() - start_merges, 1_000_000);
        const count_ms = @divFloor(total_count_time, 1_000_000);
        const apply_ms = @divFloor(total_apply_time, 1_000_000);

        std.debug.print("Finished training: {} merges completed\n", .{merges_done});
        std.debug.print("  → Total merge time: {}ms\n", .{total_merge_ms});
        std.debug.print("    - Pair counting: {}ms ({d:.1}%)\n", .{ count_ms, @as(f64, @floatFromInt(count_ms)) * 100.0 / @as(f64, @floatFromInt(total_merge_ms)) });
        std.debug.print("    - Applying merges: {}ms ({d:.1}%)\n", .{ apply_ms, @as(f64, @floatFromInt(apply_ms)) * 100.0 / @as(f64, @floatFromInt(total_merge_ms)) });

        // Step 4: Build tokenizer (transfers ownership of merges)
        const tokenizer = try self.buildTokenizer(merges);

        // Don't free merges - ownership transferred to tokenizer
        // merges.deinit() would double-free!

        return tokenizer;
    }

    /// Collect word counts from texts (FAST - minimal allocations!)
    fn collectWordCounts(
        self: *Trainer,
        texts: []const []const u8,
    ) !std.StringHashMap(i32) {
        var word_counts = std.StringHashMap(i32).init(self.allocator);

        // Simple whitespace splitting - but FAST!
        for (texts) |text| {
            var it = std.mem.splitScalar(u8, text, ' ');
            while (it.next()) |word| {
                if (word.len == 0) continue;

                // Try to get existing entry first (most common case after first pass)
                const gop = try word_counts.getOrPut(word);

                if (gop.found_existing) {
                    // Word exists - just increment count (NO allocation!)
                    gop.value_ptr.* += 1;
                } else {
                    // New word - allocate ONCE
                    const word_copy = try self.allocator.dupe(u8, word);
                    // Update the key to point to our copy
                    gop.key_ptr.* = word_copy;
                    gop.value_ptr.* = 1;
                }
            }
        }

        return word_counts;
    }

    /// Build tokenizer from learned merges
    fn buildTokenizer(self: *Trainer, merges: std.ArrayList(Pair)) !Tokenizer {
        var vocab = std.StringHashMap(u32).init(self.allocator);
        var vocab_r = std.AutoHashMap(u32, []const u8).init(self.allocator);
        var merges_map = std.HashMap(
            Pair,
            u32,
            PairContext,
            std.hash_map.default_max_load_percentage,
        ).initContext(self.allocator, PairContext{});

        // Add base vocabulary (256 bytes)
        var i: u32 = 0;
        while (i < 256) : (i += 1) {
            const key = try self.allocator.alloc(u8, 1);
            key[0] = @intCast(i);
            try vocab.put(key, i);
            try vocab_r.put(i, key);
        }

        // Add merged tokens - reconstruct string for each merge
        for (merges.items, 0..) |pair, idx| {
            try merges_map.put(pair, @intCast(idx));

            // Reconstruct the merged token string by looking up left + right
            const left_str = vocab_r.get(pair.left) orelse return error.InvalidMerge;
            const right_str = vocab_r.get(pair.right) orelse return error.InvalidMerge;

            // Concatenate left + right
            const merged_str = try self.allocator.alloc(u8, left_str.len + right_str.len);
            @memcpy(merged_str[0..left_str.len], left_str);
            @memcpy(merged_str[left_str.len..], right_str);

            // Add to vocab_r with new token ID
            const token_id: u32 = 256 + @as(u32, @intCast(idx));
            try vocab_r.put(token_id, merged_str);
        }

        const pattern_str = try self.allocator.dupe(u8, self.pattern_str);

        // Create empty trie (not used for merge-based tokenizers)
        const TrieNode = @import("tokenizer.zig").TrieNode;
        const trie = try TrieNode.init(self.allocator);

        const split_table = std.AutoHashMap(u32, @import("tokenizer.zig").Pair).init(self.allocator);

        const next_prefix_match = try self.allocator.alloc(u32, 0); // Empty for trainer

        return Tokenizer{
            .vocab = vocab,
            .vocab_r = vocab_r,
            .merges = merges,
            .merges_map = merges_map,
            .split_table = split_table,
            .pattern_str = pattern_str,
            .trie = trie,
            .aho_corasick = null, // Not needed for trainer
            .next_prefix_match = next_prefix_match,
            .allocator = self.allocator,
        };
    }
};

test "basic training" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var trainer = try Trainer.init(300, allocator); // 256 + 44 merges
    defer trainer.deinit();

    const texts = [_][]const u8{
        "hello world",
        "hello there",
        "world peace",
    };

    var tokenizer = try trainer.trainFromIterator(&texts);
    defer tokenizer.deinit();

    // Should have learned merges
    try std.testing.expect(tokenizer.merges.items.len > 0);
}
