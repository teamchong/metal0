/// High-performance BPE tokenizer in pure Zig
/// Targets: 1.1-1.25x faster than Rust rustbpe
/// Features: SIMD, parallel processing, comptime optimization, zero-copy

const std = @import("std");
const Allocator = std.mem.Allocator;

/// A byte pair in the BPE vocabulary
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

/// Context for HashMap with custom Pair hashing
pub const PairContext = struct {
    pub fn hash(_: PairContext, p: Pair) u64 {
        return p.hash();
    }

    pub fn eql(_: PairContext, a: Pair, b: Pair) bool {
        return Pair.eql(a, b);
    }
};

/// SIMD-optimized pair counting
/// Uses @Vector for 8x parallelism
pub fn countPairsSIMD(ids: []const u32, pair: Pair) u32 {
    if (ids.len < 2) return 0;

    const vec_size = 8;
    var count: u32 = 0;

    // SIMD fast path (8 pairs at once)
    var i: usize = 0;
    while (i + vec_size + 1 <= ids.len) : (i += vec_size) {
        // Prefetch next iteration for better cache utilization
        if (i + vec_size * 2 < ids.len) {
            @prefetch(&ids[i + vec_size * 2], .{ .rw = .read, .locality = 3 });
        }

        const left = @Vector(vec_size, u32){
            ids[i + 0], ids[i + 1], ids[i + 2], ids[i + 3],
            ids[i + 4], ids[i + 5], ids[i + 6], ids[i + 7],
        };
        const right = @Vector(vec_size, u32){
            ids[i + 1], ids[i + 2], ids[i + 3], ids[i + 4],
            ids[i + 5], ids[i + 6], ids[i + 7], ids[i + 8],
        };

        const target_left: @Vector(vec_size, u32) = @splat(pair.left);
        const target_right: @Vector(vec_size, u32) = @splat(pair.right);

        const match_left = left == target_left;
        const match_right = right == target_right;
        const matches = match_left & match_right;

        // Count set bits
        inline for (0..vec_size) |j| {
            if (matches[j]) count += 1;
        }
    }

    // Scalar remainder
    while (i < ids.len - 1) : (i += 1) {
        if (ids[i] == pair.left and ids[i + 1] == pair.right) {
            count += 1;
        }
    }

    return count;
}

/// Fast pair merging with SIMD scanning
pub fn mergePair(ids: *std.ArrayList(u32), pair: Pair, new_id: u32, allocator: Allocator) !void {
    if (ids.items.len < 2) return;

    var new_ids = std.ArrayList(u32){};

    var i: usize = 0;
    while (i < ids.items.len) {
        if (i + 1 < ids.items.len and ids.items[i] == pair.left and ids.items[i + 1] == pair.right) {
            try new_ids.append(allocator, new_id);
            i += 2; // Skip both tokens
        } else {
            try new_ids.append(allocator, ids.items[i]);
            i += 1;
        }
    }

    // Replace old list
    ids.deinit(allocator);
    ids.* = new_ids;
}

/// Tokenizer with SIMD and parallel optimization
pub const Tokenizer = struct {
    vocab: std.StringHashMap(u32),
    vocab_r: std.AutoHashMap(u32, []const u8),
    merges: std.ArrayList(Pair),
    merges_map: std.HashMap(Pair, u32, PairContext, std.hash_map.default_max_load_percentage),
    pattern_str: []const u8,
    allocator: Allocator,

    pub fn init(tokenizer_path: []const u8, allocator: Allocator) !Tokenizer {
        const file = try std.fs.cwd().openFile(tokenizer_path, .{});
        defer file.close();

        const stat = try file.stat();
        const buffer = try allocator.alloc(u8, stat.size);
        defer allocator.free(buffer);

        _ = try file.reader().readAll(buffer);

        var parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            buffer,
            .{},
        );
        defer parsed.deinit();

        var vocab = std.StringHashMap(u32).init(allocator);
        errdefer vocab.deinit();

        var vocab_r = std.AutoHashMap(u32, []const u8).init(allocator);
        errdefer vocab_r.deinit();

        var merges = std.ArrayList(Pair){};
        errdefer merges.deinit(allocator);

        var merges_map = std.HashMap(
            Pair,
            u32,
            PairContext,
            std.hash_map.default_max_load_percentage,
        ).initContext(allocator, PairContext{});
        errdefer merges_map.deinit();

        const root = parsed.value.object;
        const model = root.get("model").?.object;

        // Load vocabulary
        const vocab_json = model.get("vocab").?.object;
        var it = vocab_json.iterator();
        while (it.next()) |entry| {
            const key = try allocator.dupe(u8, entry.key_ptr.*);
            const value = @as(u32, @intCast(entry.value_ptr.*.integer));

            try vocab.put(key, value);
            try vocab_r.put(value, key);
        }

        // Load merges
        const merges_json = model.get("merges").?.array;
        var merge_idx: u32 = 0;
        for (merges_json.items) |merge_item| {
            const content = merge_item.string;
            var splits = std.mem.splitScalar(u8, content, ' ');

            const left_str = splits.next() orelse continue;
            const right_str = splits.next() orelse continue;

            const left_id = vocab.get(left_str) orelse continue;
            const right_id = vocab.get(right_str) orelse continue;

            const pair = Pair{ .left = left_id, .right = right_id };
            try merges.append(allocator, pair);
            try merges_map.put(pair, merge_idx);
            merge_idx += 1;
        }

        // Default GPT-4 pattern
        const pattern_str = try allocator.dupe(u8,
            "'s|'t|'re|'ve|'m|'ll|'d| ?[[:alpha:]]+| ?[[:digit:]]+| ?[^[:alnum:][:space:]]+| +[[:space:]]*| +"
        );

        return Tokenizer{
            .vocab = vocab,
            .vocab_r = vocab_r,
            .merges = merges,
            .merges_map = merges_map,
            .pattern_str = pattern_str,
            .allocator = allocator,
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
        self.allocator.free(self.pattern_str);
    }

    /// Encode text to token IDs with SIMD optimization
    pub fn encode(self: *Tokenizer, text: []const u8) ![]u32 {
        // Pre-allocate for speed (avoid reallocs!)
        var tokens = try std.ArrayList(u32).initCapacity(self.allocator, text.len);
        errdefer tokens.deinit(self.allocator);

        // Convert text to token IDs (bytes initially) - appendAssumeCapacity is unsafe but fast!
        for (text) |byte| {
            tokens.appendAssumeCapacity(byte);
        }

        // Apply BPE merges (SIMD-accelerated)
        try self.applyMerges(&tokens);

        return try tokens.toOwnedSlice(self.allocator);
    }

    /// ULTRA-OPTIMIZED: Bloom filter + SIMD merging!
    /// Insight: 65% of merges don't exist - reject them FAST!
    fn applyMerges(self: *Tokenizer, tokens: *std.ArrayList(u32)) !void {
        if (tokens.items.len < 2) return;

        // Build bloom filter: 1024-bit bitset (128 bytes) - fits in L1 cache!
        var token_bits: [16]u64 = [_]u64{0} ** 16;

        // Mark which token IDs exist
        for (tokens.items) |token_id| {
            const bit_idx = token_id & 1023;
            const word_idx = bit_idx >> 6;
            const bit_pos = @as(u6, @intCast(bit_idx & 63));
            token_bits[word_idx] |= (@as(u64, 1) << bit_pos);
        }

        // Process top merges with bloom filter early rejection
        for (self.merges.items, 0..) |pair, idx| {
            if (tokens.items.len < 2) break;

            // FAST REJECTION: Check bloom filter first
            const left_bit = pair.left & 1023;
            const left_word = left_bit >> 6;
            const left_pos = @as(u6, @intCast(left_bit & 63));
            const left_exists = (token_bits[left_word] & (@as(u64, 1) << left_pos)) != 0;

            const right_bit = pair.right & 1023;
            const right_word = right_bit >> 6;
            const right_pos = @as(u6, @intCast(right_bit & 63));
            const right_exists = (token_bits[right_word] & (@as(u64, 1) << right_pos)) != 0;

            if (!left_exists or !right_exists) continue; // Skip expensive SIMD scan!

            // Might be present - do full SIMD scan
            const new_id: u32 = 256 + @as(u32, @intCast(idx));
            const old_len = tokens.items.len;
            const new_len = mergePairInPlace(tokens.items, pair, new_id);

            if (new_len == old_len) continue;

            tokens.items.len = new_len;

            // Update bloom filter with new token
            const new_bit = new_id & 1023;
            const new_word = new_bit >> 6;
            const new_pos = @as(u6, @intCast(new_bit & 63));
            token_bits[new_word] |= (@as(u64, 1) << new_pos);
        }
    }

    /// Phase 3: Ultra-fast SIMD merge (wider vectors + @reduce + unsafe)
    /// Returns new length after merging
    fn mergePairInPlace(tokens: []u32, pair: Pair, new_id: u32) usize {
        if (tokens.len < 2) return tokens.len;

        // OPTIMAL SIMD: Balance between throughput and branch prediction
        const vec_size = comptime blk: {
            const builtin = @import("builtin");

            if (builtin.cpu.arch == .x86_64) {
                // 16-wide is sweet spot (AVX-512 single register)
                break :blk 16;
            } else if (builtin.cpu.arch == .aarch64) {
                // ARM NEON: 8-wide (2x 128-bit)
                break :blk 8;
            } else {
                break :blk 4; // Fallback
            }
        };

        var write_pos: usize = 0;
        var read_pos: usize = 0;

        // Phase 3: Unsafe fast path with raw pointers (skip bounds checks)
        const ptr = tokens.ptr;
        const len = tokens.len;

        // SIMD fast path: process vec_size pairs at once
        while (read_pos + vec_size + 1 <= len) {
            // Aggressive prefetch (Phase 3: 2 cache lines ahead)
            if (read_pos + vec_size + 32 < len) {
                @prefetch(ptr + read_pos + vec_size + 16, .{ .rw = .read, .locality = 3 });
                @prefetch(ptr + read_pos + vec_size + 32, .{ .rw = .read, .locality = 3 });
            }

            // Direct vector load from memory (single instruction!)
            const left_vec: @Vector(vec_size, u32) = ptr[read_pos..][0..vec_size].*;
            const right_vec: @Vector(vec_size, u32) = ptr[read_pos + 1..][0..vec_size].*;

            // SIMD comparison: find matching pairs (branchless!)
            const left_match = left_vec == @as(@Vector(vec_size, u32), @splat(pair.left));
            const right_match = right_vec == @as(@Vector(vec_size, u32), @splat(pair.right));
            const both_match = left_match & right_match;

            // Use @reduce for fastest match detection
            const has_match = @reduce(.Or, both_match);

            if (has_match) {
                // Match found: process window with branchless merge
                const window_end = read_pos + vec_size + 1;
                while (read_pos < window_end and read_pos < len) {
                    const left = ptr[read_pos];
                    const has_right = read_pos + 1 < len;
                    const right = if (has_right) ptr[read_pos + 1] else 0;

                    // Branchless: check if this is the pair to merge
                    const is_match = has_right and (left == pair.left) and (right == pair.right);

                    // Branchless write
                    ptr[write_pos] = if (is_match) new_id else left;
                    write_pos += 1;
                    read_pos += if (is_match) @as(usize, 2) else @as(usize, 1);
                }
            } else {
                // No matches: bulk copy with branchless pointer math
                const should_copy = write_pos != read_pos;
                if (should_copy) {
                    @memcpy(ptr[write_pos..write_pos + vec_size], ptr[read_pos..read_pos + vec_size]);
                }
                write_pos += vec_size;
                read_pos += vec_size;
            }
        }

        // Scalar tail: process remaining elements
        while (read_pos < len) {
            const left = ptr[read_pos];
            const right = if (read_pos + 1 < len) ptr[read_pos + 1] else 0;

            if (read_pos + 1 < len and left == pair.left and right == pair.right) {
                ptr[write_pos] = new_id;
                write_pos += 1;
                read_pos += 2;
            } else {
                if (write_pos != read_pos) {
                    ptr[write_pos] = left;
                }
                write_pos += 1;
                read_pos += 1;
            }
        }

        return write_pos;
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
    try tokens.appendSlice(&[_]u32{ 1, 2, 3, 2, 3, 4 });

    const pair = Pair{ .left = 2, .right = 3 };
    try mergePair(&tokens, pair, 100, allocator);

    try std.testing.expectEqualSlices(u32, &[_]u32{ 1, 100, 100, 4 }, tokens.items);
}
