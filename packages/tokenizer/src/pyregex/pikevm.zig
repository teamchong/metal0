/// Pike VM - NFA execution engine
/// Simulates Thompson NFA with O(n×m) time complexity
/// Based on Russ Cox / Rob Pike's algorithm
const std = @import("std");
const nfa = @import("nfa.zig");
const NFA = nfa.NFA;
const StateId = nfa.StateId;
const Transition = nfa.Transition;
const MATCH_STATE = nfa.MATCH_STATE;

/// Maximum number of capturing groups supported
pub const MAX_CAPTURES = 32;

/// Check if a character is a word character: [a-zA-Z0-9_]
fn isWordChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
           (c >= 'A' and c <= 'Z') or
           (c >= '0' and c <= '9') or
           c == '_';
}

/// Check if position is at a word boundary
fn isAtWordBoundary(text: []const u8, pos: usize) bool {
    const before_is_word = if (pos == 0) false else isWordChar(text[pos - 1]);
    const after_is_word = if (pos >= text.len) false else isWordChar(text[pos]);

    // Boundary if one side is word char and other isn't
    return before_is_word != after_is_word;
}

/// Span representing a captured substring
pub const Span = struct {
    start: usize,
    end: usize,

    pub fn init(start: usize, end: usize) Span {
        return .{ .start = start, .end = end };
    }
};

/// Match result
pub const Match = struct {
    /// Overall match span
    span: Span,
    /// Captured group spans (0 = full match, 1+ = groups)
    captures: []Span,

    pub fn deinit(self: *Match, allocator: std.mem.Allocator) void {
        allocator.free(self.captures);
    }
};

/// Thread - represents one execution path through the NFA
const Thread = struct {
    /// Current state in the NFA
    state: StateId,
    /// Captured group spans
    captures: [MAX_CAPTURES]Span,

    pub fn init(state: StateId) Thread {
        var t = Thread{
            .state = state,
            .captures = undefined,
        };
        // Initialize all captures to invalid spans
        for (&t.captures) |*cap| {
            cap.* = Span.init(0, 0);
        }
        return t;
    }

    pub fn clone(self: *const Thread) Thread {
        return Thread{
            .state = self.state,
            .captures = self.captures,
        };
    }
};

/// Thread list using sparse set for O(1) duplicate detection
const ThreadList = struct {
    /// Active threads
    threads: std.ArrayList(Thread),
    /// Sparse array: state_id -> index in dense
    sparse: []u32,
    /// Dense array: active state IDs
    dense: []StateId,
    /// Number of active states
    len: usize,
    /// Allocator
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, num_states: usize) !ThreadList {
        const sparse = try allocator.alloc(u32, num_states);
        @memset(sparse, 0);

        const dense = try allocator.alloc(StateId, num_states);

        return .{
            .threads = std.ArrayList(Thread){},
            .sparse = sparse,
            .dense = dense,
            .len = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ThreadList) void {
        self.threads.deinit(self.allocator);
        self.allocator.free(self.sparse);
        self.allocator.free(self.dense);
    }

    pub fn clear(self: *ThreadList) void {
        self.threads.clearRetainingCapacity();
        self.len = 0;
    }

    /// Check if state is already in the list (O(1))
    pub fn contains(self: *const ThreadList, state: StateId) bool {
        if (state >= self.sparse.len) return false;
        const idx = self.sparse[state];
        return idx < self.len and self.dense[idx] == state;
    }

    /// Add thread to list (with deduplication)
    pub fn add(self: *ThreadList, thread: Thread) !void {
        // Special handling for MATCH_STATE
        if (thread.state == MATCH_STATE) {
            // Always add match states (they don't need deduplication)
            try self.threads.append(self.allocator, thread);
            return;
        }

        if (self.contains(thread.state)) {
            // Already have a thread at this state
            return;
        }

        // Add to sparse set
        self.sparse[thread.state] = @intCast(self.len);
        self.dense[self.len] = thread.state;
        self.len += 1;

        // Add thread
        try self.threads.append(self.allocator, thread);
    }
};

/// Pike VM execution engine
pub const PikeVM = struct {
    nfa: *const NFA,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, nfa_ptr: *const NFA) PikeVM {
        return .{
            .nfa = nfa_ptr,
            .allocator = allocator,
        };
    }

    /// Find first match in text
    pub fn find(self: *PikeVM, text: []const u8) !?Match {
        // Try matching at each starting position
        var start: usize = 0;
        while (start <= text.len) : (start += 1) {
            if (try self.findAt(text, start)) |match| {
                return match;
            }
        }
        return null;
    }

    /// Try to match starting at a specific position
    fn findAt(self: *PikeVM, text: []const u8, start: usize) !?Match {
        var current = try ThreadList.init(self.allocator, self.nfa.states.len);
        defer current.deinit();

        var next = try ThreadList.init(self.allocator, self.nfa.states.len);
        defer next.deinit();

        // Initialize with start state
        var initial_thread = Thread.init(self.nfa.start);
        initial_thread.captures[0] = Span.init(start, start);
        try self.addThread(&current, initial_thread, text, start);

        // Track best match (for greedy behavior)
        var best_match: ?Match = null;
        var best_pos: usize = start;

        // Process each character
        var pos = start;
        while (pos <= text.len) : (pos += 1) {
            // Check if any thread reached match state
            for (current.threads.items) |thread| {
                if (thread.state == MATCH_STATE) {
                    // Found a match at this position
                    // Keep it if it's the first match OR longer than current best (greedy)
                    if (best_match == null or pos > best_pos) {
                        // Free old match if any
                        if (best_match) |*old| {
                            old.deinit(self.allocator);
                        }

                        var captures = try self.allocator.alloc(Span, self.nfa.num_captures + 1);
                        @memcpy(captures, thread.captures[0..self.nfa.num_captures + 1]);

                        captures[0].end = pos; // Update full match end

                        best_match = Match{
                            .span = captures[0],
                            .captures = captures,
                        };
                        best_pos = pos;
                    }
                }
            }

            // End of input
            if (pos == text.len) break;

            // Step: consume one character
            const c = text[pos];
            next.clear();

            for (current.threads.items) |thread| {
                try self.step(&next, thread, c, text, pos + 1);
            }

            // If no active threads, return best match found so far
            if (next.threads.items.len == 0) {
                return best_match;
            }

            // Swap lists
            const tmp = current;
            current = next;
            next = tmp;
        }

        return best_match;
    }

    /// Add thread with epsilon closure
    fn addThread(self: *PikeVM, list: *ThreadList, thread: Thread, text: []const u8, pos: usize) error{OutOfMemory}!void {
        // Check if already processed
        if (list.contains(thread.state)) {
            return;
        }

        // Handle special states
        if (thread.state == MATCH_STATE) {
            try list.add(thread);
            return;
        }

        if (thread.state >= self.nfa.states.len) {
            // Invalid state
            return;
        }

        const state = &self.nfa.states[thread.state];

        // Check if this is an epsilon state (split, epsilon, or assertion transitions)
        var has_epsilon = false;
        for (state.transitions) |trans| {
            switch (trans) {
                .epsilon, .split, .start_assert, .end_assert, .word_boundary, .not_word_boundary => {
                    has_epsilon = true;
                    break;
                },
                else => {},
            }
        }

        if (has_epsilon) {
            // Follow epsilon transitions recursively (don't add this state)
            for (state.transitions) |trans| {
                switch (trans) {
                    .epsilon => |target| {
                        var new_thread = thread.clone();
                        new_thread.state = target;
                        try self.addThread(list, new_thread, text, pos);
                    },
                    .split => |s| {
                        // Try all branches
                        for (s.targets) |target| {
                            var new_thread = thread.clone();
                            new_thread.state = target;
                            try self.addThread(list, new_thread, text, pos);
                        }
                    },
                    .start_assert => |target| {
                        // ^ matches only at text start
                        if (pos == 0) {
                            var new_thread = thread.clone();
                            new_thread.state = target;
                            try self.addThread(list, new_thread, text, pos);
                        }
                    },
                    .end_assert => |target| {
                        // $ matches only at text end
                        if (pos == text.len) {
                            var new_thread = thread.clone();
                            new_thread.state = target;
                            try self.addThread(list, new_thread, text, pos);
                        }
                    },
                    .word_boundary => |target| {
                        // \b matches at word boundary
                        if (isAtWordBoundary(text, pos)) {
                            var new_thread = thread.clone();
                            new_thread.state = target;
                            try self.addThread(list, new_thread, text, pos);
                        }
                    },
                    .not_word_boundary => |target| {
                        // \B matches NOT at word boundary
                        if (!isAtWordBoundary(text, pos)) {
                            var new_thread = thread.clone();
                            new_thread.state = target;
                            try self.addThread(list, new_thread, text, pos);
                        }
                    },
                    else => {},
                }
            }
        } else {
            // Non-epsilon state, add to thread list
            try list.add(thread);
        }
    }

    /// Step: process one character
    fn step(self: *PikeVM, next: *ThreadList, thread: Thread, c: u8, text: []const u8, next_pos: usize) !void {
        if (thread.state >= self.nfa.states.len) return;

        const state = &self.nfa.states[thread.state];

        for (state.transitions) |trans| {
            const matches = switch (trans) {
                .byte => |b| b.value == c,
                .range => |r| c >= r.start and c <= r.end,
                .any => true,
                else => false,
            };

            if (matches) {
                // Get target state
                const target = switch (trans) {
                    .byte => |b| b.target,
                    .range => |r| r.target,
                    .any => |t| t,
                    else => continue,
                };

                var new_thread = thread.clone();
                new_thread.state = target;
                new_thread.captures[0].end = next_pos; // Update match end

                try self.addThread(next, new_thread, text, next_pos);
            }
        }
    }
};

// Tests
test "PikeVM simple match" {
    const allocator = std.testing.allocator;
    const ast = @import("ast.zig");
    const Expr = ast.Expr;

    // Build NFA for 'a'
    var builder = nfa.Builder.init(allocator);
    defer builder.states.deinit(allocator);

    const expr = Expr{ .char = 'a' };
    var nfa_instance = try builder.build(expr);
    defer nfa_instance.deinit();

    // Test matching
    var vm = PikeVM.init(allocator, &nfa_instance);

    const result = try vm.find("a");
    try std.testing.expect(result != null);

    var match = result.?;
    defer match.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), match.span.start);
    try std.testing.expectEqual(@as(usize, 1), match.span.end);
}

test "PikeVM no match" {
    const allocator = std.testing.allocator;
    const ast = @import("ast.zig");
    const Expr = ast.Expr;

    // Build NFA for 'a'
    var builder = nfa.Builder.init(allocator);
    defer builder.states.deinit(allocator);

    const expr = Expr{ .char = 'a' };
    var nfa_instance = try builder.build(expr);
    defer nfa_instance.deinit();

    // Test non-matching
    var vm = PikeVM.init(allocator, &nfa_instance);

    const result = try vm.find("b");
    try std.testing.expect(result == null);
}
