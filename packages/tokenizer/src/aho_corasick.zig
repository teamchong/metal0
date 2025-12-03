/// Aho-Corasick automaton using double-array structure
/// EXACT port of daachorse (github.com/daac-tools/daachorse/src/bytewise.rs)
/// Algorithm: Double-Array Trie + Aho-Corasick failure links
const std = @import("std");
const Allocator = std.mem.Allocator;
const builder_mod = @import("aho_corasick_builder.zig");
const Builder = builder_mod.Builder;
const NO_OUTPUT = builder_mod.NO_OUTPUT;
const simd = @import("simd_encoder.zig");

const ROOT_STATE_IDX: u32 = 0;
const BLOCK_LEN: u32 = 256;

/// State struct - port of daachorse::State
pub const State = struct {
    /// Base offset for XOR-based child indexing (0 = no children)
    base: u32 = 0,
    /// Check byte (validates transition)
    check: u8 = 0,
    /// Failure link for Aho-Corasick
    fail: u32 = ROOT_STATE_IDX,
    /// Output position (index into outputs, 0 = no match)
    output_pos: u32 = 0,

    pub inline fn setBase(self: *State, base: u32) void {
        self.base = base;
    }

    pub inline fn setCheck(self: *State, c: u8) void {
        self.check = c;
    }

    pub inline fn setFail(self: *State, fail: u32) void {
        self.fail = fail;
    }

    pub inline fn setOutputPos(self: *State, pos: u32) void {
        self.output_pos = pos;
    }
};

/// Double-Array Aho-Corasick automaton
pub const AhoCorasick = struct {
    states: []State,
    outputs: []u32,
    allocator: Allocator,

    /// Port of daachorse::DoubleArrayAhoCorasick::new()
    pub fn build(
        allocator: Allocator,
        patterns: []const []const u8,
        token_ids: []const u32,
    ) !AhoCorasick {
        var builder = Builder.init(allocator);
        defer builder.deinit();

        // Build NFA first (pattern trie + failure links)
        try builder.buildNFA(patterns, token_ids);

        // Convert NFA to double-array
        const states = try builder.arrangeStates();
        const outputs = try builder.buildOutputs();

        return AhoCorasick{
            .states = states,
            .outputs = outputs,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AhoCorasick) void {
        self.allocator.free(self.states);
        self.allocator.free(self.outputs);
    }

    /// Port of daachorse leftmost_find_iter().next()
    /// Find the leftmost-longest match starting at position `start`
    /// Optimized with loop unrolling and pointer arithmetic
    pub fn longestMatch(self: *const AhoCorasick, text: []const u8, start: usize) ?u32 {
        @setRuntimeSafety(false);

        if (start >= text.len) return null;

        const states = self.states.ptr;
        const outputs = self.outputs.ptr;
        const states_len = self.states.len;

        var state_id: u32 = ROOT_STATE_IDX;
        var longest_token: ?u32 = null;
        var pos = start;

        // Unroll first 8 iterations for better branch prediction and reduced loop overhead
        // Most BPE tokens are 1-8 bytes, so this covers the common case
        comptime var i = 0;
        inline while (i < 8) : (i += 1) {
            if (pos >= text.len) return longest_token;

            const c = text[pos];
            const state = states[state_id];
            const base = state.base;

            // No children - we're done
            if (base == 0) return longest_token;

            const child_idx = base ^ c;

            // Combined bounds check + validation
            if (child_idx >= states_len) return longest_token;

            const child_state = states[child_idx];
            if (child_state.check != c) return longest_token;

            state_id = child_idx;

            // Check for output - output_pos points to outputs array
            // The outputs array value is NO_OUTPUT for non-pattern states
            const output_pos = child_state.output_pos;
            if (output_pos != 0) {
                const token_id = outputs[output_pos];
                if (token_id != NO_OUTPUT) {
                    longest_token = token_id;
                }

                // Early exit if we found a match and can't extend
                if (child_state.base == 0) return longest_token;
            }

            pos += 1;
        }

        // Continuation loop for longer matches (rare case)
        while (pos < text.len) {
            const c = text[pos];
            const state = states[state_id];
            const base = state.base;

            if (base == 0) break;

            const child_idx = base ^ c;
            if (child_idx >= states_len) break;

            const child_state = states[child_idx];
            if (child_state.check != c) break;

            state_id = child_idx;

            const output_pos = child_state.output_pos;
            if (output_pos != 0) {
                const token_id = outputs[output_pos];
                if (token_id != NO_OUTPUT) {
                    longest_token = token_id;
                }
                if (child_state.base == 0) break;
            }

            pos += 1;
        }

        return longest_token;
    }

    /// Check if we can extend the current state (has children)
    inline fn canExtend(self: *const AhoCorasick, state_id: u32) bool {
        return self.states[state_id].base != 0;
    }

    /// Find all overlapping matches starting at position (for next_prefix)
    pub fn overlappingMatches(self: *const AhoCorasick, text: []const u8, start: usize, allocator: std.mem.Allocator) ![]u32 {
        @setRuntimeSafety(false);

        if (start >= text.len) return try allocator.alloc(u32, 0);

        var matches = std.ArrayList(u32){};
        errdefer matches.deinit(allocator);

        var state_id: u32 = ROOT_STATE_IDX;
        var pos = start;

        while (pos < text.len) : (pos += 1) {
            const c = text[pos];

            // Transition to next state
            state_id = self.nextStateUnchecked(state_id, c);

            // Collect ALL outputs at this state (overlapping matches)
            const output_pos = self.states[state_id].output_pos;
            if (output_pos != 0) {
                try matches.append(allocator, self.outputs[output_pos]);
            }
        }

        // Avoid toOwnedSlice overhead - just dupe used portion
        const items = matches.items[0..matches.items.len];
        const owned = try allocator.dupe(u32, items);
        matches.clearRetainingCapacity();
        return owned;
    }

    /// Port of next_state_id_unchecked()
    inline fn nextStateUnchecked(self: *const AhoCorasick, state_id_arg: u32, c: u8) u32 {
        @setRuntimeSafety(false);

        var state_id = state_id_arg;
        while (true) {
            if (self.childIndexUnchecked(state_id, c)) |child_id| {
                return child_id;
            }
            if (state_id == ROOT_STATE_IDX) {
                return ROOT_STATE_IDX;
            }
            state_id = self.states[state_id].fail;
        }
    }

    /// Port of child_index_unchecked() - XOR-based child lookup
    inline fn childIndexUnchecked(self: *const AhoCorasick, state_id: u32, c: u8) ?u32 {
        @setRuntimeSafety(false);

        const state = &self.states[state_id];
        const base = state.base;
        if (base == 0) return null;

        const child_idx = base ^ c;
        if (child_idx >= self.states.len) return null;

        // Validate with check
        if (self.states[child_idx].check == c) {
            return child_idx;
        }

        return null;
    }
};

test "token id 0 is correctly recognized" {
    // Test that token ID 0 (!) is properly returned, not treated as "no match"
    const allocator = std.testing.allocator;

    // Create AC with single pattern "!" mapped to token 0
    const patterns = [_][]const u8{"!"};
    const token_ids = [_]u32{0};

    var ac = try AhoCorasick.build(allocator, &patterns, &token_ids);
    defer ac.deinit();

    // longestMatch should return 0, not null
    const result = ac.longestMatch("!", 0);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u32, 0), result.?);
}

test "various token ids work" {
    const allocator = std.testing.allocator;

    const patterns = [_][]const u8{ "!", "?", "." };
    const token_ids = [_]u32{ 0, 30, 13 };

    var ac = try AhoCorasick.build(allocator, &patterns, &token_ids);
    defer ac.deinit();

    // All should work
    try std.testing.expectEqual(@as(u32, 0), ac.longestMatch("!", 0).?);
    try std.testing.expectEqual(@as(u32, 30), ac.longestMatch("?", 0).?);
    try std.testing.expectEqual(@as(u32, 13), ac.longestMatch(".", 0).?);
}
