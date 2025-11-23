/// Thompson NFA construction from AST
/// Uses sparse states to eliminate epsilon transitions where possible
const std = @import("std");
const ast = @import("ast.zig");
const Expr = ast.Expr;

/// State ID in the NFA
pub const StateId = u32;

/// Special state representing a match
pub const MATCH_STATE: StateId = std.math.maxInt(StateId);

/// Sentinel value for dangling transitions (to be patched)
pub const DANGLING: StateId = std.math.maxInt(StateId) - 1;

/// Transition from one state to another
pub const Transition = union(enum) {
    /// Transition on a specific byte
    byte: struct {
        value: u8,
        target: StateId,
    },

    /// Transition on any byte in a range (inclusive)
    range: struct {
        start: u8,
        end: u8,
        target: StateId,
    },

    /// Transition on any byte (.)
    any: StateId,

    /// Epsilon transition (empty move, no input consumed)
    epsilon: StateId,

    /// Split into multiple states (used for alternation, quantifiers)
    split: struct {
        targets: []StateId,
    },

    /// Start assertion (^) - matches only at text start
    start_assert: StateId,

    /// End assertion ($) - matches only at text end
    end_assert: StateId,

    /// Word boundary assertion (\b) - matches at word boundary
    word_boundary: StateId,

    /// Not word boundary assertion (\B) - matches NOT at word boundary
    not_word_boundary: StateId,

    /// Match state - accept the input
    match: void,
};

/// A state in the NFA
pub const State = struct {
    /// Unique state ID
    id: StateId,

    /// Transitions from this state
    transitions: []Transition,

    /// For capturing groups - which group this state belongs to
    capture_group: ?u32 = null,

    pub fn init(id: StateId, transitions: []Transition) State {
        return .{
            .id = id,
            .transitions = transitions,
        };
    }
};

/// Thompson NFA
pub const NFA = struct {
    /// All states in the NFA
    states: []State,

    /// Start state ID
    start: StateId,

    /// Total number of capturing groups
    num_captures: u32,

    /// Allocator used for construction
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, states: []State, start: StateId, num_captures: u32) NFA {
        return .{
            .states = states,
            .start = start,
            .num_captures = num_captures,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *NFA) void {
        for (self.states) |*state| {
            // Free transitions
            for (state.transitions) |*trans| {
                switch (trans.*) {
                    .split => |s| self.allocator.free(s.targets),
                    else => {},
                }
            }
            self.allocator.free(state.transitions);
        }
        self.allocator.free(self.states);
    }
};

/// NFA Builder - constructs NFA from AST using Thompson's construction
pub const Builder = struct {
    allocator: std.mem.Allocator,
    states: std.ArrayList(State),
    next_state_id: StateId,
    next_capture_group: u32,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{
            .allocator = allocator,
            .states = std.ArrayList(State){},
            .next_state_id = 0,
            .next_capture_group = 0,
        };
    }

    pub fn build(self: *Builder, expr: Expr) !NFA {
        // Build the NFA fragment for the expression
        var frag = try self.compile(expr);
        defer frag.out_states.deinit(self.allocator);

        // Connect the fragment to a match state
        try self.patch(frag.out_states, MATCH_STATE);

        // Convert states ArrayList to owned slice
        const states = try self.states.toOwnedSlice(self.allocator);

        return NFA.init(
            self.allocator,
            states,
            frag.start,
            self.next_capture_group,
        );
    }

    /// Fragment - a piece of NFA with dangling out transitions
    const Fragment = struct {
        start: StateId,
        out_states: std.ArrayList(StateId), // States that need to be patched
    };

    /// Compile an expression into an NFA fragment
    fn compile(self: *Builder, expr: Expr) error{OutOfMemory}!Fragment {
        return switch (expr) {
            .char => |c| try self.compileChar(c),
            .any => try self.compileAny(),
            .digit => try self.compileDigit(),
            .not_digit => try self.compileNotDigit(),
            .word => try self.compileWord(),
            .not_word => try self.compileNotWord(),
            .whitespace => try self.compileWhitespace(),
            .not_whitespace => try self.compileNotWhitespace(),
            .class => |c| try self.compileClass(c),
            .star => |sub| try self.compileStar(sub.*),
            .plus => |sub| try self.compilePlus(sub.*),
            .question => |sub| try self.compileQuestion(sub.*),
            .repeat => |r| try self.compileRepeat(r),
            .concat => |c| try self.compileConcat(c),
            .alt => |a| try self.compileAlt(a),
            .group => |g| try self.compileGroup(g.*),
            .start => try self.compileStart(),
            .end => try self.compileEnd(),
            .word_boundary => try self.compileWordBoundary(),
            .not_word_boundary => try self.compileNotWordBoundary(),
        };
    }

    /// Create a new state with given transitions
    fn newState(self: *Builder, transitions: []Transition) !StateId {
        const id = self.next_state_id;
        self.next_state_id += 1;

        const state = State.init(id, transitions);
        try self.states.append(self.allocator, state);

        return id;
    }

    /// Patch a list of dangling out states to point to a target state
    /// Updates all transitions with target = DANGLING to point to the new target
    fn patch(self: *Builder, out_states: std.ArrayList(StateId), target: StateId) !void {
        for (out_states.items) |state_id| {
            // Find the state in our states list
            const state = &self.states.items[state_id];

            // Update all dangling transitions (target = DANGLING) to point to target
            for (state.transitions) |*trans| {
                switch (trans.*) {
                    .byte => |*b| {
                        if (b.target == DANGLING) {
                            b.target = target;
                        }
                    },
                    .range => |*r| {
                        if (r.target == DANGLING) {
                            r.target = target;
                        }
                    },
                    .any => |*t| {
                        if (t.* == DANGLING) {
                            t.* = target;
                        }
                    },
                    .epsilon => |*t| {
                        if (t.* == DANGLING) {
                            t.* = target;
                        }
                    },
                    .split => |*s| {
                        for (s.targets) |*t| {
                            if (t.* == DANGLING) {
                                t.* = target;
                            }
                        }
                    },
                    .start_assert => |*t| {
                        if (t.* == DANGLING) {
                            t.* = target;
                        }
                    },
                    .end_assert => |*t| {
                        if (t.* == DANGLING) {
                            t.* = target;
                        }
                    },
                    .word_boundary => |*t| {
                        if (t.* == DANGLING) {
                            t.* = target;
                        }
                    },
                    .not_word_boundary => |*t| {
                        if (t.* == DANGLING) {
                            t.* = target;
                        }
                    },
                    .match => {},
                }
            }
        }
    }

    /// Compile a literal character: 'a'
    fn compileChar(self: *Builder, c: u8) !Fragment {
        var out_states: std.ArrayList(StateId) = .{};

        // Create a state that transitions on 'c' to a dangling state
        const trans = try self.allocator.alloc(Transition, 1);
        trans[0] = Transition{ .byte = .{ .value = c, .target = DANGLING } }; // target will be patched

        const state_id = try self.newState(trans);
        try out_states.append(self.allocator, state_id);

        return Fragment{
            .start = state_id,
            .out_states = out_states,
        };
    }

    /// Compile any character: '.'
    fn compileAny(self: *Builder) !Fragment {
        var out_states: std.ArrayList(StateId) = .{};

        const trans = try self.allocator.alloc(Transition, 1);
        trans[0] = Transition{ .any = DANGLING }; // target will be patched

        const state_id = try self.newState(trans);
        try out_states.append(self.allocator, state_id);

        return Fragment{
            .start = state_id,
            .out_states = out_states,
        };
    }

    /// Compile \d (digit)
    fn compileDigit(self: *Builder) !Fragment {
        var out_states: std.ArrayList(StateId) = .{};

        const trans = try self.allocator.alloc(Transition, 1);
        trans[0] = Transition{ .range = .{ .start = '0', .end = '9', .target = DANGLING } };

        const state_id = try self.newState(trans);
        try out_states.append(self.allocator, state_id);

        return Fragment{
            .start = state_id,
            .out_states = out_states,
        };
    }

    /// Compile \D (not digit)
    fn compileNotDigit(self: *Builder) !Fragment {
        // TODO: Implement properly (multiple ranges)
        return try self.compileAny();
    }

    /// Compile \w (word character)
    fn compileWord(self: *Builder) !Fragment {
        // TODO: Implement properly (a-z, A-Z, 0-9, _)
        return try self.compileAny();
    }

    /// Compile \W (not word)
    fn compileNotWord(self: *Builder) !Fragment {
        // TODO: Implement properly
        return try self.compileAny();
    }

    /// Compile \s (whitespace)
    /// Matches: space, tab, newline, carriage return, form feed, vertical tab
    fn compileWhitespace(self: *Builder) !Fragment {
        var out_states: std.ArrayList(StateId) = .{};

        // Python \s matches: [ \t\n\r\f\v]
        const whitespace_chars = [_]u8{ ' ', '\t', '\n', '\r', 12, 11 }; // 12=\f, 11=\v

        const trans = try self.allocator.alloc(Transition, whitespace_chars.len);
        for (whitespace_chars, 0..) |ch, i| {
            trans[i] = Transition{ .byte = .{ .value = ch, .target = DANGLING } };
        }

        const state_id = try self.newState(trans);
        try out_states.append(self.allocator, state_id);

        return Fragment{
            .start = state_id,
            .out_states = out_states,
        };
    }

    /// Compile \S (not whitespace)
    fn compileNotWhitespace(self: *Builder) !Fragment {
        // TODO: Implement properly
        return try self.compileAny();
    }

    /// Compile character class: [abc] or [a-z]
    fn compileClass(self: *Builder, class: Expr.CharClass) !Fragment {
        var out_states: std.ArrayList(StateId) = .{};

        if (class.negated) {
            // Negated class [^abc] - match anything EXCEPT these characters
            // For now, implement as: match any byte that's NOT in the ranges
            // This requires checking all ranges during matching

            // Create transitions for all possible bytes NOT in the ranges
            // This is inefficient but correct - optimization later
            var allowed_bytes: std.ArrayList(u8) = .{};

            for (0..256) |byte_val| {
                const byte: u8 = @intCast(byte_val);
                var in_range = false;

                for (class.ranges) |range| {
                    if (byte >= range.start and byte <= range.end) {
                        in_range = true;
                        break;
                    }
                }

                if (!in_range) {
                    try allowed_bytes.append(self.allocator, byte);
                }
            }

            const trans = try self.allocator.alloc(Transition, allowed_bytes.items.len);
            for (allowed_bytes.items, 0..) |byte, i| {
                trans[i] = Transition{ .byte = .{ .value = byte, .target = DANGLING } };
            }
            allowed_bytes.deinit(self.allocator);

            const state_id = try self.newState(trans);
            try out_states.append(self.allocator, state_id);

            return Fragment{
                .start = state_id,
                .out_states = out_states,
            };
        } else {
            // Positive class [abc] or [a-z] - match any character in the ranges
            const trans = try self.allocator.alloc(Transition, class.ranges.len);

            for (class.ranges, 0..) |range, i| {
                if (range.start == range.end) {
                    // Single character
                    trans[i] = Transition{ .byte = .{ .value = range.start, .target = DANGLING } };
                } else {
                    // Character range
                    trans[i] = Transition{ .range = .{ .start = range.start, .end = range.end, .target = DANGLING } };
                }
            }

            const state_id = try self.newState(trans);
            try out_states.append(self.allocator, state_id);

            return Fragment{
                .start = state_id,
                .out_states = out_states,
            };
        }
    }

    /// Compile e* (zero or more)
    /// Thompson: create split state that either enters e or skips it
    ///           connect e's out back to split (creates loop)
    fn compileStar(self: *Builder, sub: Expr) !Fragment {
        // Build fragment for e
        var e_frag = try self.compile(sub);
        defer e_frag.out_states.deinit(self.allocator);

        // Create split state with two targets: e's start, and out (dangling)
        var split_targets = try self.allocator.alloc(StateId, 2);
        split_targets[0] = e_frag.start; // Enter e
        split_targets[1] = DANGLING; // Skip e (dangling, will be patched)

        const trans = try self.allocator.alloc(Transition, 1);
        trans[0] = Transition{ .split = .{ .targets = split_targets } };

        const split_state = try self.newState(trans);

        // Connect e's out states back to split (creates loop)
        try self.patch(e_frag.out_states, split_state);

        // The star's out state is the split state itself (via the skip path)
        var out_states: std.ArrayList(StateId) = .{};
        try out_states.append(self.allocator, split_state);

        return Fragment{
            .start = split_state,
            .out_states = out_states,
        };
    }

    /// Compile e+ (one or more)
    /// Thompson: e followed by e* (one occurrence, then zero or more)
    fn compilePlus(self: *Builder, sub: Expr) !Fragment {
        // Build fragment for e
        var e_frag = try self.compile(sub);
        defer e_frag.out_states.deinit(self.allocator);

        // Create split state for the loop (like star)
        var split_targets = try self.allocator.alloc(StateId, 2);
        split_targets[0] = e_frag.start; // Loop back to e
        split_targets[1] = DANGLING; // Exit (dangling)

        const trans = try self.allocator.alloc(Transition, 1);
        trans[0] = Transition{ .split = .{ .targets = split_targets } };

        const split_state = try self.newState(trans);

        // Connect e's out to split (creates loop after first match)
        try self.patch(e_frag.out_states, split_state);

        // The plus's out state is split (via exit path)
        var out_states: std.ArrayList(StateId) = .{};
        try out_states.append(self.allocator, split_state);

        return Fragment{
            .start = e_frag.start, // Start at e (must match at least once)
            .out_states = out_states,
        };
    }

    /// Compile e? (zero or one)
    /// Thompson: split state that either enters e or skips it (no loop back)
    fn compileQuestion(self: *Builder, sub: Expr) !Fragment {
        // Build fragment for e
        var e_frag = try self.compile(sub);

        // Create split state: either enter e or skip
        var split_targets = try self.allocator.alloc(StateId, 2);
        split_targets[0] = e_frag.start; // Enter e
        split_targets[1] = DANGLING; // Skip e (dangling)

        const trans = try self.allocator.alloc(Transition, 1);
        trans[0] = Transition{ .split = .{ .targets = split_targets } };

        const split_state = try self.newState(trans);

        // Collect out states: split (skip path) + e's out states
        try e_frag.out_states.append(self.allocator, split_state);

        return Fragment{
            .start = split_state,
            .out_states = e_frag.out_states,
        };
    }

    /// Compile e{n,m} (repeat)
    fn compileRepeat(self: *Builder, repeat: Expr.Repeat) !Fragment {
        // Strategy: Expand repeat to concat of copies
        // e{3} = eee
        // e{2,5} = ee(e)?(e)?(e)?  (2 required + 3 optional)
        // e{2,} = ee(e)*  (2 required + star)

        if (repeat.min == 0 and repeat.max == null) {
            // {0,} is same as *
            return try self.compileStar(repeat.expr.*);
        }

        if (repeat.min == 0 and repeat.max != null and repeat.max.? == 1) {
            // {0,1} is same as ?
            return try self.compileQuestion(repeat.expr.*);
        }

        // Build fragments array
        var fragments: std.ArrayList(Fragment) = .{};
        errdefer {
            for (fragments.items) |*frag| {
                frag.out_states.deinit(self.allocator);
            }
            fragments.deinit(self.allocator);
        }

        // Add minimum required copies
        for (0..repeat.min) |_| {
            const frag = try self.compile(repeat.expr.*);
            try fragments.append(self.allocator, frag);
        }

        // Add optional copies if bounded
        if (repeat.max) |max| {
            if (max > repeat.min) {
                // Add (max - min) optional copies (each wrapped in ?)
                for (repeat.min..max) |_| {
                    const frag = try self.compileQuestion(repeat.expr.*);
                    try fragments.append(self.allocator, frag);
                }
            }
        } else {
            // Unbounded: add one * copy
            const frag = try self.compileStar(repeat.expr.*);
            try fragments.append(self.allocator, frag);
        }

        // If only one fragment, return it
        if (fragments.items.len == 1) {
            const result = fragments.items[0];
            fragments.deinit(self.allocator);
            return result;
        }

        // Concatenate all fragments
        var result = fragments.items[0];
        for (fragments.items[1..]) |frag| {
            // Connect result's out to frag's start
            try self.patch(result.out_states, frag.start);
            result.out_states.deinit(self.allocator);
            result.out_states = frag.out_states;
        }

        fragments.deinit(self.allocator);
        return result;
    }

    /// Compile e1 e2 e3 (concatenation)
    /// Thompson: connect e1's out to e2's start, e2's out to e3's start, etc.
    fn compileConcat(self: *Builder, concat: Expr.Concat) !Fragment {
        if (concat.exprs.len == 0) {
            // Empty concatenation - should not happen, but handle gracefully
            return try self.compileChar(0); // Empty match
        }

        // Build first fragment
        var result = try self.compile(concat.exprs[0]);

        // Connect each subsequent fragment
        for (concat.exprs[1..]) |expr| {
            const next_frag = try self.compile(expr);

            // Connect result's out states to next_frag's start
            try self.patch(result.out_states, next_frag.start);
            result.out_states.deinit(self.allocator);

            // Update result to use next_frag's out states
            result.out_states = next_frag.out_states;
            // Keep result.start the same (start of the whole concat)
        }

        return result;
    }

    /// Compile e1 | e2 | e3 (alternation)
    /// Thompson: create split state that branches to each alternative
    fn compileAlt(self: *Builder, alt: Expr.Alt) !Fragment {
        if (alt.exprs.len == 0) {
            // Empty alternation - should not happen
            return try self.compileChar(0);
        }

        if (alt.exprs.len == 1) {
            // Single alternative - just compile it directly
            return try self.compile(alt.exprs[0]);
        }

        // Build fragments for all alternatives
        var fragments = try self.allocator.alloc(Fragment, alt.exprs.len);
        defer self.allocator.free(fragments);

        var all_out_states: std.ArrayList(StateId) = .{};
        errdefer all_out_states.deinit(self.allocator);

        for (alt.exprs, 0..) |expr, i| {
            fragments[i] = try self.compile(expr);

            // Collect all out states from this fragment
            try all_out_states.appendSlice(self.allocator, fragments[i].out_states.items);
            fragments[i].out_states.deinit(self.allocator);
        }

        // Create split state with epsilon transitions to all start states
        var split_targets = try self.allocator.alloc(StateId, alt.exprs.len);
        for (fragments, 0..) |frag, i| {
            split_targets[i] = frag.start;
        }

        const trans = try self.allocator.alloc(Transition, 1);
        trans[0] = Transition{ .split = .{ .targets = split_targets } };

        const split_state = try self.newState(trans);

        return Fragment{
            .start = split_state,
            .out_states = all_out_states,
        };
    }

    /// Compile (e) (capturing group)
    fn compileGroup(self: *Builder, expr: Expr) !Fragment {
        _ = expr;
        // TODO: Implement with capture group tracking
        return try self.compileAny();
    }

    /// Compile ^ (start anchor)
    fn compileStart(self: *Builder) !Fragment {
        var out_states: std.ArrayList(StateId) = .{};

        const trans = try self.allocator.alloc(Transition, 1);
        trans[0] = Transition{ .start_assert = DANGLING };

        const state_id = try self.newState(trans);
        try out_states.append(self.allocator, state_id);

        return Fragment{
            .start = state_id,
            .out_states = out_states,
        };
    }

    /// Compile $ (end anchor)
    fn compileEnd(self: *Builder) !Fragment {
        var out_states: std.ArrayList(StateId) = .{};

        const trans = try self.allocator.alloc(Transition, 1);
        trans[0] = Transition{ .end_assert = DANGLING };

        const state_id = try self.newState(trans);
        try out_states.append(self.allocator, state_id);

        return Fragment{
            .start = state_id,
            .out_states = out_states,
        };
    }

    /// Compile \b (word boundary)
    fn compileWordBoundary(self: *Builder) !Fragment {
        var out_states: std.ArrayList(StateId) = .{};

        const trans = try self.allocator.alloc(Transition, 1);
        trans[0] = Transition{ .word_boundary = DANGLING };

        const state_id = try self.newState(trans);
        try out_states.append(self.allocator, state_id);

        return Fragment{
            .start = state_id,
            .out_states = out_states,
        };
    }

    /// Compile \B (not word boundary)
    fn compileNotWordBoundary(self: *Builder) !Fragment {
        var out_states: std.ArrayList(StateId) = .{};

        const trans = try self.allocator.alloc(Transition, 1);
        trans[0] = Transition{ .not_word_boundary = DANGLING };

        const state_id = try self.newState(trans);
        try out_states.append(self.allocator, state_id);

        return Fragment{
            .start = state_id,
            .out_states = out_states,
        };
    }
};

// Tests
test "build simple NFA" {
    const allocator = std.testing.allocator;

    var builder = Builder.init(allocator);
    defer builder.states.deinit(allocator);

    const expr = Expr{ .char = 'a' };

    var nfa = try builder.build(expr);
    defer nfa.deinit();

    try std.testing.expect(nfa.states.len > 0);
}

test "build concatenation NFA" {
    const allocator = std.testing.allocator;

    var builder = Builder.init(allocator);
    defer builder.states.deinit(allocator);

    // Build "abc"
    const exprs = try allocator.alloc(Expr, 3);
    defer allocator.free(exprs);
    exprs[0] = Expr{ .char = 'a' };
    exprs[1] = Expr{ .char = 'b' };
    exprs[2] = Expr{ .char = 'c' };

    const expr = Expr{ .concat = .{ .exprs = exprs } };

    var nfa = try builder.build(expr);
    defer nfa.deinit();

    // Should have multiple states for a, b, c
    try std.testing.expect(nfa.states.len >= 3);
}

test "build alternation NFA" {
    const allocator = std.testing.allocator;

    var builder = Builder.init(allocator);
    defer builder.states.deinit(allocator);

    // Build "a|b"
    const exprs = try allocator.alloc(Expr, 2);
    defer allocator.free(exprs);
    exprs[0] = Expr{ .char = 'a' };
    exprs[1] = Expr{ .char = 'b' };

    const expr = Expr{ .alt = .{ .exprs = exprs } };

    var nfa = try builder.build(expr);
    defer nfa.deinit();

    // Should have split state plus states for a and b
    try std.testing.expect(nfa.states.len >= 3);
}
