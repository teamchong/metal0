//! test.test_peg_generator.test_parser - Parser generation and parsing tests
//!
//! This module tests the core parser functionality including parse state management,
//! backtracking, and result handling for PEG parsers.

const std = @import("std");

/// Result of a parse attempt
pub const ParseResult = union(enum) {
    success: ParseSuccess,
    failure: ParseFailure,

    pub fn isSuccess(self: ParseResult) bool {
        return self == .success;
    }

    pub fn getPosition(self: ParseResult) usize {
        return switch (self) {
            .success => |s| s.end_pos,
            .failure => |f| f.position,
        };
    }
};

/// Successful parse result with captured value
pub const ParseSuccess = struct {
    value: ParseValue,
    start_pos: usize,
    end_pos: usize,

    pub fn span(self: ParseSuccess) usize {
        return self.end_pos - self.start_pos;
    }
};

/// Parse failure with error information
pub const ParseFailure = struct {
    position: usize,
    expected: []const u8,
    found: ?u8,
    rule_name: []const u8,

    pub fn format(self: ParseFailure, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "Parse error at position {d}: expected '{s}', found '{?c}' in rule '{s}'", .{
            self.position,
            self.expected,
            self.found,
            self.rule_name,
        });
    }
};

/// Value captured during parsing
pub const ParseValue = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    list: []const ParseValue,
    node: *ParseNode,
    none: void,

    pub fn asString(self: ParseValue) ?[]const u8 {
        return if (self == .string) self.string else null;
    }

    pub fn asInt(self: ParseValue) ?i64 {
        return if (self == .integer) self.integer else null;
    }

    pub fn asList(self: ParseValue) ?[]const ParseValue {
        return if (self == .list) self.list else null;
    }
};

/// AST node produced by parser
pub const ParseNode = struct {
    rule_name: []const u8,
    children: []const ParseValue,
    start_pos: usize,
    end_pos: usize,
};

/// Parser state for tracking position and backtracking
pub const ParserState = struct {
    input: []const u8,
    position: usize,
    line: usize,
    column: usize,
    marks: std.ArrayList(Mark),
    allocator: std.mem.Allocator,

    pub const Mark = struct {
        position: usize,
        line: usize,
        column: usize,
    };

    pub fn init(allocator: std.mem.Allocator, input: []const u8) ParserState {
        return .{
            .input = input,
            .position = 0,
            .line = 1,
            .column = 1,
            .marks = std.ArrayList(Mark).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ParserState) void {
        self.marks.deinit();
    }

    pub fn isEof(self: ParserState) bool {
        return self.position >= self.input.len;
    }

    pub fn peek(self: ParserState) ?u8 {
        if (self.isEof()) return null;
        return self.input[self.position];
    }

    pub fn peekN(self: ParserState, n: usize) ?[]const u8 {
        if (self.position + n > self.input.len) return null;
        return self.input[self.position .. self.position + n];
    }

    pub fn advance(self: *ParserState) ?u8 {
        if (self.isEof()) return null;
        const c = self.input[self.position];
        self.position += 1;
        if (c == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
        return c;
    }

    pub fn advanceN(self: *ParserState, n: usize) ?[]const u8 {
        if (self.position + n > self.input.len) return null;
        const slice = self.input[self.position .. self.position + n];
        for (slice) |c| {
            if (c == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
        }
        self.position += n;
        return slice;
    }

    pub fn mark(self: *ParserState) !void {
        try self.marks.append(.{
            .position = self.position,
            .line = self.line,
            .column = self.column,
        });
    }

    pub fn unmark(self: *ParserState) void {
        _ = self.marks.popOrNull();
    }

    pub fn reset(self: *ParserState) void {
        if (self.marks.popOrNull()) |m| {
            self.position = m.position;
            self.line = m.line;
            self.column = m.column;
        }
    }

    pub fn remaining(self: ParserState) []const u8 {
        return self.input[self.position..];
    }

    pub fn consumed(self: ParserState) []const u8 {
        return self.input[0..self.position];
    }
};

/// Core PEG parser with combinators
pub const Parser = struct {
    state: ParserState,
    allocator: std.mem.Allocator,
    debug: bool = false,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Parser {
        return .{
            .state = ParserState.init(allocator, input),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.state.deinit();
    }

    /// Match a literal string
    pub fn literal(self: *Parser, expected: []const u8) ParseResult {
        const start = self.state.position;
        const actual = self.state.peekN(expected.len) orelse {
            return .{ .failure = .{
                .position = self.state.position,
                .expected = expected,
                .found = self.state.peek(),
                .rule_name = "literal",
            } };
        };

        if (std.mem.eql(u8, actual, expected)) {
            _ = self.state.advanceN(expected.len);
            return .{ .success = .{
                .value = .{ .string = expected },
                .start_pos = start,
                .end_pos = self.state.position,
            } };
        }

        return .{ .failure = .{
            .position = self.state.position,
            .expected = expected,
            .found = self.state.peek(),
            .rule_name = "literal",
        } };
    }

    /// Match a single character
    pub fn char(self: *Parser, expected: u8) ParseResult {
        const start = self.state.position;
        const actual = self.state.peek() orelse {
            return .{ .failure = .{
                .position = self.state.position,
                .expected = &[_]u8{expected},
                .found = null,
                .rule_name = "char",
            } };
        };

        if (actual == expected) {
            _ = self.state.advance();
            return .{ .success = .{
                .value = .{ .string = self.state.input[start..self.state.position] },
                .start_pos = start,
                .end_pos = self.state.position,
            } };
        }

        return .{ .failure = .{
            .position = self.state.position,
            .expected = &[_]u8{expected},
            .found = actual,
            .rule_name = "char",
        } };
    }

    /// Match any character in range
    pub fn charRange(self: *Parser, from: u8, to: u8) ParseResult {
        const start = self.state.position;
        const actual = self.state.peek() orelse {
            return .{ .failure = .{
                .position = self.state.position,
                .expected = "character in range",
                .found = null,
                .rule_name = "charRange",
            } };
        };

        if (actual >= from and actual <= to) {
            _ = self.state.advance();
            return .{ .success = .{
                .value = .{ .string = self.state.input[start..self.state.position] },
                .start_pos = start,
                .end_pos = self.state.position,
            } };
        }

        return .{ .failure = .{
            .position = self.state.position,
            .expected = "character in range",
            .found = actual,
            .rule_name = "charRange",
        } };
    }

    /// Match any single character
    pub fn anyChar(self: *Parser) ParseResult {
        const start = self.state.position;
        const c = self.state.advance() orelse {
            return .{ .failure = .{
                .position = self.state.position,
                .expected = "any character",
                .found = null,
                .rule_name = "anyChar",
            } };
        };

        return .{ .success = .{
            .value = .{ .string = self.state.input[start..self.state.position] },
            .start_pos = start,
            .end_pos = self.state.position,
        } };
        _ = c;
    }

    /// Match end of input
    pub fn eof(self: *Parser) ParseResult {
        if (self.state.isEof()) {
            return .{ .success = .{
                .value = .{ .none = {} },
                .start_pos = self.state.position,
                .end_pos = self.state.position,
            } };
        }
        return .{ .failure = .{
            .position = self.state.position,
            .expected = "end of input",
            .found = self.state.peek(),
            .rule_name = "eof",
        } };
    }

    /// Parse zero or more occurrences
    pub fn zeroOrMore(self: *Parser, comptime parseFn: fn (*Parser) ParseResult) ParseResult {
        var results = std.ArrayList(ParseValue).init(self.allocator);
        const start = self.state.position;

        while (true) {
            const result = parseFn(self);
            if (result.isSuccess()) {
                results.append(result.success.value) catch break;
            } else {
                break;
            }
        }

        return .{ .success = .{
            .value = .{ .list = results.items },
            .start_pos = start,
            .end_pos = self.state.position,
        } };
    }

    /// Parse one or more occurrences
    pub fn oneOrMore(self: *Parser, comptime parseFn: fn (*Parser) ParseResult) ParseResult {
        const start = self.state.position;
        const first = parseFn(self);

        if (!first.isSuccess()) {
            return first;
        }

        var results = std.ArrayList(ParseValue).init(self.allocator);
        results.append(first.success.value) catch return first;

        while (true) {
            const result = parseFn(self);
            if (result.isSuccess()) {
                results.append(result.success.value) catch break;
            } else {
                break;
            }
        }

        return .{ .success = .{
            .value = .{ .list = results.items },
            .start_pos = start,
            .end_pos = self.state.position,
        } };
    }

    /// Optional parser - always succeeds
    pub fn optional(self: *Parser, comptime parseFn: fn (*Parser) ParseResult) ParseResult {
        const start = self.state.position;
        const result = parseFn(self);

        if (result.isSuccess()) {
            return result;
        }

        return .{ .success = .{
            .value = .{ .none = {} },
            .start_pos = start,
            .end_pos = start,
        } };
    }
};

/// Parse digits helper
fn parseDigit(parser: *Parser) ParseResult {
    return parser.charRange('0', '9');
}

/// Parse alpha helper
fn parseAlpha(parser: *Parser) ParseResult {
    const lower = parser.charRange('a', 'z');
    if (lower.isSuccess()) return lower;
    return parser.charRange('A', 'Z');
}

// Tests
test "parser_state_basic" {
    var state = ParserState.init(std.testing.allocator, "hello");
    defer state.deinit();

    try std.testing.expect(!state.isEof());
    try std.testing.expectEqual(@as(?u8, 'h'), state.peek());
}

test "parser_state_advance" {
    var state = ParserState.init(std.testing.allocator, "abc");
    defer state.deinit();

    try std.testing.expectEqual(@as(?u8, 'a'), state.advance());
    try std.testing.expectEqual(@as(?u8, 'b'), state.advance());
    try std.testing.expectEqual(@as(?u8, 'c'), state.advance());
    try std.testing.expectEqual(@as(?u8, null), state.advance());
    try std.testing.expect(state.isEof());
}

test "parser_state_peek_n" {
    var state = ParserState.init(std.testing.allocator, "hello world");
    defer state.deinit();

    try std.testing.expectEqualStrings("hello", state.peekN(5).?);
    try std.testing.expect(state.peekN(100) == null);
}

test "parser_state_mark_reset" {
    var state = ParserState.init(std.testing.allocator, "abcdef");
    defer state.deinit();

    _ = state.advance(); // a
    _ = state.advance(); // b
    try state.mark();
    _ = state.advance(); // c
    _ = state.advance(); // d

    try std.testing.expectEqual(@as(usize, 4), state.position);
    state.reset();
    try std.testing.expectEqual(@as(usize, 2), state.position);
}

test "parser_state_line_tracking" {
    var state = ParserState.init(std.testing.allocator, "ab\ncd");
    defer state.deinit();

    _ = state.advance(); // a
    try std.testing.expectEqual(@as(usize, 1), state.line);
    try std.testing.expectEqual(@as(usize, 2), state.column);

    _ = state.advance(); // b
    _ = state.advance(); // \n
    try std.testing.expectEqual(@as(usize, 2), state.line);
    try std.testing.expectEqual(@as(usize, 1), state.column);
}

test "parser_literal_success" {
    var parser = Parser.init(std.testing.allocator, "hello world");
    defer parser.deinit();

    const result = parser.literal("hello");
    try std.testing.expect(result.isSuccess());
    try std.testing.expectEqualStrings("hello", result.success.value.asString().?);
}

test "parser_literal_failure" {
    var parser = Parser.init(std.testing.allocator, "hello");
    defer parser.deinit();

    const result = parser.literal("world");
    try std.testing.expect(!result.isSuccess());
    try std.testing.expectEqualStrings("world", result.failure.expected);
}

test "parser_char_success" {
    var parser = Parser.init(std.testing.allocator, "abc");
    defer parser.deinit();

    const result = parser.char('a');
    try std.testing.expect(result.isSuccess());
}

test "parser_char_range" {
    var parser = Parser.init(std.testing.allocator, "5abc");
    defer parser.deinit();

    const digit = parser.charRange('0', '9');
    try std.testing.expect(digit.isSuccess());

    const alpha = parser.charRange('a', 'z');
    try std.testing.expect(alpha.isSuccess());
}

test "parser_any_char" {
    var parser = Parser.init(std.testing.allocator, "xyz");
    defer parser.deinit();

    const result = parser.anyChar();
    try std.testing.expect(result.isSuccess());
}

test "parser_eof" {
    var parser = Parser.init(std.testing.allocator, "");
    defer parser.deinit();

    const result = parser.eof();
    try std.testing.expect(result.isSuccess());
}

test "parser_eof_not_at_end" {
    var parser = Parser.init(std.testing.allocator, "x");
    defer parser.deinit();

    const result = parser.eof();
    try std.testing.expect(!result.isSuccess());
}

test "parser_zero_or_more" {
    var parser = Parser.init(std.testing.allocator, "12345abc");
    defer parser.deinit();

    const result = parser.zeroOrMore(parseDigit);
    try std.testing.expect(result.isSuccess());
    try std.testing.expectEqual(@as(usize, 5), result.success.value.asList().?.len);
}

test "parser_zero_or_more_empty" {
    var parser = Parser.init(std.testing.allocator, "abc");
    defer parser.deinit();

    const result = parser.zeroOrMore(parseDigit);
    try std.testing.expect(result.isSuccess());
    try std.testing.expectEqual(@as(usize, 0), result.success.value.asList().?.len);
}

test "parser_one_or_more_success" {
    var parser = Parser.init(std.testing.allocator, "123abc");
    defer parser.deinit();

    const result = parser.oneOrMore(parseDigit);
    try std.testing.expect(result.isSuccess());
    try std.testing.expectEqual(@as(usize, 3), result.success.value.asList().?.len);
}

test "parser_one_or_more_failure" {
    var parser = Parser.init(std.testing.allocator, "abc");
    defer parser.deinit();

    const result = parser.oneOrMore(parseDigit);
    try std.testing.expect(!result.isSuccess());
}

test "parser_optional_present" {
    var parser = Parser.init(std.testing.allocator, "5abc");
    defer parser.deinit();

    const result = parser.optional(parseDigit);
    try std.testing.expect(result.isSuccess());
    try std.testing.expect(result.success.value != .none);
}

test "parser_optional_missing" {
    var parser = Parser.init(std.testing.allocator, "abc");
    defer parser.deinit();

    const result = parser.optional(parseDigit);
    try std.testing.expect(result.isSuccess());
    try std.testing.expect(result.success.value == .none);
}

test "parse_result_position" {
    const success = ParseResult{ .success = .{
        .value = .{ .none = {} },
        .start_pos = 5,
        .end_pos = 10,
    } };
    try std.testing.expectEqual(@as(usize, 10), success.getPosition());

    const failure = ParseResult{ .failure = .{
        .position = 7,
        .expected = "test",
        .found = 'x',
        .rule_name = "test",
    } };
    try std.testing.expectEqual(@as(usize, 7), failure.getPosition());
}

test "parse_success_span" {
    const success = ParseSuccess{
        .value = .{ .none = {} },
        .start_pos = 3,
        .end_pos = 8,
    };
    try std.testing.expectEqual(@as(usize, 5), success.span());
}

test "parse_value_type_checks" {
    const str_val = ParseValue{ .string = "test" };
    try std.testing.expect(str_val.asString() != null);
    try std.testing.expect(str_val.asInt() == null);

    const int_val = ParseValue{ .integer = 42 };
    try std.testing.expect(int_val.asInt() != null);
    try std.testing.expect(int_val.asString() == null);
}
