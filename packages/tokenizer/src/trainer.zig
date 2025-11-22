/// BPE Training - Learn merges from corpus
/// Parallel processing with SIMD optimization
/// Matches rustbpe training API for nanochat compatibility

const std = @import("std");
const Allocator = std.mem.Allocator;
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const Pair = @import("tokenizer.zig").Pair;
const PairContext = @import("tokenizer.zig").PairContext;
const countPairsSIMD = @import("tokenizer.zig").countPairsSIMD;

/// Word with its frequency count
const Word = struct {
    ids: []u32,
    count: i32,
    original_allocation: []u32, // Track original allocation for proper freeing

    fn deinit(self: *Word, allocator: Allocator) void {
        allocator.free(self.original_allocation);
    }
};

/// Parallel chunk for multi-threaded processing
const ChunkResult = struct {
    pair_counts: std.HashMap(Pair, i32, PairContext, std.hash_map.default_max_load_percentage),
    allocator: Allocator,

    fn deinit(self: *ChunkResult) void {
        self.pair_counts.deinit();
    }
};

/// Merge candidate for priority queue (Phase 1 optimization)
const MergeCandidate = struct {
    pair: Pair,
    frequency: i32,

    /// Compare for max-heap (higher frequency = higher priority)
    fn compare(context: void, a: MergeCandidate, b: MergeCandidate) std.math.Order {
        _ = context;
        // Reverse order for max-heap (std.PriorityQueue is min-heap by default)
        return std.math.order(b.frequency, a.frequency);
    }
};

/// Position tracker for incremental updates (Phase 1.5)
/// Tracks which word indices contain each pair
const PairPositions = struct {
    allocator: Allocator,
    map: std.HashMap(Pair, std.ArrayList(usize), PairContext, std.hash_map.default_max_load_percentage),

    fn init(allocator: Allocator) PairPositions {
        return .{
            .allocator = allocator,
            .map = std.HashMap(
                Pair,
                std.ArrayList(usize),
                PairContext,
                std.hash_map.default_max_load_percentage,
            ).initContext(allocator, PairContext{}),
        };
    }

    fn deinit(self: *PairPositions) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.map.deinit();
    }

    /// Add a word index to a pair's position list
    fn addPosition(self: *PairPositions, pair: Pair, word_idx: usize) !void {
        const gop = try self.map.getOrPut(pair);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList(usize){};
        }
        try gop.value_ptr.append(self.allocator, word_idx);
    }

    /// Remove a word index from a pair's position list
    fn removePosition(self: *PairPositions, pair: Pair, word_idx: usize) void {
        if (self.map.getPtr(pair)) |positions| {
            for (positions.items, 0..) |idx, i| {
                if (idx == word_idx) {
                    _ = positions.swapRemove(i);
                    break;
                }
            }
        }
    }

    /// Get positions for a pair
    fn getPositions(self: *PairPositions, pair: Pair) ?[]const usize {
        if (self.map.get(pair)) |positions| {
            return positions.items;
        }
        return null;
    }
};

/// Count all pairs in words (parallel with SIMD)
fn countPairsParallel(
    words: []const Word,
    allocator: Allocator,
) !std.HashMap(Pair, i32, PairContext, std.hash_map.default_max_load_percentage) {
    // FORCE single-threaded for profiling
    return countPairsSingleThreaded(words, allocator);
}

fn countPairsParallelOLD(
    words: []const Word,
    allocator: Allocator,
) !std.HashMap(Pair, i32, PairContext, std.hash_map.default_max_load_percentage) {
    const cpu_count = try std.Thread.getCpuCount();
    const num_threads = @min(cpu_count, words.len);

    if (num_threads == 1) {
        return countPairsSingleThreaded(words, allocator);
    }

    const chunk_size = words.len / num_threads;
    const threads = try allocator.alloc(std.Thread, num_threads);
    defer allocator.free(threads);

    var results = try allocator.alloc(ChunkResult, num_threads);
    defer {
        for (results) |*result| result.deinit();
        allocator.free(results);
    }

    // Spawn threads
    for (threads, 0..) |*thread, i| {
        const start = i * chunk_size;
        const end = if (i == num_threads - 1) words.len else start + chunk_size;

        results[i] = ChunkResult{
            .pair_counts = std.HashMap(
                Pair,
                i32,
                PairContext,
                std.hash_map.default_max_load_percentage,
            ).initContext(allocator, PairContext{}),
            .allocator = allocator,
        };

        thread.* = try std.Thread.spawn(.{}, countPairsChunk, .{
            words[start..end],
            &results[i].pair_counts,
        });
    }

    // Wait for all threads
    for (threads) |thread| thread.join();

    // Merge results (single-threaded)
    var merged = std.HashMap(
        Pair,
        i32,
        PairContext,
        std.hash_map.default_max_load_percentage,
    ).initContext(allocator, PairContext{});

    for (results) |*result| {
        var it = result.pair_counts.iterator();
        while (it.next()) |entry| {
            const gop = try merged.getOrPut(entry.key_ptr.*);
            if (gop.found_existing) {
                gop.value_ptr.* += entry.value_ptr.*;
            } else {
                gop.value_ptr.* = entry.value_ptr.*;
            }
        }
    }

    return merged;
}

/// Count pairs in a chunk (SIMPLE like Rust - just iterate!)
fn countPairsChunk(
    words: []const Word,
    pair_counts: *std.HashMap(Pair, i32, PairContext, std.hash_map.default_max_load_percentage),
) void {
    for (words) |word| {
        if (word.ids.len < 2 or word.count == 0) continue;

        // Simple iteration like Rust - no SIMD, no "seen" HashMap!
        var i: usize = 0;
        while (i < word.ids.len - 1) : (i += 1) {
            const pair = Pair{ .left = word.ids[i], .right = word.ids[i + 1] };

            // Add word.count to this pair's frequency
            const gop = pair_counts.getOrPut(pair) catch continue;
            if (gop.found_existing) {
                gop.value_ptr.* += word.count;
            } else {
                gop.value_ptr.* = word.count;
            }
        }
    }
}

/// Single-threaded pair counting (fallback)
fn countPairsSingleThreaded(
    words: []const Word,
    allocator: Allocator,
) !std.HashMap(Pair, i32, PairContext, std.hash_map.default_max_load_percentage) {
    var pair_counts = std.HashMap(
        Pair,
        i32,
        PairContext,
        std.hash_map.default_max_load_percentage,
    ).initContext(allocator, PairContext{});

    countPairsChunk(words, &pair_counts);
    return pair_counts;
}

/// Apply merge in-place (Phase 1: avoid ArrayList recreation)
/// Returns true if any merge was applied
fn mergePairInPlace(word: *Word, pair: Pair, new_id: u32) bool {
    if (word.ids.len < 2) return false;

    var write_pos: usize = 0;
    var read_pos: usize = 0;
    var changed = false;

    while (read_pos < word.ids.len) {
        // Prefetch ahead for better cache utilization
        if (read_pos + 16 < word.ids.len) {
            @prefetch(&word.ids[read_pos + 16], .{ .rw = .read, .locality = 3 });
        }

        // Check if we can merge at current position
        if (read_pos + 1 < word.ids.len and
            word.ids[read_pos] == pair.left and
            word.ids[read_pos + 1] == pair.right)
        {
            // Merge: write new_id and skip both tokens
            word.ids[write_pos] = new_id;
            write_pos += 1;
            read_pos += 2;
            changed = true;
        } else {
            // No merge: copy token
            if (write_pos != read_pos) {
                word.ids[write_pos] = word.ids[read_pos];
            }
            write_pos += 1;
            read_pos += 1;
        }
    }

    // Truncate to new length (no reallocation!)
    word.ids = word.ids[0..write_pos];
    return changed;
}

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

        return Tokenizer{
            .vocab = vocab,
            .vocab_r = vocab_r,
            .merges = merges,
            .merges_map = merges_map,
            .split_table = split_table,
            .pattern_str = pattern_str,
            .trie = trie,
            .aho_corasick = null, // Not needed for trainer
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
