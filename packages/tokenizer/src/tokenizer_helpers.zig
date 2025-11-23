/// Utility types and helper functions for tokenizer
/// Part of tokenizer.zig split (was lines 14-268)

const std = @import("std");
const Allocator = std.mem.Allocator;
const wyhash = @import("wyhash.zig");

/// A byte pair in the BPE vocabulary
pub const Pair = struct {
    left: u32,
    right: u32,

    pub fn hash(self: Pair) u64 {
        // Use WyHash for 10-20% faster hashing (simpler than streaming API)
        // Pack both u32s into 8 bytes for single hash
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u32, bytes[0..4], self.left, .little);
        std.mem.writeInt(u32, bytes[4..8], self.right, .little);
        return wyhash.Wyhash11.hash(0, &bytes);
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

/// Context for string keys using WyHash (10-20% faster than default)
pub const StringHashContext = struct {
    pub fn hash(_: StringHashContext, key: []const u8) u64 {
        return wyhash.Wyhash11.hash(0, key);
    }

    pub fn eql(_: StringHashContext, a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};

/// BitField for heap-based BPE encoding (rs-bpe algorithm)
/// Tracks token boundaries without array shifting
pub const BitField = struct {
    bits: []u64,
    allocator: Allocator,

    pub fn init(allocator: Allocator, size: usize) !BitField {
        const num_words = (size + 63) / 64;
        const bits = try allocator.alloc(u64, num_words);
        @memset(bits, 0xFFFFFFFFFFFFFFFF); // All bits set initially
        return BitField{ .bits = bits, .allocator = allocator };
    }

    pub fn deinit(self: *BitField) void {
        self.allocator.free(self.bits);
    }

    pub inline fn isSet(self: *const BitField, pos: usize) bool {
        const word = pos >> 6; // pos / 64
        const bit = @as(u6, @truncate(pos));
        return (self.bits[word] & (@as(u64, 1) << bit)) != 0;
    }

    pub inline fn clear(self: *BitField, pos: usize) void {
        const word = pos >> 6;
        const bit = @as(u6, @truncate(pos));
        self.bits[word] &= ~(@as(u64, 1) << bit);
    }

    /// Find next set bit after pos (successor in boundary list)
    pub fn successor(self: *const BitField, pos: usize) ?usize {
        var word_idx = pos >> 6;
        const bit_offset = @as(u6, @truncate(pos));

        // Check remaining bits in current word
        const mask = ~(@as(u64, 0)) << bit_offset;
        if (self.bits[word_idx] & mask != 0) {
            const bit = @ctz(self.bits[word_idx] & mask);
            return (word_idx << 6) | bit;
        }

        // Check subsequent words
        word_idx += 1;
        while (word_idx < self.bits.len) : (word_idx += 1) {
            if (self.bits[word_idx] != 0) {
                const bit = @ctz(self.bits[word_idx]);
                return (word_idx << 6) | bit;
            }
        }

        return null;
    }

    /// Find previous set bit before pos (predecessor in boundary list)
    pub fn predecessor(self: *const BitField, pos: usize) ?usize {
        if (pos == 0) return null;

        var word_idx = (pos - 1) >> 6;
        const bit_offset = @as(u6, @truncate(pos - 1));

        // Check bits up to bit_offset in current word
        const mask = (@as(u64, 1) << (bit_offset + 1)) - 1;
        if (self.bits[word_idx] & mask != 0) {
            // Find highest set bit
            var test_word = self.bits[word_idx] & mask;
            var bit: u6 = 0;
            while (test_word != 0) {
                bit = @intCast(@ctz(test_word));
                test_word &= test_word - 1;
            }
            return (word_idx << 6) | bit;
        }

        // Check previous words
        if (word_idx == 0) return null;
        word_idx -= 1;
        while (true) : (word_idx -= 1) {
            if (self.bits[word_idx] != 0) {
                var test_word = self.bits[word_idx];
                var bit: u6 = 0;
                while (test_word != 0) {
                    bit = @intCast(@ctz(test_word));
                    test_word &= test_word - 1;
                }
                return (word_idx << 6) | bit;
            }
            if (word_idx == 0) break;
        }

        return null;
    }
};

/// Trie node for fast longest-match token lookup (array-based for speed)
pub const TrieNode = struct {
    children: [256]?*TrieNode, // Direct array lookup (fast!)
    token_id: ?u32, // If this is end of a token
    allocator: Allocator,

    pub fn init(allocator: Allocator) !*TrieNode {
        const node = try allocator.create(TrieNode);
        node.* = TrieNode{
            .children = [_]?*TrieNode{null} ** 256,
            .token_id = null,
            .allocator = allocator,
        };
        return node;
    }

    pub fn deinit(self: *TrieNode) void {
        for (self.children) |child_opt| {
            if (child_opt) |child| {
                child.deinit();
            }
        }
        self.allocator.destroy(self);
    }

    pub fn insert(self: *TrieNode, bytes: []const u8, token_id: u32) !void {
        var current = self;
        for (bytes) |byte| {
            if (current.children[byte]) |child| {
                current = child;
            } else {
                const new_child = try TrieNode.init(current.allocator);
                current.children[byte] = new_child;
                current = new_child;
            }
        }
        current.token_id = token_id;
    }

    /// Find longest match starting at text[pos]
    pub fn longestMatch(self: *TrieNode, text: []const u8, pos: usize) struct { len: usize, token_id: u32 } {
        var current = self;
        var best_len: usize = 0;
        var best_token: u32 = text[pos]; // Default to byte

        var i: usize = pos;
        while (i < text.len) : (i += 1) {
            const byte = text[i];
            const child = current.children[byte] orelse break;

            if (child.token_id) |token_id| {
                best_len = i - pos + 1;
                best_token = token_id;
            }

            current = child;
        }

        if (best_len == 0) {
            best_len = 1; // Single byte
        }

        return .{ .len = best_len, .token_id = best_token };
    }
};

/// SIMD-optimized pair counting
/// Uses @Vector for 8x parallelism
pub fn countPairsSIMD(ids: []const u32, pair: Pair) u32 {
    if (ids.len < 2) return 0;

    var count: u32 = 0;
    const simd_width = 8;

    // SIMD section
    if (ids.len >= simd_width + 1) {
        const left_vec: @Vector(simd_width, u32) = @splat(pair.left);
        const right_vec: @Vector(simd_width, u32) = @splat(pair.right);

        var i: usize = 0;
        while (i + simd_width < ids.len) : (i += simd_width) {
            const current_vec: @Vector(simd_width, u32) = ids[i..][0..simd_width].*;
            const next_vec: @Vector(simd_width, u32) = ids[i + 1 ..][0..simd_width].*;

            const left_match = current_vec == left_vec;
            const right_match = next_vec == right_vec;
            const both_match: @Vector(simd_width, bool) = left_match and right_match;

            for (both_match) |match| {
                if (match) count += 1;
            }
        }
    }

    // Scalar remainder
    var i: usize = (ids.len / simd_width) * simd_width;
    while (i + 1 < ids.len) : (i += 1) {
        if (ids[i] == pair.left and ids[i + 1] == pair.right) {
            count += 1;
        }
    }

    return count;
}

/// Merge all occurrences of pair into new_id (in-place ArrayList modification)
/// Zig 0.15.2: Pass allocator to .append() and .orderedRemove()
pub fn mergePair(ids: *std.ArrayList(u32), pair: Pair, new_id: u32, allocator: Allocator) !void {
    var write_pos: usize = 0;
    var read_pos: usize = 0;

    while (read_pos < ids.items.len) {
        if (read_pos + 1 < ids.items.len and
            ids.items[read_pos] == pair.left and
            ids.items[read_pos + 1] == pair.right)
        {
            ids.items[write_pos] = new_id;
            write_pos += 1;
            read_pos += 2; // Skip both tokens
        } else {
            ids.items[write_pos] = ids.items[read_pos];
            write_pos += 1;
            read_pos += 1;
        }
    }

    // Truncate to write_pos
    ids.items.len = write_pos;
    _ = allocator; // Suppress unused warning
}
