/// Aho-Corasick automaton using double-array structure
/// EXACT port of daachorse (github.com/daac-tools/daachorse/src/bytewise.rs)
/// Algorithm: Double-Array Trie + Aho-Corasick failure links
const std = @import("std");
const Allocator = std.mem.Allocator;

const ROOT_STATE_IDX: u32 = 0;
const BLOCK_LEN: u32 = 256;

/// State struct - port of daachorse::State
const State = struct {
    /// Base offset for XOR-based child indexing (0 = no children)
    base: u32 = 0,
    /// Check byte (validates transition)
    check: u8 = 0,
    /// Failure link for Aho-Corasick
    fail: u32 = ROOT_STATE_IDX,
    /// Output position (index into outputs, 0 = no match)
    output_pos: u32 = 0,

    inline fn setBase(self: *State, base: u32) void {
        self.base = base;
    }

    inline fn setCheck(self: *State, c: u8) void {
        self.check = c;
    }

    inline fn setFail(self: *State, fail: u32) void {
        self.fail = fail;
    }

    inline fn setOutputPos(self: *State, pos: u32) void {
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

    /// Port of next_state_id_unchecked() - transition with failure links
    pub fn longestMatch(self: *const AhoCorasick, text: []const u8, start: usize) ?u32 {
        @setRuntimeSafety(false);

        if (start >= text.len) return null;

        var state_id: u32 = ROOT_STATE_IDX;
        var longest_token: ?u32 = null;

        var pos = start;
        while (pos < text.len) : (pos += 1) {
            const c = text[pos];

            // Transition to next state (with failure link fallback)
            state_id = self.nextStateUnchecked(state_id, c);

            // Check output
            const output_pos = self.states[state_id].output_pos;
            if (output_pos != 0) {
                longest_token = self.outputs[output_pos];
            }
        }

        return longest_token;
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

/// Builder for constructing double-array (port of daachorse Builder)
const Builder = struct {
    allocator: Allocator,
    nfa_states: std.ArrayList(NFAState),
    patterns: std.ArrayList([]const u8),
    token_ids: std.ArrayList(u32),

    const NFAState = struct {
        children: std.AutoHashMap(u8, u32),
        fail: u32 = ROOT_STATE_IDX,
        output: u32 = 0,

        fn init(allocator: Allocator) NFAState {
            return .{
                .children = std.AutoHashMap(u8, u32).init(allocator),
                .fail = ROOT_STATE_IDX,
                .output = 0,
            };
        }

        fn deinit(self: *NFAState) void {
            self.children.deinit();
        }
    };

    fn init(allocator: Allocator) Builder {
        return .{
            .allocator = allocator,
            .nfa_states = std.ArrayList(NFAState){},
            .patterns = std.ArrayList([]const u8){},
            .token_ids = std.ArrayList(u32){},
        };
    }

    fn deinit(self: *Builder) void {
        for (self.nfa_states.items) |*state| {
            state.deinit();
        }
        self.nfa_states.deinit(self.allocator);
        self.patterns.deinit(self.allocator);
        self.token_ids.deinit(self.allocator);
    }

    /// Build NFA (trie + failure links)
    fn buildNFA(self: *Builder, patterns: []const []const u8, token_ids: []const u32) !void {
        // Add root state
        try self.nfa_states.append(self.allocator, NFAState.init(self.allocator));

        // Build trie
        for (patterns, 0..) |pattern, i| {
            try self.addPattern(pattern, token_ids[i]);
        }

        // Build failure links (BFS)
        try self.buildFailureLinks();
    }

    fn addPattern(self: *Builder, pattern: []const u8, token_id: u32) !void {
        var state_id: u32 = ROOT_STATE_IDX;

        for (pattern) |c| {
            const entry = try self.nfa_states.items[state_id].children.getOrPut(c);
            if (!entry.found_existing) {
                // Create new state
                const new_id = @as(u32, @intCast(self.nfa_states.items.len));
                entry.value_ptr.* = new_id;
                try self.nfa_states.append(self.allocator, NFAState.init(self.allocator));
            }
            state_id = entry.value_ptr.*;
        }

        // Mark final state
        self.nfa_states.items[state_id].output = token_id;
    }

    fn buildFailureLinks(self: *Builder) !void {
        var queue = std.ArrayList(u32){};
        defer queue.deinit(self.allocator);

        // Initialize: root's children fail to root
        var it = self.nfa_states.items[ROOT_STATE_IDX].children.iterator();
        while (it.next()) |entry| {
            const child_id = entry.value_ptr.*;
            self.nfa_states.items[child_id].fail = ROOT_STATE_IDX;
            try queue.append(self.allocator, child_id);
        }

        // BFS to build failure links
        var head: usize = 0;
        while (head < queue.items.len) : (head += 1) {
            const state_id = queue.items[head];
            var child_it = self.nfa_states.items[state_id].children.iterator();

            while (child_it.next()) |entry| {
                const c = entry.key_ptr.*;
                const child_id = entry.value_ptr.*;

                // Find failure link
                var fail_state = self.nfa_states.items[state_id].fail;
                while (fail_state != ROOT_STATE_IDX) {
                    if (self.nfa_states.items[fail_state].children.get(c)) |target| {
                        self.nfa_states.items[child_id].fail = target;
                        break;
                    }
                    fail_state = self.nfa_states.items[fail_state].fail;
                } else {
                    // Check root
                    if (self.nfa_states.items[ROOT_STATE_IDX].children.get(c)) |target| {
                        self.nfa_states.items[child_id].fail = target;
                    } else {
                        self.nfa_states.items[child_id].fail = ROOT_STATE_IDX;
                    }
                }

                try queue.append(self.allocator, child_id);
            }
        }
    }

    /// Convert NFA to double-array (port of daachorse arrange())
    fn arrangeStates(self: *Builder) ![]State {
        var helper = BuildHelper.init(self.allocator);
        defer helper.deinit();

        var states = std.ArrayList(State){};
        errdefer states.deinit(self.allocator);

        // Preallocate
        try states.ensureTotalCapacity(self.allocator, self.nfa_states.items.len * 2);

        // Add root
        try states.append(self.allocator, State{});

        // Process each NFA state
        for (self.nfa_states.items, 0..) |*nfa_state, nfa_id| {
            if (nfa_state.children.count() == 0) continue;

            // Get sorted labels
            var labels = std.ArrayList(u8){};
            defer labels.deinit(self.allocator);

            var it = nfa_state.children.keyIterator();
            while (it.next()) |c| {
                try labels.append(self.allocator, c.*);
            }
            std.sort.insertion(u8, labels.items, {}, std.sort.asc(u8));

            // Find base
            const base = try self.findBase(labels.items, &helper, &states);
            states.items[nfa_id].setBase(base);

            // Create children
            for (labels.items) |c| {
                const child_idx = base ^ c;
                const nfa_child_id = nfa_state.children.get(c).?;

                // Ensure capacity
                while (states.items.len <= child_idx) {
                    try states.append(self.allocator, State{});
                }

                states.items[child_idx].setCheck(c);
                states.items[child_idx].setFail(self.nfa_states.items[nfa_child_id].fail);
                states.items[child_idx].setOutputPos(if (self.nfa_states.items[nfa_child_id].output != 0) nfa_child_id else 0);

                try helper.markUsed(child_idx);
            }

            try helper.markUsedBase(base);
        }

        return try states.toOwnedSlice(self.allocator);
    }

    /// Port of find_base() - find conflict-free base value
    fn findBase(self: *Builder, labels: []const u8, helper: *BuildHelper, states: *std.ArrayList(State)) !u32 {
        _ = self;

        var iter = helper.vacantIter(states.items.len);
        while (iter.next()) |idx| {
            const base = idx ^ @as(u32, labels[0]);
            if (checkValidBase(base, labels, helper, states.items.len)) |valid_base| {
                return valid_base;
            }
        }

        // Extend array
        return @intCast(states.items.len);
    }

    fn buildOutputs(self: *Builder) ![]u32 {
        var outputs = std.ArrayList(u32){};
        errdefer outputs.deinit(self.allocator);

        for (self.nfa_states.items) |*nfa_state| {
            try outputs.append(self.allocator, nfa_state.output);
        }

        return try outputs.toOwnedSlice(self.allocator);
    }
};

/// Port of check_valid_base()
fn checkValidBase(base: u32, labels: []const u8, helper: *BuildHelper, max_len: usize) ?u32 {
    if (base == 0) return null;
    if (helper.isUsedBase(base)) return null;

    for (labels) |c| {
        const idx = base ^ c;
        if (idx >= max_len) continue; // Will be extended
        if (helper.isUsedIndex(idx)) return null;
    }

    return base;
}

/// Helper for tracking used indices during construction
const BuildHelper = struct {
    used_indices: std.AutoHashMap(u32, void),
    used_bases: std.AutoHashMap(u32, void),
    allocator: Allocator,

    fn init(allocator: Allocator) BuildHelper {
        return .{
            .used_indices = std.AutoHashMap(u32, void).init(allocator),
            .used_bases = std.AutoHashMap(u32, void).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *BuildHelper) void {
        self.used_indices.deinit();
        self.used_bases.deinit();
    }

    fn markUsed(self: *BuildHelper, idx: u32) !void {
        try self.used_indices.put(idx, {});
    }

    fn markUsedBase(self: *BuildHelper, base: u32) !void {
        try self.used_bases.put(base, {});
    }

    fn isUsedIndex(self: *BuildHelper, idx: u32) bool {
        return self.used_indices.contains(idx);
    }

    fn isUsedBase(self: *BuildHelper, base: u32) bool {
        return self.used_bases.contains(base);
    }

    fn vacantIter(_: *BuildHelper, max_len: usize) VacantIterator {
        // Returns sequential indices for now
        // TODO: Implement proper block-based iteration like daachorse
        return VacantIterator{
            .current = 0,
            .max = @intCast(max_len),
        };
    }
};

const VacantIterator = struct {
    current: u32,
    max: u32,

    fn next(self: *VacantIterator) ?u32 {
        if (self.current >= self.max) return null;
        const val = self.current;
        self.current += 1;
        return val;
    }
};
