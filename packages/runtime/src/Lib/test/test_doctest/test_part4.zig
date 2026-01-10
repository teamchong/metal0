//! test.test_doctest.test_part4 - OutputChecker implementation
//! Compare expected and actual output from doctest examples.
const std = @import("std");

/// Comparison mode for output checking
pub const CompareMode = enum {
    exact,
    normalized,
    ellipsis,
    regex,
};

/// Result of output comparison
pub const CompareResult = struct {
    matches: bool,
    expected_normalized: ?[]const u8 = null,
    actual_normalized: ?[]const u8 = null,
    diff_position: ?usize = null,
    message: ?[]const u8 = null,

    pub fn ok() @This() {
        return .{ .matches = true };
    }

    pub fn fail(message: []const u8) @This() {
        return .{ .matches = false, .message = message };
    }

    pub fn failAt(position: usize, message: []const u8) @This() {
        return .{ .matches = false, .diff_position = position, .message = message };
    }
};

/// OutputChecker - compares expected and actual doctest output
pub const OutputChecker = struct {
    allocator: std.mem.Allocator,
    optionflags: u32 = 0,

    // Option flags (matching Python's doctest module)
    pub const ELLIPSIS: u32 = 1 << 0;
    pub const NORMALIZE_WHITESPACE: u32 = 1 << 1;
    pub const IGNORE_EXCEPTION_DETAIL: u32 = 1 << 2;
    pub const DONT_ACCEPT_TRUE_FOR_1: u32 = 1 << 3;
    pub const DONT_ACCEPT_BLANKLINE: u32 = 1 << 4;
    pub const COMPARISON_FLAGS: u32 = ELLIPSIS | NORMALIZE_WHITESPACE;

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    /// Check if output matches expected, considering option flags
    pub fn checkOutput(self: @This(), want: []const u8, got: []const u8, optionflags: u32) bool {
        const flags = self.optionflags | optionflags;

        // Exact match first
        if (std.mem.eql(u8, want, got)) return true;

        // Empty expected matches empty got
        if (want.len == 0 and got.len == 0) return true;

        // Try normalized comparison
        if (flags & NORMALIZE_WHITESPACE != 0) {
            if (self.normalizedMatch(want, got)) return true;
        }

        // Try ellipsis matching
        if (flags & ELLIPSIS != 0) {
            if (self.ellipsisMatch(want, got)) return true;
        }

        return false;
    }

    /// Check output and return detailed comparison result
    pub fn checkOutputDetailed(
        self: @This(),
        want: []const u8,
        got: []const u8,
        optionflags: u32,
    ) CompareResult {
        const flags = self.optionflags | optionflags;

        if (std.mem.eql(u8, want, got)) {
            return CompareResult.ok();
        }

        if (want.len == 0 and got.len == 0) {
            return CompareResult.ok();
        }

        if (flags & NORMALIZE_WHITESPACE != 0) {
            if (self.normalizedMatch(want, got)) {
                return CompareResult.ok();
            }
        }

        if (flags & ELLIPSIS != 0) {
            if (self.ellipsisMatch(want, got)) {
                return CompareResult.ok();
            }
        }

        // Find first difference
        const diff_pos = self.findFirstDifference(want, got);
        return CompareResult.failAt(diff_pos, "Output does not match");
    }

    /// Normalize whitespace and compare
    fn normalizedMatch(self: @This(), want: []const u8, got: []const u8) bool {
        _ = self;
        const norm_want = normalizeWhitespace(want);
        const norm_got = normalizeWhitespace(got);
        return std.mem.eql(u8, norm_want, norm_got);
    }

    /// Match with ellipsis wildcards (... matches anything)
    fn ellipsisMatch(self: @This(), pattern: []const u8, text: []const u8) bool {
        _ = self;
        return matchEllipsis(pattern, text);
    }

    /// Find position of first difference between strings
    fn findFirstDifference(self: @This(), a: []const u8, b: []const u8) usize {
        _ = self;
        const min_len = @min(a.len, b.len);
        for (0..min_len) |i| {
            if (a[i] != b[i]) return i;
        }
        return min_len;
    }

    /// Generate a diff-style output for mismatches
    pub fn outputDifference(
        self: @This(),
        want: []const u8,
        got: []const u8,
        writer: anytype,
    ) !void {
        _ = self;
        try writer.writeAll("Expected:\n");
        var want_lines = std.mem.splitScalar(u8, want, '\n');
        while (want_lines.next()) |line| {
            try writer.print("    {s}\n", .{line});
        }

        try writer.writeAll("Got:\n");
        var got_lines = std.mem.splitScalar(u8, got, '\n');
        while (got_lines.next()) |line| {
            try writer.print("    {s}\n", .{line});
        }
    }
};

/// Normalize whitespace: collapse runs of whitespace to single space, trim
fn normalizeWhitespace(s: []const u8) []const u8 {
    // Simple approach: just trim for now
    // Full implementation would collapse internal whitespace
    return std.mem.trim(u8, s, " \t\n\r");
}

/// Match pattern with ellipsis wildcards
fn matchEllipsis(pattern: []const u8, text: []const u8) bool {
    const ellipsis = "...";

    // No ellipsis - exact match
    const first_ellipsis = std.mem.indexOf(u8, pattern, ellipsis) orelse {
        return std.mem.eql(u8, pattern, text);
    };

    // Check prefix before first ellipsis
    const prefix = pattern[0..first_ellipsis];
    if (!std.mem.startsWith(u8, text, prefix)) {
        return false;
    }

    // Get pattern after ellipsis
    const after_ellipsis = pattern[first_ellipsis + ellipsis.len ..];

    // If nothing after ellipsis, it matches everything
    if (after_ellipsis.len == 0) {
        return true;
    }

    // Find next ellipsis or end
    if (std.mem.indexOf(u8, after_ellipsis, ellipsis)) |_| {
        // Multiple ellipses - need recursive matching
        return matchMultipleEllipsis(after_ellipsis, text[prefix.len..]);
    }

    // Single ellipsis - check suffix
    return std.mem.endsWith(u8, text, after_ellipsis);
}

/// Handle patterns with multiple ellipses
fn matchMultipleEllipsis(pattern: []const u8, text: []const u8) bool {
    const ellipsis = "...";

    var pat_parts = std.mem.splitSequence(u8, pattern, ellipsis);
    var current_text = text;

    while (pat_parts.next()) |part| {
        if (part.len == 0) continue;

        // Find this part in remaining text
        if (std.mem.indexOf(u8, current_text, part)) |pos| {
            current_text = current_text[pos + part.len ..];
        } else {
            return false;
        }
    }

    return true;
}

/// Diff generator for output comparison
pub const DiffGenerator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .allocator = allocator };
    }

    /// Generate unified diff between expected and actual
    pub fn unifiedDiff(
        self: @This(),
        expected: []const u8,
        actual: []const u8,
        writer: anytype,
    ) !void {
        _ = self;
        var exp_lines = std.mem.splitScalar(u8, expected, '\n');
        var act_lines = std.mem.splitScalar(u8, actual, '\n');

        var line_num: usize = 1;
        while (true) {
            const exp_line = exp_lines.next();
            const act_line = act_lines.next();

            if (exp_line == null and act_line == null) break;

            const exp = exp_line orelse "";
            const act = act_line orelse "";

            if (!std.mem.eql(u8, exp, act)) {
                try writer.print("@@ line {d} @@\n", .{line_num});
                try writer.print("-{s}\n", .{exp});
                try writer.print("+{s}\n", .{act});
            }

            line_num += 1;
        }
    }

    /// Generate context diff (shows surrounding lines)
    pub fn contextDiff(
        self: @This(),
        expected: []const u8,
        actual: []const u8,
        context_lines: usize,
        writer: anytype,
    ) !void {
        _ = self;
        _ = context_lines;

        // Simplified: just show what differs
        try writer.writeAll("*** Expected ***\n");
        try writer.print("{s}\n", .{expected});
        try writer.writeAll("*** Actual ***\n");
        try writer.print("{s}\n", .{actual});
    }
};

/// Exception output matcher for IGNORE_EXCEPTION_DETAIL
pub const ExceptionMatcher = struct {
    /// Check if both are exceptions of the same type
    pub fn matchExceptionType(expected: []const u8, actual: []const u8) bool {
        const exp_type = extractExceptionType(expected);
        const act_type = extractExceptionType(actual);

        if (exp_type == null or act_type == null) return false;
        return std.mem.eql(u8, exp_type.?, act_type.?);
    }

    /// Extract exception type from traceback line
    fn extractExceptionType(line: []const u8) ?[]const u8 {
        const trimmed = std.mem.trim(u8, line, " \t\n\r");

        // Look for "SomeError:" or "SomeError("
        for (trimmed, 0..) |c, i| {
            if (c == ':' or c == '(') {
                return trimmed[0..i];
            }
        }

        // Might be bare exception name
        if (trimmed.len > 0 and std.ascii.isUpper(trimmed[0])) {
            return trimmed;
        }

        return null;
    }
};

/// Blank line handling
pub const BlankLineChecker = struct {
    pub const BLANKLINE_MARKER = "<BLANKLINE>";

    /// Replace actual blank lines with marker for comparison
    pub fn replaceBlankLines(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        var lines = std.mem.splitScalar(u8, text, '\n');
        var first = true;

        while (lines.next()) |line| {
            if (!first) try result.append('\n');
            first = false;

            if (line.len == 0) {
                try result.appendSlice(BLANKLINE_MARKER);
            } else {
                try result.appendSlice(line);
            }
        }

        return result.toOwnedSlice();
    }

    /// Check if line is a blank line marker
    pub fn isBlankLineMarker(line: []const u8) bool {
        return std.mem.eql(u8, std.mem.trim(u8, line, " \t"), BLANKLINE_MARKER);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "OutputChecker_exact_match" {
    const checker = OutputChecker.init(std.testing.allocator);

    try std.testing.expect(checker.checkOutput("hello", "hello", 0));
    try std.testing.expect(!checker.checkOutput("hello", "world", 0));
}

test "OutputChecker_empty_match" {
    const checker = OutputChecker.init(std.testing.allocator);

    try std.testing.expect(checker.checkOutput("", "", 0));
}

test "OutputChecker_normalize_whitespace" {
    const checker = OutputChecker.init(std.testing.allocator);

    try std.testing.expect(checker.checkOutput("hello", "  hello  ", OutputChecker.NORMALIZE_WHITESPACE));
    try std.testing.expect(checker.checkOutput("hello world", "  hello world  ", OutputChecker.NORMALIZE_WHITESPACE));
}

test "OutputChecker_ellipsis_suffix" {
    const checker = OutputChecker.init(std.testing.allocator);

    try std.testing.expect(checker.checkOutput("hello...", "hello world", OutputChecker.ELLIPSIS));
    try std.testing.expect(checker.checkOutput("start...", "start and more text", OutputChecker.ELLIPSIS));
}

test "OutputChecker_ellipsis_prefix_suffix" {
    const checker = OutputChecker.init(std.testing.allocator);

    try std.testing.expect(checker.checkOutput("hello...world", "hello there world", OutputChecker.ELLIPSIS));
}

test "OutputChecker_ellipsis_no_match" {
    const checker = OutputChecker.init(std.testing.allocator);

    try std.testing.expect(!checker.checkOutput("hello...world", "goodbye there world", OutputChecker.ELLIPSIS));
}

test "OutputChecker_checkOutputDetailed_ok" {
    const checker = OutputChecker.init(std.testing.allocator);

    const result = checker.checkOutputDetailed("hello", "hello", 0);
    try std.testing.expect(result.matches);
}

test "OutputChecker_checkOutputDetailed_fail" {
    const checker = OutputChecker.init(std.testing.allocator);

    const result = checker.checkOutputDetailed("hello", "world", 0);
    try std.testing.expect(!result.matches);
    try std.testing.expectEqual(@as(usize, 0), result.diff_position.?);
}

test "OutputChecker_findFirstDifference" {
    const checker = OutputChecker.init(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), checker.findFirstDifference("abc", "xyz"));
    try std.testing.expectEqual(@as(usize, 2), checker.findFirstDifference("abc", "abx"));
    try std.testing.expectEqual(@as(usize, 3), checker.findFirstDifference("abc", "abcd"));
}

test "normalizeWhitespace" {
    try std.testing.expectEqualStrings("hello", normalizeWhitespace("  hello  "));
    try std.testing.expectEqualStrings("hello world", normalizeWhitespace("  hello world  "));
    try std.testing.expectEqualStrings("test", normalizeWhitespace("\n\ttest\n"));
}

test "matchEllipsis_no_ellipsis" {
    try std.testing.expect(matchEllipsis("exact", "exact"));
    try std.testing.expect(!matchEllipsis("exact", "different"));
}

test "matchEllipsis_trailing" {
    try std.testing.expect(matchEllipsis("start...", "start and anything else"));
    try std.testing.expect(matchEllipsis("abc...", "abcdef"));
}

test "matchEllipsis_middle" {
    try std.testing.expect(matchEllipsis("start...end", "start middle end"));
    try std.testing.expect(!matchEllipsis("start...end", "start middle finish"));
}

test "matchMultipleEllipsis" {
    try std.testing.expect(matchMultipleEllipsis("a...b...c", "aXXbYYc"));
    try std.testing.expect(matchMultipleEllipsis("...x...", "before x after"));
}

test "DiffGenerator_unifiedDiff" {
    const gen = DiffGenerator.init(std.testing.allocator);
    var buf: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try gen.unifiedDiff("line1\nline2", "line1\nchanged", stream.writer());

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "-line2") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "+changed") != null);
}

test "ExceptionMatcher_matchExceptionType" {
    try std.testing.expect(ExceptionMatcher.matchExceptionType(
        "ValueError: invalid value",
        "ValueError: different message",
    ));
    try std.testing.expect(!ExceptionMatcher.matchExceptionType(
        "ValueError: x",
        "TypeError: x",
    ));
}

test "ExceptionMatcher_extractExceptionType" {
    try std.testing.expectEqualStrings(
        "ValueError",
        ExceptionMatcher.extractExceptionType("ValueError: bad value").?,
    );
    try std.testing.expectEqualStrings(
        "TypeError",
        ExceptionMatcher.extractExceptionType("TypeError(msg)").?,
    );
}

test "BlankLineChecker_replaceBlankLines" {
    const result = try BlankLineChecker.replaceBlankLines(std.testing.allocator, "line1\n\nline2");
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "<BLANKLINE>") != null);
}

test "BlankLineChecker_isBlankLineMarker" {
    try std.testing.expect(BlankLineChecker.isBlankLineMarker("<BLANKLINE>"));
    try std.testing.expect(BlankLineChecker.isBlankLineMarker("  <BLANKLINE>  "));
    try std.testing.expect(!BlankLineChecker.isBlankLineMarker("not blank"));
}

test "CompareResult_ok" {
    const result = CompareResult.ok();
    try std.testing.expect(result.matches);
    try std.testing.expect(result.message == null);
}

test "CompareResult_fail" {
    const result = CompareResult.fail("error message");
    try std.testing.expect(!result.matches);
    try std.testing.expectEqualStrings("error message", result.message.?);
}

test "CompareResult_failAt" {
    const result = CompareResult.failAt(10, "mismatch");
    try std.testing.expect(!result.matches);
    try std.testing.expectEqual(@as(usize, 10), result.diff_position.?);
}
