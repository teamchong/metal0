/// Backtracking encoder - port of rs-bpe's algorithm
/// Greedy forward pass with backtracking on invalid pairs
/// Based on: ../../../rs-bpe/bpe/src/backtrack_encoder.rs
const std = @import("std");
const Allocator = std.mem.Allocator;

// Copy Pair from tokenizer.zig to avoid circular import
const Pair = struct {
    left: u32,
    right: u32,
};
const PairContext = struct {
    pub fn hash(_: PairContext, p: Pair) u64 {
        return (@as(u64, p.left) << 32) | p.right;
    }
    pub fn eql(_: PairContext, a: Pair, b: Pair) bool {
        return a.left == b.left and a.right == b.right;
    }
};

pub const BacktrackEncoder = struct {
    allocator: Allocator,
    text: []const u8,
    tokens: std.ArrayList(u32),
    next_token: ?u32, // Track next token to process (key state!)
    pos: usize,
    bitfield: BitField,

    // Vocab lookups
    vocab: *const std.StringHashMap(u32),
    vocab_r: *const std.AutoHashMap(u32, []const u8),

    pub fn init(
        allocator: Allocator,
        text: []const u8,
        vocab: *const std.StringHashMap(u32),
        vocab_r: *const std.AutoHashMap(u32, []const u8),
    ) !BacktrackEncoder {
        var tokens = std.ArrayList(u32){};
        try tokens.ensureTotalCapacity(allocator, text.len / 3);

        // Initialize next_token with first match (rs-bpe does this in constructor)
        const first_token = findNextMatch(text, 0, vocab);

        return BacktrackEncoder{
            .allocator = allocator,
            .text = text,
            .tokens = tokens,
            .next_token = first_token,
            .pos = 0,
            .bitfield = try BitField.init(allocator, text.len + 1),
            .vocab = vocab,
            .vocab_r = vocab_r,
        };
    }

    pub fn deinit(self: *BacktrackEncoder) void {
        self.tokens.deinit(self.allocator);
        self.bitfield.deinit();
    }

    /// Find longest token match starting at given position
    /// This is a static function like rs-bpe's next_match
    fn findNextMatch(text: []const u8, start_pos: usize, vocab: *const std.StringHashMap(u32)) ?u32 {
        if (start_pos >= text.len) return null;

        var best_token: ?u32 = null;

        // Start with single byte as fallback
        const byte = text[start_pos];
        const byte_slice = text[start_pos .. start_pos + 1];
        if (vocab.get(byte_slice)) |token| {
            best_token = token;
        } else {
            best_token = byte; // Raw byte fallback
        }

        // Try progressively longer matches (greedy longest)
        var len: usize = 2;
        while (start_pos + len <= text.len and len <= 512) : (len += 1) {
            const slice = text[start_pos .. start_pos + len];
            if (vocab.get(slice)) |token| {
                best_token = token;
            }
        }

        return best_token;
    }

    /// Find next shorter prefix of current token at current position
    fn nextPrefix(self: *BacktrackEncoder, token: u32) ?u32 {
        const token_len = self.tokenLen(token);
        if (token_len <= 1) return null;

        // Try progressively shorter prefixes
        var len = token_len - 1;
        while (len > 0) : (len -= 1) {
            const slice = self.text[self.pos .. self.pos + len];
            if (self.vocab.get(slice)) |shorter_token| {
                return shorter_token;
            }
        }

        return null;
    }

    /// Check if token pair is valid (can be merged) using split_table
    /// Port of rs-bpe's is_valid_token_pair
    fn isValidPair(self: *BacktrackEncoder, left: u32, right: u32) bool {
        // Use tokenizer's isValidTokenPair function (defined in tokenizer.zig)
        // For now, accept all pairs - full validation requires split_table in encoder
        // TODO: Pass split_table to encoder
        _ = self;
        _ = left;
        _ = right;
        return true; // Use HashMap encoder which has split_table
    }

    /// Get token length in bytes
    fn tokenLen(self: *BacktrackEncoder, token: u32) usize {
        if (self.vocab_r.get(token)) |bytes| {
            return bytes.len;
        }
        return 1; // Single byte fallback
    }

    /// Process one token step - returns next token to process
    /// This matches rs-bpe's step() function exactly
    fn step(self: *BacktrackEncoder) !?u32 {
        var token = self.next_token orelse return null;
        const last = if (self.tokens.items.len > 0)
            self.tokens.items[self.tokens.items.len - 1]
        else
            null;

        while (true) {
            const token_len = self.tokenLen(token);
            const end_pos = self.pos + token_len;

            // Check if we can accept this token
            const can_accept = blk: {
                // Must be at valid position
                if (!self.bitfield.isSet(end_pos)) break :blk false;

                // If there's a previous token, check if pair is valid
                if (last) |last_token| {
                    if (!self.isValidPair(last_token, token)) break :blk false;
                }

                break :blk true;
            };

            if (can_accept) {
                // Accept token and advance
                try self.tokens.append(self.allocator, token);
                self.pos = end_pos;
                // Find next match starting from new position
                self.next_token = findNextMatch(self.text, end_pos, self.vocab);
                break;
            } else if (self.nextPrefix(token)) |shorter| {
                // Try shorter prefix
                token = shorter;
                continue;
            } else {
                // Backtrack: clear bitfield, pop last token, restore position
                self.bitfield.clear(self.pos);
                if (self.tokens.items.len > 0) {
                    const popped = self.tokens.items[self.tokens.items.len - 1];
                    _ = self.tokens.pop();
                    const popped_len = self.tokenLen(popped);
                    self.pos -= popped_len;
                    self.next_token = last; // Retry the token we just popped
                } else {
                    self.next_token = null;
                }
                break;
            }
        }

        return self.next_token;
    }

    /// Main encoding loop - call step() until done
    pub fn encode(self: *BacktrackEncoder) ![]u32 {
        while (try self.step() != null) {
            // Keep stepping until no more tokens
        }
        return try self.tokens.toOwnedSlice(self.allocator);
    }
};

/// BitField for tracking valid positions
const BitField = struct {
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
        const word = pos >> 6;
        if (word >= self.bits.len) return false;
        const bit = @as(u6, @truncate(pos));
        return (self.bits[word] & (@as(u64, 1) << bit)) != 0;
    }

    pub inline fn clear(self: *BitField, pos: usize) void {
        const word = pos >> 6;
        if (word >= self.bits.len) return;
        const bit = @as(u6, @truncate(pos));
        self.bits[word] &= ~(@as(u64, 1) << bit);
    }
};
