/// BPE Training - Helper structures and statistics functions
/// Extracted from trainer.zig for file size compliance

const std = @import("std");
const Allocator = std.mem.Allocator;
const Pair = @import("tokenizer.zig").Pair;
const PairContext = @import("tokenizer.zig").PairContext;

/// Word with its frequency count
pub const Word = struct {
    ids: []u32,
    count: i32,
    original_allocation: []u32, // Track original allocation for proper freeing

    pub fn deinit(self: *Word, allocator: Allocator) void {
        allocator.free(self.original_allocation);
    }
};

/// Parallel chunk for multi-threaded processing
pub const ChunkResult = struct {
    pair_counts: std.HashMap(Pair, i32, PairContext, std.hash_map.default_max_load_percentage),
    allocator: Allocator,

    pub fn deinit(self: *ChunkResult) void {
        self.pair_counts.deinit();
    }
};

/// Merge candidate for priority queue (Phase 1 optimization)
pub const MergeCandidate = struct {
    pair: Pair,
    frequency: i32,

    /// Compare for max-heap (higher frequency = higher priority)
    pub fn compare(context: void, a: MergeCandidate, b: MergeCandidate) std.math.Order {
        _ = context;
        // Reverse order for max-heap (std.PriorityQueue is min-heap by default)
        return std.math.order(b.frequency, a.frequency);
    }
};

/// Position tracker for incremental updates (Phase 1.5)
/// Tracks which word indices contain each pair
pub const PairPositions = struct {
    allocator: Allocator,
    map: std.HashMap(Pair, std.ArrayList(usize), PairContext, std.hash_map.default_max_load_percentage),

    pub fn init(allocator: Allocator) PairPositions {
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

    pub fn deinit(self: *PairPositions) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.map.deinit();
    }

    /// Add a word index to a pair's position list
    pub fn addPosition(self: *PairPositions, pair: Pair, word_idx: usize) !void {
        const gop = try self.map.getOrPut(pair);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.ArrayList(usize){};
        }
        try gop.value_ptr.append(self.allocator, word_idx);
    }

    /// Remove a word index from a pair's position list
    pub fn removePosition(self: *PairPositions, pair: Pair, word_idx: usize) void {
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
    pub fn getPositions(self: *PairPositions, pair: Pair) ?[]const usize {
        if (self.map.get(pair)) |positions| {
            return positions.items;
        }
        return null;
    }
};

/// Count all pairs in words (parallel with SIMD)
pub fn countPairsParallel(
    words: []const Word,
    allocator: Allocator,
) !std.HashMap(Pair, i32, PairContext, std.hash_map.default_max_load_percentage) {
    // FORCE single-threaded for profiling
    return countPairsSingleThreaded(words, allocator);
}

pub fn countPairsParallelOLD(
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
pub fn countPairsChunk(
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
pub fn countPairsSingleThreaded(
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
pub fn mergePairInPlace(word: *Word, pair: Pair, new_id: u32) bool {
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
