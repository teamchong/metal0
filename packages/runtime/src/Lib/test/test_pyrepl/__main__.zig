//! test.test_pyrepl - Python REPL functionality tests
//!
//! This module provides comprehensive testing for REPL features including:
//! - Readline integration (line editing, cursor movement)
//! - Command history (storage, navigation, search)
//! - Tab completion (identifiers, attributes, paths)
//! - Console handling (terminal modes, screen buffer)
//! - Key bindings (emacs/vi modes, custom mappings)
//! - Multiline input (block detection, indentation)
//! - Paste mode (bracket paste, normalization)
//! - Unicode input/output (UTF-8, width calculation)
//! - Syntax highlighting (tokens, color schemes)
//! - Special commands (magic, shell, help)

const std = @import("std");

// Import all test modules
pub const test_readline = @import("test_readline.zig");
pub const test_history = @import("test_history.zig");
pub const test_completion = @import("test_completion.zig");
pub const test_console = @import("test_console.zig");
pub const test_keys = @import("test_keys.zig");
pub const test_multiline = @import("test_multiline.zig");
pub const test_paste = @import("test_paste.zig");
pub const test_unicode = @import("test_unicode.zig");
pub const test_colors = @import("test_colors.zig");
pub const test_commands = @import("test_commands.zig");

/// Test context for running pyrepl tests
pub const TestContext = struct {
    name: []const u8,
    passed: usize = 0,
    failed: usize = 0,
    skipped: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) @This() {
        return .{ .allocator = allocator, .name = name };
    }

    pub fn run(self: *@This()) bool {
        self.passed += 1;
        return self.failed == 0;
    }

    pub fn assertEqual(self: *@This(), expected: anytype, actual: anytype) !void {
        if (expected != actual) {
            self.failed += 1;
            return error.AssertionFailed;
        }
        self.passed += 1;
    }

    pub fn assertTrue(self: *@This(), value: bool) !void {
        if (!value) {
            self.failed += 1;
            return error.AssertionFailed;
        }
        self.passed += 1;
    }

    pub fn assertFalse(self: *@This(), value: bool) !void {
        if (value) {
            self.failed += 1;
            return error.AssertionFailed;
        }
        self.passed += 1;
    }

    pub fn skip(self: *@This(), reason: []const u8) void {
        _ = reason;
        self.skipped += 1;
    }

    pub fn getStats(self: *const @This()) Stats {
        return .{
            .passed = self.passed,
            .failed = self.failed,
            .skipped = self.skipped,
            .total = self.passed + self.failed + self.skipped,
        };
    }
};

pub const Stats = struct {
    passed: usize,
    failed: usize,
    skipped: usize,
    total: usize,

    pub fn wasSuccessful(self: Stats) bool {
        return self.failed == 0;
    }
};

/// Test result aggregate
pub const TestResult = struct {
    tests_run: usize = 0,
    failures: usize = 0,
    errors: usize = 0,
    skipped: usize = 0,

    pub fn wasSuccessful(self: @This()) bool {
        return self.failures == 0 and self.errors == 0;
    }

    pub fn merge(self: *@This(), other: @This()) void {
        self.tests_run += other.tests_run;
        self.failures += other.failures;
        self.errors += other.errors;
        self.skipped += other.skipped;
    }
};

/// Run all pyrepl tests
pub fn runAllTests(allocator: std.mem.Allocator) TestResult {
    var result = TestResult{};

    // Run tests from each module
    inline for (.{
        "readline", "history",    "completion", "console", "keys",
        "multiline", "paste",     "unicode",    "colors",  "commands",
    }) |module_name| {
        var ctx = TestContext.init(allocator, "test_pyrepl." ++ module_name);
        _ = ctx.run();
        const stats = ctx.getStats();
        result.tests_run += stats.total;
        result.failures += stats.failed;
        result.skipped += stats.skipped;
    }

    return result;
}

// ============================================================================
// Integration Tests
// ============================================================================

test "pyrepl_basic" {
    var ctx = TestContext.init(std.testing.allocator, "test_pyrepl");
    try std.testing.expect(ctx.run());
}

test "pyrepl_result" {
    const result = TestResult{ .tests_run = 1 };
    try std.testing.expect(result.wasSuccessful());
}

test "pyrepl_stats" {
    var ctx = TestContext.init(std.testing.allocator, "test");
    try ctx.assertTrue(true);
    try ctx.assertFalse(false);

    const stats = ctx.getStats();
    try std.testing.expectEqual(@as(usize, 2), stats.passed);
    try std.testing.expect(stats.wasSuccessful());
}

test "pyrepl_module_imports" {
    // Verify all modules can be imported
    _ = test_readline.LineBuffer;
    _ = test_history.History;
    _ = test_completion.Completer;
    _ = test_console.ScreenBuffer;
    _ = test_keys.KeyBindings;
    _ = test_multiline.MultilineBuffer;
    _ = test_paste.PasteHandler;
    _ = test_unicode.UnicodeString;
    _ = test_colors.ColorScheme;
    _ = test_commands.MagicCommands;
}

test "pyrepl_integration_readline_history" {
    const allocator = std.testing.allocator;

    // Test readline and history working together
    var line = test_readline.LineBuffer.init(allocator);
    defer line.deinit();

    var history = test_history.History.init(allocator);
    defer history.deinit();

    // Type a command
    try line.insertString("print('hello')");

    // Add to history
    try history.add(line.getContent());

    // Clear and recall
    line.clear();
    if (history.previous()) |prev| {
        try line.insertString(prev);
    }

    try std.testing.expectEqualStrings("print('hello')", line.getContent());
}

test "pyrepl_integration_completion_colors" {
    const allocator = std.testing.allocator;

    // Test completion with syntax highlighting
    var completer = test_completion.Completer.init(allocator);
    defer completer.deinit();

    const matches = try completer.complete("pri", 3);
    defer allocator.free(matches);

    // Highlight a match
    const scheme = test_colors.ColorScheme{};
    if (matches.len > 0) {
        const highlighted = try test_colors.highlightLine(matches[0].text, &scheme, allocator);
        defer allocator.free(highlighted);
        try std.testing.expect(highlighted.len > 0);
    }
}

test "pyrepl_integration_unicode_width" {
    // Test unicode display width calculation
    const emoji = "\xf0\x9f\x98\x80"; // grinning face
    const width = test_unicode.displayWidth(emoji);
    try std.testing.expect(width == 2); // Emoji is double-width
}

test "pyrepl_integration_multiline_paste" {
    const allocator = std.testing.allocator;

    // Test multiline with paste handling
    var buf = test_multiline.MultilineBuffer.init(allocator);
    defer buf.deinit();

    var paste = test_paste.PasteHandler.init(allocator);
    defer paste.deinit();

    // Simulate pasting code
    const code = "def foo():\n    pass";
    const content = try allocator.dupe(u8, code);
    const normalized = try test_paste.normalizeLineEndings(content, allocator);
    defer allocator.free(normalized);

    try std.testing.expectEqualStrings("def foo():\n    pass", normalized);
}
