/// Aho-Corasick automaton using double-array structure
/// EXACT port of daachorse (github.com/daac-tools/daachorse/src/bytewise.rs)
/// Algorithm: Double-Array Trie + Aho-Corasick failure links
const std = @import("std");
const Allocator = std.mem.Allocator;
const Builder = @import("aho_corasick_builder.zig").Builder;

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
    pub fn longestMatch(self: *const AhoCorasick, text: []const u8, start: usize) ?u32 {
        @setRuntimeSafety(false);

        if (start >= text.len) return null;

        var state_id: u32 = ROOT_STATE_IDX;
        var longest_token: ?u32 = null;

        var pos = start;
        while (pos < text.len) : (pos += 1) {
            const c = text[pos];

            // Strict prefix match: only follow children, no failure links
            if (self.childIndexUnchecked(state_id, c)) |child_id| {
                state_id = child_id;
            } else {
                break;
            }

            // Check output - record if this is the longest match so far
            const output_pos = self.states[state_id].output_pos;
            if (output_pos != 0) {
                longest_token = self.outputs[output_pos];
            }

            // CRITICAL: If we have a match and can't extend further, stop
            // This implements leftmost-longest: we found the longest match starting at `start`
            if (longest_token != null and !self.canExtend(state_id)) {
                break;
            }
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

        return try matches.toOwnedSlice(allocator);
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
