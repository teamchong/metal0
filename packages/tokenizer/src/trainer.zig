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
    const cpu_count = try std.Thread.getCpuCount();
    const num_threads = @min(cpu_count, words.len);

    if (num_threads == 1) {
        // Single-threaded fallback
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

/// Count pairs in a chunk (called by worker thread)
fn countPairsChunk(
    words: []const Word,
    pair_counts: *std.HashMap(Pair, i32, PairContext, std.hash_map.default_max_load_percentage),
) void {
    for (words) |word| {
        if (word.ids.len < 2) continue;

        // Use SIMD to count each unique pair
        var seen = std.AutoHashMap(Pair, void).init(pair_counts.allocator);
        defer seen.deinit();

        var i: usize = 0;
        while (i < word.ids.len - 1) : (i += 1) {
            const pair = Pair{ .left = word.ids[i], .right = word.ids[i + 1] };

            // Only count each unique pair once per word
            const gop = seen.getOrPut(pair) catch continue;
            if (gop.found_existing) continue;

            const count = countPairsSIMD(word.ids, pair);
            const weighted_count = count * @as(u32, @intCast(word.count));

            const pair_gop = pair_counts.getOrPut(pair) catch continue;
            if (pair_gop.found_existing) {
                pair_gop.value_ptr.* += @intCast(weighted_count);
            } else {
                pair_gop.value_ptr.* = @intCast(weighted_count);
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
        std.debug.print("Processing {} texts...\n", .{texts.len});
        var word_counts = try self.collectWordCounts(texts);
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

        // Step 3: Learn merges (Phase 1 OPTIMIZED: PriorityQueue with smart rebuild)
        var merges = std.ArrayList(Pair){};

        const num_merges = self.vocab_size - 256;

        std.debug.print("Starting OPTIMIZED merge loop (Phase 1: PriorityQueue + in-place)...\n", .{});

        // Initial pair count (one-time cost)
        var pair_counts = try countPairsParallel(words.items, self.allocator);
        defer pair_counts.deinit();

        // Build priority queue from initial counts: O(n log n)
        var heap = std.PriorityQueue(MergeCandidate, void, MergeCandidate.compare).init(self.allocator, {});
        defer heap.deinit();

        var count_it = pair_counts.iterator();
        while (count_it.next()) |entry| {
            try heap.add(.{
                .pair = entry.key_ptr.*,
                .frequency = entry.value_ptr.*,
            });
        }

        std.debug.print("Built priority queue with {} unique pairs\n", .{heap.count()});

        // Main merge loop: O(m × k log n) where k = affected words per merge
        var merges_done: u32 = 0;
        while (merges_done < num_merges and heap.count() > 0) {
            const best = heap.remove(); // O(log n)
            if (best.frequency == 0) break;

            try merges.append(self.allocator, best.pair);
            const new_id = 256 + merges_done;

            // Track new pair frequencies after this merge
            var new_frequencies = std.HashMap(
                Pair,
                i32,
                PairContext,
                std.hash_map.default_max_load_percentage,
            ).initContext(self.allocator, PairContext{});
            defer new_frequencies.deinit();

            // Apply merge in-place to ALL words, collecting new frequencies
            // This is still better than naive O(n²) because:
            // 1. In-place merge (no ArrayList recreation)
            // 2. Only recalculate pairs in words that changed
            // 3. Priority queue avoids scanning all pairs
            for (words.items, 0..) |*word, word_i| {
                // Prefetch next word for better cache utilization
                if (word_i + 1 < words.items.len) {
                    @prefetch(&words.items[word_i + 1], .{ .rw = .read, .locality = 2 });
                }

                if (!mergePairInPlace(word, best.pair, new_id)) continue;

                // Recalculate pairs ONLY in this modified word
                if (word.ids.len < 2) continue;

                var i: usize = 0;
                while (i < word.ids.len - 1) : (i += 1) {
                    const pair = Pair{ .left = word.ids[i], .right = word.ids[i + 1] };

                    // Count with SIMD
                    const count = countPairsSIMD(word.ids, pair);
                    const weighted = count * @as(u32, @intCast(word.count));

                    const gop = try new_frequencies.getOrPut(pair);
                    if (gop.found_existing) {
                        gop.value_ptr.* += @intCast(weighted);
                    } else {
                        gop.value_ptr.* = @intCast(weighted);
                    }
                }
            }

            // Smart rebuild: Instead of full rebuild, add only new/affected pairs
            // Remove pairs involving merged tokens from heap, add updated frequencies
            var temp_heap = std.PriorityQueue(MergeCandidate, void, MergeCandidate.compare).init(self.allocator, {});

            // Add new frequencies
            var new_it = new_frequencies.iterator();
            while (new_it.next()) |entry| {
                if (entry.value_ptr.* > 0) {
                    try temp_heap.add(.{
                        .pair = entry.key_ptr.*,
                        .frequency = entry.value_ptr.*,
                    });
                }
            }

            // Filter old heap: keep pairs that weren't affected by this merge
            while (heap.removeOrNull()) |candidate| {
                // Skip the merged pair and any pair involving the merged tokens
                if (candidate.pair.eql(best.pair) or
                    candidate.pair.left == best.pair.left or
                    candidate.pair.left == best.pair.right or
                    candidate.pair.right == best.pair.left or
                    candidate.pair.right == best.pair.right)
                {
                    continue;
                }

                // Keep if not in new frequencies (unaffected by merge)
                if (!new_frequencies.contains(candidate.pair)) {
                    try temp_heap.add(candidate);
                }
            }

            heap.deinit();
            heap = temp_heap;

            merges_done += 1;

            // Progress logging
            if (merges_done % @max(1, num_merges / 100) == 0 or merges_done == num_merges) {
                const percent = (merges_done * 100) / num_merges;
                std.debug.print("Progress: {}% ({}/{} merges) - Last: ({}, {}) -> {} (freq: {}, heap: {})\n", .{
                    percent,
                    merges_done,
                    num_merges,
                    best.pair.left,
                    best.pair.right,
                    new_id,
                    best.frequency,
                    heap.count(),
                });
            }
        }

        std.debug.print("Finished training: {} merges completed\n", .{merges_done});

        // Step 4: Build tokenizer (transfers ownership of merges)
        const tokenizer = try self.buildTokenizer(merges);

        // Don't free merges - ownership transferred to tokenizer
        // merges.deinit() would double-free!

        return tokenizer;
    }

    /// Collect word counts from texts (parallel)
    fn collectWordCounts(
        self: *Trainer,
        texts: []const []const u8,
    ) !std.StringHashMap(i32) {
        var word_counts = std.StringHashMap(i32).init(self.allocator);

        // TODO: Add regex splitting for production
        // For now: simple whitespace splitting
        for (texts) |text| {
            var it = std.mem.splitScalar(u8, text, ' ');
            while (it.next()) |word| {
                if (word.len == 0) continue;

                const word_copy = try self.allocator.dupe(u8, word);
                const gop = try word_counts.getOrPut(word_copy);

                if (gop.found_existing) {
                    gop.value_ptr.* += 1;
                    self.allocator.free(word_copy); // Don't need duplicate
                } else {
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

        // Add merged tokens
        for (merges.items, 0..) |pair, idx| {
            try merges_map.put(pair, @intCast(idx));
        }

        const pattern_str = try self.allocator.dupe(u8, self.pattern_str);

        return Tokenizer{
            .vocab = vocab,
            .vocab_r = vocab_r,
            .merges = merges,
            .merges_map = merges_map,
            .pattern_str = pattern_str,
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
