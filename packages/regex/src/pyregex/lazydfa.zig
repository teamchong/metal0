/// Lazy DFA - Build DFA states on-demand with caching
/// Converts NFA subset construction to a cached DFA for O(n) matching
const std = @import("std");
const nfa_mod = @import("nfa.zig");
const NFA = nfa_mod.NFA;
const StateId = nfa_mod.StateId;
const Transition = nfa_mod.Transition;
const MATCH_STATE = nfa_mod.MATCH_STATE;

/// DFA state ID
const DfaStateId = u32;
const DEAD_STATE: DfaStateId = 0;
const START_STATE: DfaStateId = 1;

/// Match result
pub const Match = struct {
    start: usize,
    end: usize,
};

/// A DFA state represents a set of NFA states
const DfaState = struct {
    /// Set of NFA states this DFA state represents
    nfa_states: []StateId,
    /// Transition table: byte -> DFA state
    transitions: [256]DfaStateId,
    /// Is this a match state?
    is_match: bool,

    pub fn init(allocator: std.mem.Allocator, nfa_states: []StateId, is_match: bool) !DfaState {
        const states_copy = try allocator.dupe(StateId, nfa_states);

        var state = DfaState{
            .nfa_states = states_copy,
            .transitions = undefined,
            .is_match = is_match,
        };

        // Initialize all transitions to DEAD_STATE
        for (&state.transitions) |*t| {
            t.* = DEAD_STATE;
        }

        return state;
    }

    pub fn deinit(self: *DfaState, allocator: std.mem.Allocator) void {
        allocator.free(self.nfa_states);
    }
};

/// Hash function for NFA state sets
fn hashStateSet(states: []const StateId) u64 {
    var hasher = std.hash.Wyhash.init(0);
    for (states) |state| {
        hasher.update(std.mem.asBytes(&state));
    }
    return hasher.final();
}

/// Check if two state sets are equal
fn stateSetEqual(a: []const StateId, b: []const StateId) bool {
    if (a.len != b.len) return false;
    for (a, b) |sa, sb| {
        if (sa != sb) return false;
    }
    return true;
}

/// Lazy DFA executor
pub const LazyDFA = struct {
    nfa: *const NFA,
    allocator: std.mem.Allocator,

    /// Cache of DFA states
    states: std.ArrayList(DfaState),

    /// Map from NFA state set -> DFA state ID
    state_cache: std.AutoHashMap(u64, DfaStateId),

    /// Optional prefix literal for fast scanning (single or multi-byte)
    prefix_literal: ?[]const u8,
    prefix_window_before: usize,
    prefix_window_after: usize,

    pub fn init(allocator: std.mem.Allocator, nfa_ptr: *const NFA) LazyDFA {
        return .{
            .nfa = nfa_ptr,
            .allocator = allocator,
            .states = std.ArrayList(DfaState){},
            .state_cache = std.AutoHashMap(u64, DfaStateId).init(allocator),
            .prefix_literal = null,
            .prefix_window_before = 5,
            .prefix_window_after = 5,
        };
    }

    /// Set prefix literal hint for fast scanning
    /// Can be single byte ('@') or multi-byte ('://')
    /// Optionally specify custom window size (before, after)
    pub fn setPrefix(self: *LazyDFA, literal: []const u8) void {
        self.prefix_literal = literal;
    }

    pub fn setPrefixWithWindow(self: *LazyDFA, literal: []const u8, before: usize, after: usize) void {
        self.prefix_literal = literal;
        self.prefix_window_before = before;
        self.prefix_window_after = after;
    }

    pub fn deinit(self: *LazyDFA) void {
        for (self.states.items) |*state| {
            state.deinit(self.allocator);
        }
        self.states.deinit(self.allocator);
        self.state_cache.deinit();
    }

    /// Find first match in text
    pub fn find(self: *LazyDFA, text: []const u8) !?Match {
        // Try matching at each starting position
        var start: usize = 0;
        while (start <= text.len) : (start += 1) {
            if (try self.findAt(text, start)) |match| {
                return match;
            }
        }
        return null;
    }

    /// Find all matches in text (like Rust find_iter)
    pub fn findAll(self: *LazyDFA, text: []const u8, allocator: std.mem.Allocator) ![]Match {
        if (text.len == 0) return allocator.alloc(Match, 0);

        // Initialize DFA if needed
        if (self.states.items.len == 0) {
            try self.initializeDFA();
        }

        // Use prefix scanning if available
        if (self.prefix_literal) |prefix| {
            return try self.findAllWithPrefix(text, allocator, prefix);
        }

        var matches = std.ArrayList(Match){};

        var search_start: usize = 0;
        while (search_start < text.len) {
            // Run DFA starting from search_start
            var current_state: DfaStateId = START_STATE;
            var last_match_end: ?usize = null;
            const last_match_start: usize = search_start;

            // Check if start state is a match state
            if (self.states.items[START_STATE].is_match) {
                last_match_end = search_start;
            }

            var pos = search_start;
            while (pos < text.len) {
                const c = text[pos];
                const next_state = try self.getTransition(current_state, c);

                if (next_state == DEAD_STATE) {
                    // Dead state - can't match from here
                    break;
                }

                current_state = next_state;
                pos += 1;

                // Check if this is a match state
                if (self.states.items[current_state].is_match) {
                    last_match_end = pos; // Greedy matching
                }
            }

            // Did we find a match?
            if (last_match_end) |end| {
                try matches.append(allocator, .{
                    .start = last_match_start,
                    .end = end,
                });
                // Continue searching after this match
                search_start = end;
                if (search_start == last_match_start) {
                    // Empty match, advance by 1 to avoid infinite loop
                    search_start += 1;
                }
            } else {
                // No match found, advance by 1 and try again
                search_start += 1;
            }
        }

        return matches.toOwnedSlice(allocator);
    }

    /// Find all matches using prefix literal scanning (FAST PATH)
    fn findAllWithPrefix(self: *LazyDFA, text: []const u8, allocator: std.mem.Allocator, prefix: []const u8) ![]Match {
        var matches = std.ArrayList(Match){};
        var last_scanned_pos: usize = 0;

        // Find all positions of prefix literal (single or multi-byte)
        var pos: usize = 0;
        while (pos < text.len) {
            const found_pos_opt = if (prefix.len == 1)
                std.mem.indexOfScalarPos(u8, text, pos, prefix[0])
            else
                std.mem.indexOfPos(u8, text, pos, prefix);

            const found_pos = found_pos_opt orelse break;

            // Calculate search window around this prefix
            const window_start = if (found_pos >= self.prefix_window_before)
                found_pos - self.prefix_window_before
            else
                0;
            const window_end = @min(found_pos + self.prefix_window_after + 1, text.len);

            // Only scan positions we haven't scanned yet
            const scan_start = @max(window_start, last_scanned_pos);

            // Try matching from each position in the new window
            var scan_pos = scan_start;
            while (scan_pos < window_end) : (scan_pos += 1) {
                if (try self.findAt(text, scan_pos)) |match| {
                    try matches.append(allocator, match);
                    // Skip to end of this match to avoid overlapping matches
                    scan_pos = match.end - 1;
                    last_scanned_pos = match.end;
                }
            }

            // Update last scanned position
            last_scanned_pos = @max(last_scanned_pos, window_end);

            // Continue searching after this prefix
            pos = found_pos + 1;
        }

        return matches.toOwnedSlice(allocator);
    }

    /// Try to match starting at a specific position
    fn findAt(self: *LazyDFA, text: []const u8, start: usize) !?Match {
        // Initialize DFA if needed
        if (self.states.items.len == 0) {
            try self.initializeDFA();
        }

        var current_state: DfaStateId = START_STATE;
        var match_end: ?usize = null;

        // Check if start state is a match state
        if (self.states.items[current_state].is_match) {
            match_end = start;
        }

        var pos = start;
        while (pos < text.len) : (pos += 1) {
            const c = text[pos];

            // Get or build transition
            const next_state = try self.getTransition(current_state, c);

            if (next_state == DEAD_STATE) {
                // No more matches possible
                break;
            }

            current_state = next_state;

            // Check if this is a match state
            if (self.states.items[current_state].is_match) {
                match_end = pos + 1; // Greedy: keep updating
            }
        }

        if (match_end) |end| {
            return .{ .start = start, .end = end };
        }

        return null;
    }

    /// Initialize DFA with start state
    fn initializeDFA(self: *LazyDFA) !void {
        // Create dead state (state 0)
        const dead_states = try self.allocator.alloc(StateId, 0);
        const dead_state = try DfaState.init(self.allocator, dead_states, false);
        try self.states.append(self.allocator, dead_state);

        // Create start state (state 1) - epsilon closure of NFA start
        var start_nfa_states = std.ArrayList(StateId){};
        try self.epsilonClosure(&start_nfa_states, self.nfa.start);

        const is_match = self.containsMatchState(start_nfa_states.items);
        const start_state = try DfaState.init(self.allocator, start_nfa_states.items, is_match);
        try self.states.append(self.allocator, start_state);

        // Cache start state
        const hash = hashStateSet(start_nfa_states.items);
        try self.state_cache.put(hash, START_STATE);

        start_nfa_states.deinit(self.allocator);
    }

    /// Get or build transition for a DFA state on a byte
    inline fn getTransition(self: *LazyDFA, state_id: DfaStateId, byte: u8) !DfaStateId {
        const state = &self.states.items[state_id];

        // Check cache
        if (state.transitions[byte] != DEAD_STATE or state_id == DEAD_STATE) {
            return state.transitions[byte];
        }

        // Build new DFA state by following NFA transitions
        var next_nfa_states = std.ArrayList(StateId){};
        defer next_nfa_states.deinit(self.allocator);

        for (state.nfa_states) |nfa_state| {
            try self.followByte(&next_nfa_states, nfa_state, byte);
        }

        // If no states reachable, transition to dead state
        if (next_nfa_states.items.len == 0) {
            self.states.items[state_id].transitions[byte] = DEAD_STATE;
            return DEAD_STATE;
        }

        // Sort for consistent hashing
        std.mem.sort(StateId, next_nfa_states.items, {}, comptime std.sort.asc(StateId));

        // Check if this DFA state already exists
        const hash = hashStateSet(next_nfa_states.items);
        if (self.state_cache.get(hash)) |existing_id| {
            self.states.items[state_id].transitions[byte] = existing_id;
            return existing_id;
        }

        // Create new DFA state
        const is_match = self.containsMatchState(next_nfa_states.items);
        const new_dfa_state = try DfaState.init(self.allocator, next_nfa_states.items, is_match);
        const new_id: DfaStateId = @intCast(self.states.items.len);

        try self.states.append(self.allocator, new_dfa_state);
        try self.state_cache.put(hash, new_id);

        // Update transition
        self.states.items[state_id].transitions[byte] = new_id;

        return new_id;
    }

    /// Compute epsilon closure of an NFA state
    fn epsilonClosure(self: *LazyDFA, result: *std.ArrayList(StateId), start_state: StateId) !void {
        var visited = std.AutoHashMap(StateId, void).init(self.allocator);
        defer visited.deinit();

        try self.epsilonClosureHelper(result, &visited, start_state);
    }

    fn epsilonClosureHelper(self: *LazyDFA, result: *std.ArrayList(StateId), visited: *std.AutoHashMap(StateId, void), state_id: StateId) !void {
        if (visited.contains(state_id)) return;
        try visited.put(state_id, {});

        if (state_id == MATCH_STATE) {
            try result.append(self.allocator, state_id);
            return;
        }

        if (state_id >= self.nfa.states.len) return;

        const state = &self.nfa.states[state_id];
        var has_epsilon = false;

        // Check for epsilon transitions
        for (state.transitions) |trans| {
            switch (trans) {
                .epsilon => |target| {
                    has_epsilon = true;
                    try self.epsilonClosureHelper(result, visited, target);
                },
                .split => |s| {
                    has_epsilon = true;
                    for (s.targets) |target| {
                        try self.epsilonClosureHelper(result, visited, target);
                    }
                },
                .start_assert, .end_assert, .word_boundary, .not_word_boundary => {
                    // Assertions don't consume input but we can't handle them in DFA
                    // For now, skip them (this is a simplification)
                    has_epsilon = true;
                },
                else => {},
            }
        }

        // If no epsilon transitions, add this state
        if (!has_epsilon) {
            try result.append(self.allocator, state_id);
        }
    }

    /// Follow a byte transition from an NFA state and compute epsilon closure
    inline fn followByte(self: *LazyDFA, result: *std.ArrayList(StateId), state_id: StateId, byte: u8) !void {
        if (state_id >= self.nfa.states.len) return;

        const state = &self.nfa.states[state_id];

        for (state.transitions) |trans| {
            const matches = switch (trans) {
                .byte => |b| b.value == byte,
                .range => |r| byte >= r.start and byte <= r.end,
                .any => true,
                else => false,
            };

            if (matches) {
                const target = switch (trans) {
                    .byte => |b| b.target,
                    .range => |r| r.target,
                    .any => |t| t,
                    else => continue,
                };

                // Compute epsilon closure of target
                try self.epsilonClosure(result, target);
            }
        }
    }

    /// Check if a set of NFA states contains the match state
    fn containsMatchState(self: *LazyDFA, states: []const StateId) bool {
        _ = self;
        for (states) |state| {
            if (state == MATCH_STATE) return true;
        }
        return false;
    }
};
