//! test.test_peg_generator.test_lookahead - Lookahead handling tests
//!
//! This module tests PEG lookahead operators including positive lookahead (&),
//! negative lookahead (!), and cut operators for committed choice.

const std = @import("std");

/// Result of a lookahead check
pub const LookaheadResult = enum {
    success,
    failure,
    cut_failure, // Failure that prevents backtracking
};

/// Types of lookahead predicates
pub const LookaheadType = enum {
    positive, // & - succeeds if pattern matches, doesn't consume
    negative, // ! - succeeds if pattern doesn't match, doesn't consume
    cut, // ~ - commits to current alternative

    pub fn symbol(self: LookaheadType) []const u8 {
        return switch (self) {
            .positive => "&",
            .negative => "!",
            .cut => "~",
        };
    }
};

/// Lookahead predicate with pattern
pub const LookaheadPredicate = struct {
    lookahead_type: LookaheadType,
    pattern: Pattern,
    position: usize,

    pub const Pattern = union(enum) {
        literal: []const u8,
        char_class: CharClass,
        rule_ref: []const u8,
        any_char: void,
        eof: void,

        pub fn describe(self: Pattern) []const u8 {
            return switch (self) {
                .literal => |s| s,
                .char_class => "[...]",
                .rule_ref => |r| r,
                .any_char => ".",
                .eof => "EOF",
            };
        }
    };

    pub const CharClass = struct {
        ranges: []const CharRange,
        negated: bool,

        pub const CharRange = struct {
            start: u8,
            end: u8,
        };
    };

    pub fn init(lookahead_type: LookaheadType, pattern: Pattern, position: usize) LookaheadPredicate {
        return .{
            .lookahead_type = lookahead_type,
            .pattern = pattern,
            .position = position,
        };
    }
};

/// State for lookahead evaluation
pub const LookaheadState = struct {
    input: []const u8,
    position: usize,
    cut_active: bool,
    depth: usize,
    max_depth: usize,

    pub fn init(input: []const u8) LookaheadState {
        return .{
            .input = input,
            .position = 0,
            .cut_active = false,
            .depth = 0,
            .max_depth = 100,
        };
    }

    pub fn atEnd(self: LookaheadState) bool {
        return self.position >= self.input.len;
    }

    pub fn peek(self: LookaheadState) ?u8 {
        if (self.atEnd()) return null;
        return self.input[self.position];
    }

    pub fn peekN(self: LookaheadState, n: usize) ?[]const u8 {
        if (self.position + n > self.input.len) return null;
        return self.input[self.position .. self.position + n];
    }

    pub fn advance(self: *LookaheadState) void {
        if (!self.atEnd()) {
            self.position += 1;
        }
    }

    pub fn advanceN(self: *LookaheadState, n: usize) void {
        self.position = @min(self.position + n, self.input.len);
    }

    pub fn save(self: LookaheadState) LookaheadState {
        return self;
    }

    pub fn restore(self: *LookaheadState, saved: LookaheadState) void {
        self.position = saved.position;
        // Note: cut_active is NOT restored
    }
};

/// Evaluator for lookahead predicates
pub const LookaheadEvaluator = struct {
    state: *LookaheadState,

    pub fn init(state: *LookaheadState) LookaheadEvaluator {
        return .{ .state = state };
    }

    pub fn evaluate(self: *LookaheadEvaluator, predicate: LookaheadPredicate) LookaheadResult {
        const saved = self.state.save();

        const match_result = self.matchPattern(predicate.pattern);

        // Restore position for lookahead (doesn't consume input)
        if (predicate.lookahead_type != .cut) {
            self.state.restore(saved);
        }

        return switch (predicate.lookahead_type) {
            .positive => if (match_result) .success else .failure,
            .negative => if (match_result) .failure else .success,
            .cut => blk: {
                if (match_result) {
                    self.state.cut_active = true;
                    break :blk .success;
                }
                break :blk .cut_failure;
            },
        };
    }

    fn matchPattern(self: *LookaheadEvaluator, pattern: LookaheadPredicate.Pattern) bool {
        return switch (pattern) {
            .literal => |lit| self.matchLiteral(lit),
            .char_class => |cc| self.matchCharClass(cc),
            .any_char => self.matchAnyChar(),
            .eof => self.state.atEnd(),
            .rule_ref => true, // Would need grammar context to evaluate
        };
    }

    fn matchLiteral(self: *LookaheadEvaluator, literal: []const u8) bool {
        const actual = self.state.peekN(literal.len) orelse return false;
        if (std.mem.eql(u8, actual, literal)) {
            self.state.advanceN(literal.len);
            return true;
        }
        return false;
    }

    fn matchCharClass(self: *LookaheadEvaluator, cc: LookaheadPredicate.CharClass) bool {
        const c = self.state.peek() orelse return cc.negated;

        var matched = false;
        for (cc.ranges) |range| {
            if (c >= range.start and c <= range.end) {
                matched = true;
                break;
            }
        }

        const result = if (cc.negated) !matched else matched;
        if (result) {
            self.state.advance();
        }
        return result;
    }

    fn matchAnyChar(self: *LookaheadEvaluator) bool {
        if (self.state.atEnd()) return false;
        self.state.advance();
        return true;
    }
};

/// Lookahead combinator for complex lookahead expressions
pub const LookaheadCombinator = struct {
    predicates: std.ArrayList(LookaheadPredicate),
    allocator: std.mem.Allocator,

    pub const Mode = enum {
        all, // All predicates must succeed
        any, // At least one predicate must succeed
        sequence, // Predicates are evaluated in order
    };

    pub fn init(allocator: std.mem.Allocator) LookaheadCombinator {
        return .{
            .predicates = std.ArrayList(LookaheadPredicate).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LookaheadCombinator) void {
        self.predicates.deinit();
    }

    pub fn addPredicate(self: *LookaheadCombinator, predicate: LookaheadPredicate) !void {
        try self.predicates.append(predicate);
    }

    pub fn positive(self: *LookaheadCombinator, pattern: LookaheadPredicate.Pattern) !void {
        try self.addPredicate(.{
            .lookahead_type = .positive,
            .pattern = pattern,
            .position = 0,
        });
    }

    pub fn negative(self: *LookaheadCombinator, pattern: LookaheadPredicate.Pattern) !void {
        try self.addPredicate(.{
            .lookahead_type = .negative,
            .pattern = pattern,
            .position = 0,
        });
    }

    pub fn cut(self: *LookaheadCombinator, pattern: LookaheadPredicate.Pattern) !void {
        try self.addPredicate(.{
            .lookahead_type = .cut,
            .pattern = pattern,
            .position = 0,
        });
    }

    pub fn evaluate(self: LookaheadCombinator, state: *LookaheadState, mode: Mode) LookaheadResult {
        var evaluator = LookaheadEvaluator.init(state);

        return switch (mode) {
            .all => self.evaluateAll(&evaluator),
            .any => self.evaluateAny(&evaluator),
            .sequence => self.evaluateSequence(&evaluator),
        };
    }

    fn evaluateAll(self: LookaheadCombinator, evaluator: *LookaheadEvaluator) LookaheadResult {
        for (self.predicates.items) |pred| {
            const result = evaluator.evaluate(pred);
            if (result != .success) return result;
        }
        return .success;
    }

    fn evaluateAny(self: LookaheadCombinator, evaluator: *LookaheadEvaluator) LookaheadResult {
        var has_cut_failure = false;
        for (self.predicates.items) |pred| {
            const result = evaluator.evaluate(pred);
            if (result == .success) return .success;
            if (result == .cut_failure) has_cut_failure = true;
        }
        return if (has_cut_failure) .cut_failure else .failure;
    }

    fn evaluateSequence(self: LookaheadCombinator, evaluator: *LookaheadEvaluator) LookaheadResult {
        return self.evaluateAll(evaluator);
    }

    pub fn count(self: LookaheadCombinator) usize {
        return self.predicates.items.len;
    }
};

// Tests
test "lookahead_type_symbols" {
    try std.testing.expectEqualStrings("&", LookaheadType.positive.symbol());
    try std.testing.expectEqualStrings("!", LookaheadType.negative.symbol());
    try std.testing.expectEqualStrings("~", LookaheadType.cut.symbol());
}

test "lookahead_state_basic" {
    var state = LookaheadState.init("hello");
    try std.testing.expect(!state.atEnd());
    try std.testing.expectEqual(@as(?u8, 'h'), state.peek());
}

test "lookahead_state_advance" {
    var state = LookaheadState.init("abc");
    state.advance();
    try std.testing.expectEqual(@as(?u8, 'b'), state.peek());
    state.advance();
    try std.testing.expectEqual(@as(?u8, 'c'), state.peek());
    state.advance();
    try std.testing.expect(state.atEnd());
}

test "lookahead_state_peek_n" {
    var state = LookaheadState.init("hello world");
    try std.testing.expectEqualStrings("hello", state.peekN(5).?);
    try std.testing.expect(state.peekN(100) == null);
}

test "lookahead_state_save_restore" {
    var state = LookaheadState.init("abcdef");
    state.advance();
    state.advance();

    const saved = state.save();
    state.advance();
    state.advance();

    try std.testing.expectEqual(@as(usize, 4), state.position);
    state.restore(saved);
    try std.testing.expectEqual(@as(usize, 2), state.position);
}

test "positive_lookahead_success" {
    var state = LookaheadState.init("hello world");
    var evaluator = LookaheadEvaluator.init(&state);

    const pred = LookaheadPredicate.init(.positive, .{ .literal = "hello" }, 0);
    const result = evaluator.evaluate(pred);

    try std.testing.expect(result == .success);
    try std.testing.expectEqual(@as(usize, 0), state.position); // Position unchanged
}

test "positive_lookahead_failure" {
    var state = LookaheadState.init("hello world");
    var evaluator = LookaheadEvaluator.init(&state);

    const pred = LookaheadPredicate.init(.positive, .{ .literal = "world" }, 0);
    const result = evaluator.evaluate(pred);

    try std.testing.expect(result == .failure);
}

test "negative_lookahead_success" {
    var state = LookaheadState.init("hello world");
    var evaluator = LookaheadEvaluator.init(&state);

    const pred = LookaheadPredicate.init(.negative, .{ .literal = "world" }, 0);
    const result = evaluator.evaluate(pred);

    try std.testing.expect(result == .success);
}

test "negative_lookahead_failure" {
    var state = LookaheadState.init("hello world");
    var evaluator = LookaheadEvaluator.init(&state);

    const pred = LookaheadPredicate.init(.negative, .{ .literal = "hello" }, 0);
    const result = evaluator.evaluate(pred);

    try std.testing.expect(result == .failure);
}

test "lookahead_any_char" {
    var state = LookaheadState.init("x");
    var evaluator = LookaheadEvaluator.init(&state);

    const pred = LookaheadPredicate.init(.positive, .{ .any_char = {} }, 0);
    const result = evaluator.evaluate(pred);

    try std.testing.expect(result == .success);
}

test "lookahead_eof_success" {
    var state = LookaheadState.init("");
    var evaluator = LookaheadEvaluator.init(&state);

    const pred = LookaheadPredicate.init(.positive, .{ .eof = {} }, 0);
    const result = evaluator.evaluate(pred);

    try std.testing.expect(result == .success);
}

test "lookahead_eof_failure" {
    var state = LookaheadState.init("x");
    var evaluator = LookaheadEvaluator.init(&state);

    const pred = LookaheadPredicate.init(.positive, .{ .eof = {} }, 0);
    const result = evaluator.evaluate(pred);

    try std.testing.expect(result == .failure);
}

test "lookahead_char_class" {
    var state = LookaheadState.init("5abc");
    var evaluator = LookaheadEvaluator.init(&state);

    const digit_class = LookaheadPredicate.CharClass{
        .ranges = &[_]LookaheadPredicate.CharClass.CharRange{.{ .start = '0', .end = '9' }},
        .negated = false,
    };

    const pred = LookaheadPredicate.init(.positive, .{ .char_class = digit_class }, 0);
    const result = evaluator.evaluate(pred);

    try std.testing.expect(result == .success);
}

test "lookahead_char_class_negated" {
    var state = LookaheadState.init("abc");
    var evaluator = LookaheadEvaluator.init(&state);

    const not_digit = LookaheadPredicate.CharClass{
        .ranges = &[_]LookaheadPredicate.CharClass.CharRange{.{ .start = '0', .end = '9' }},
        .negated = true,
    };

    const pred = LookaheadPredicate.init(.positive, .{ .char_class = not_digit }, 0);
    const result = evaluator.evaluate(pred);

    try std.testing.expect(result == .success);
}

test "cut_lookahead" {
    var state = LookaheadState.init("hello");
    var evaluator = LookaheadEvaluator.init(&state);

    try std.testing.expect(!state.cut_active);

    const pred = LookaheadPredicate.init(.cut, .{ .literal = "hello" }, 0);
    const result = evaluator.evaluate(pred);

    try std.testing.expect(result == .success);
    try std.testing.expect(state.cut_active);
}

test "cut_lookahead_failure" {
    var state = LookaheadState.init("hello");
    var evaluator = LookaheadEvaluator.init(&state);

    const pred = LookaheadPredicate.init(.cut, .{ .literal = "world" }, 0);
    const result = evaluator.evaluate(pred);

    try std.testing.expect(result == .cut_failure);
}

test "lookahead_combinator_positive" {
    var combinator = LookaheadCombinator.init(std.testing.allocator);
    defer combinator.deinit();

    try combinator.positive(.{ .literal = "foo" });
    try std.testing.expectEqual(@as(usize, 1), combinator.count());
}

test "lookahead_combinator_all_mode" {
    var combinator = LookaheadCombinator.init(std.testing.allocator);
    defer combinator.deinit();

    try combinator.positive(.{ .literal = "h" });
    try combinator.positive(.{ .literal = "h" }); // Same position, same result

    var state = LookaheadState.init("hello");
    const result = combinator.evaluate(&state, .all);

    try std.testing.expect(result == .success);
}

test "lookahead_combinator_any_mode" {
    var combinator = LookaheadCombinator.init(std.testing.allocator);
    defer combinator.deinit();

    try combinator.positive(.{ .literal = "world" }); // Will fail
    try combinator.positive(.{ .literal = "hello" }); // Will succeed

    var state = LookaheadState.init("hello");
    const result = combinator.evaluate(&state, .any);

    try std.testing.expect(result == .success);
}

test "pattern_describe" {
    const lit = LookaheadPredicate.Pattern{ .literal = "test" };
    try std.testing.expectEqualStrings("test", lit.describe());

    const any = LookaheadPredicate.Pattern{ .any_char = {} };
    try std.testing.expectEqualStrings(".", any.describe());

    const eof = LookaheadPredicate.Pattern{ .eof = {} };
    try std.testing.expectEqualStrings("EOF", eof.describe());
}

test "lookahead_predicate_init" {
    const pred = LookaheadPredicate.init(.positive, .{ .literal = "test" }, 5);
    try std.testing.expect(pred.lookahead_type == .positive);
    try std.testing.expectEqual(@as(usize, 5), pred.position);
}
