//! test.test_warnings.test_showwarning - Comprehensive tests for showwarning
//!
//! Tests the showwarning function and custom warning display hooks.
//! Mirrors CPython's showwarning tests.

const std = @import("std");
const warnings = @import("Lib.warnings");

// ============================================================================
// Test Types
// ============================================================================

/// Captured warning output for testing
pub const CapturedOutput = struct {
    lines: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CapturedOutput {
        return .{
            .lines = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CapturedOutput) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit();
    }

    pub fn addLine(self: *CapturedOutput, line: []const u8) !void {
        const copy = try self.allocator.dupe(u8, line);
        try self.lines.append(copy);
    }

    pub fn getLineCount(self: CapturedOutput) usize {
        return self.lines.items.len;
    }

    pub fn getLine(self: CapturedOutput, index: usize) ?[]const u8 {
        if (index < self.lines.items.len) {
            return self.lines.items[index];
        }
        return null;
    }

    pub fn clear(self: *CapturedOutput) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearRetainingCapacity();
    }

    pub fn containsSubstring(self: CapturedOutput, substring: []const u8) bool {
        for (self.lines.items) |line| {
            if (std.mem.indexOf(u8, line, substring) != null) {
                return true;
            }
        }
        return false;
    }
};

/// Mock showwarning implementation for testing
pub const MockShowWarning = struct {
    output: CapturedOutput,
    call_count: usize,
    last_message: ?[]const u8,
    last_category: ?warnings.WarningCategory,
    last_filename: ?[]const u8,
    last_lineno: ?usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MockShowWarning {
        return .{
            .output = CapturedOutput.init(allocator),
            .call_count = 0,
            .last_message = null,
            .last_category = null,
            .last_filename = null,
            .last_lineno = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MockShowWarning) void {
        self.output.deinit();
        if (self.last_message) |msg| {
            self.allocator.free(msg);
        }
        if (self.last_filename) |fname| {
            self.allocator.free(fname);
        }
    }

    pub fn showWarning(
        self: *MockShowWarning,
        message: []const u8,
        category: warnings.WarningCategory,
        filename: []const u8,
        lineno: usize,
    ) !void {
        self.call_count += 1;

        // Store last values
        if (self.last_message) |msg| {
            self.allocator.free(msg);
        }
        self.last_message = try self.allocator.dupe(u8, message);

        self.last_category = category;

        if (self.last_filename) |fname| {
            self.allocator.free(fname);
        }
        self.last_filename = try self.allocator.dupe(u8, filename);

        self.last_lineno = lineno;

        // Format output line
        const line = try std.fmt.allocPrint(
            self.allocator,
            "{s}:{d}: {s}: {s}",
            .{ filename, lineno, category.name(), message },
        );
        defer self.allocator.free(line);

        try self.output.addLine(line);
    }

    pub fn reset(self: *MockShowWarning) void {
        self.call_count = 0;
        if (self.last_message) |msg| {
            self.allocator.free(msg);
            self.last_message = null;
        }
        self.last_category = null;
        if (self.last_filename) |fname| {
            self.allocator.free(fname);
            self.last_filename = null;
        }
        self.last_lineno = null;
        self.output.clear();
    }
};

/// Warning display configuration
pub const ShowWarningConfig = struct {
    show_filename: bool = true,
    show_lineno: bool = true,
    show_category: bool = true,
    show_source: bool = false,
    file: ?std.fs.File = null,

    pub fn createFormatter(self: ShowWarningConfig) Formatter {
        return .{ .config = self };
    }

    pub const Formatter = struct {
        config: ShowWarningConfig,

        pub fn format(
            self: Formatter,
            allocator: std.mem.Allocator,
            message: []const u8,
            category: warnings.WarningCategory,
            filename: []const u8,
            lineno: usize,
        ) ![]u8 {
            var result = std.ArrayList(u8).init(allocator);
            const writer = result.writer();

            if (self.config.show_filename) {
                try writer.print("{s}", .{filename});
            }

            if (self.config.show_lineno) {
                if (self.config.show_filename) {
                    try writer.print(":{d}", .{lineno});
                } else {
                    try writer.print("{d}", .{lineno});
                }
            }

            if (self.config.show_category) {
                if (self.config.show_filename or self.config.show_lineno) {
                    try writer.print(": {s}: ", .{category.name()});
                } else {
                    try writer.print("{s}: ", .{category.name()});
                }
            } else {
                try writer.print(": ", .{});
            }

            try writer.print("{s}", .{message});

            return result.toOwnedSlice();
        }
    };
};

/// Line parser for warning output
pub const WarningLineParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WarningLineParser {
        return .{ .allocator = allocator };
    }

    pub const ParsedLine = struct {
        filename: ?[]const u8,
        lineno: ?usize,
        category: ?[]const u8,
        message: ?[]const u8,
    };

    pub fn parse(self: WarningLineParser, line: []const u8) ParsedLine {
        _ = self;
        var result = ParsedLine{
            .filename = null,
            .lineno = null,
            .category = null,
            .message = null,
        };

        // Try to parse "filename:lineno: Category: message"
        if (std.mem.indexOf(u8, line, ":")) |first_colon| {
            result.filename = line[0..first_colon];

            const rest = line[first_colon + 1 ..];
            if (std.mem.indexOf(u8, rest, ":")) |second_colon| {
                const lineno_str = rest[0..second_colon];
                result.lineno = std.fmt.parseInt(usize, std.mem.trim(u8, lineno_str, " "), 10) catch null;

                const after_lineno = rest[second_colon + 1 ..];
                if (std.mem.indexOf(u8, after_lineno, ":")) |third_colon| {
                    result.category = std.mem.trim(u8, after_lineno[0..third_colon], " ");
                    result.message = std.mem.trim(u8, after_lineno[third_colon + 1 ..], " ");
                }
            }
        }

        return result;
    }
};

// ============================================================================
// Captured Output Tests
// ============================================================================

test "captured_output_init" {
    var output = CapturedOutput.init(std.testing.allocator);
    defer output.deinit();

    try std.testing.expectEqual(@as(usize, 0), output.getLineCount());
}

test "captured_output_add_line" {
    var output = CapturedOutput.init(std.testing.allocator);
    defer output.deinit();

    try output.addLine("test line 1");
    try output.addLine("test line 2");

    try std.testing.expectEqual(@as(usize, 2), output.getLineCount());
}

test "captured_output_get_line" {
    var output = CapturedOutput.init(std.testing.allocator);
    defer output.deinit();

    try output.addLine("first line");
    try output.addLine("second line");

    const first = output.getLine(0);
    try std.testing.expect(first != null);
    try std.testing.expectEqualStrings("first line", first.?);

    const second = output.getLine(1);
    try std.testing.expect(second != null);
    try std.testing.expectEqualStrings("second line", second.?);

    const invalid = output.getLine(5);
    try std.testing.expect(invalid == null);
}

test "captured_output_contains_substring" {
    var output = CapturedOutput.init(std.testing.allocator);
    defer output.deinit();

    try output.addLine("UserWarning: test message");

    try std.testing.expect(output.containsSubstring("UserWarning"));
    try std.testing.expect(output.containsSubstring("test message"));
    try std.testing.expect(!output.containsSubstring("DeprecationWarning"));
}

test "captured_output_clear" {
    var output = CapturedOutput.init(std.testing.allocator);
    defer output.deinit();

    try output.addLine("line 1");
    try output.addLine("line 2");
    try std.testing.expectEqual(@as(usize, 2), output.getLineCount());

    output.clear();
    try std.testing.expectEqual(@as(usize, 0), output.getLineCount());
}

// ============================================================================
// Mock ShowWarning Tests
// ============================================================================

test "mock_showwarning_init" {
    var mock = MockShowWarning.init(std.testing.allocator);
    defer mock.deinit();

    try std.testing.expectEqual(@as(usize, 0), mock.call_count);
    try std.testing.expect(mock.last_message == null);
}

test "mock_showwarning_call" {
    var mock = MockShowWarning.init(std.testing.allocator);
    defer mock.deinit();

    try mock.showWarning("test message", .UserWarning, "test.py", 42);

    try std.testing.expectEqual(@as(usize, 1), mock.call_count);
    try std.testing.expectEqualStrings("test message", mock.last_message.?);
    try std.testing.expectEqual(warnings.WarningCategory.UserWarning, mock.last_category.?);
    try std.testing.expectEqualStrings("test.py", mock.last_filename.?);
    try std.testing.expectEqual(@as(usize, 42), mock.last_lineno.?);
}

test "mock_showwarning_multiple_calls" {
    var mock = MockShowWarning.init(std.testing.allocator);
    defer mock.deinit();

    try mock.showWarning("first", .UserWarning, "a.py", 1);
    try mock.showWarning("second", .DeprecationWarning, "b.py", 2);
    try mock.showWarning("third", .RuntimeWarning, "c.py", 3);

    try std.testing.expectEqual(@as(usize, 3), mock.call_count);
    try std.testing.expectEqualStrings("third", mock.last_message.?);
    try std.testing.expectEqual(@as(usize, 3), mock.output.getLineCount());
}

test "mock_showwarning_output_format" {
    var mock = MockShowWarning.init(std.testing.allocator);
    defer mock.deinit();

    try mock.showWarning("deprecated feature", .DeprecationWarning, "module.py", 100);

    const line = mock.output.getLine(0);
    try std.testing.expect(line != null);
    try std.testing.expect(std.mem.indexOf(u8, line.?, "module.py") != null);
    try std.testing.expect(std.mem.indexOf(u8, line.?, "100") != null);
    try std.testing.expect(std.mem.indexOf(u8, line.?, "DeprecationWarning") != null);
    try std.testing.expect(std.mem.indexOf(u8, line.?, "deprecated feature") != null);
}

test "mock_showwarning_reset" {
    var mock = MockShowWarning.init(std.testing.allocator);
    defer mock.deinit();

    try mock.showWarning("test", .UserWarning, "test.py", 1);
    try std.testing.expectEqual(@as(usize, 1), mock.call_count);

    mock.reset();
    try std.testing.expectEqual(@as(usize, 0), mock.call_count);
    try std.testing.expect(mock.last_message == null);
    try std.testing.expectEqual(@as(usize, 0), mock.output.getLineCount());
}

// ============================================================================
// ShowWarning Config Tests
// ============================================================================

test "config_default" {
    const config = ShowWarningConfig{};

    try std.testing.expect(config.show_filename);
    try std.testing.expect(config.show_lineno);
    try std.testing.expect(config.show_category);
    try std.testing.expect(!config.show_source);
}

test "config_format_full" {
    const config = ShowWarningConfig{};
    const formatter = config.createFormatter();

    const result = try formatter.format(
        std.testing.allocator,
        "test message",
        .UserWarning,
        "test.py",
        42,
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "test.py") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "42") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "UserWarning") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "test message") != null);
}

test "config_format_no_filename" {
    const config = ShowWarningConfig{ .show_filename = false };
    const formatter = config.createFormatter();

    const result = try formatter.format(
        std.testing.allocator,
        "test message",
        .UserWarning,
        "test.py",
        42,
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "test.py") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "42") != null);
}

test "config_format_no_lineno" {
    const config = ShowWarningConfig{ .show_lineno = false };
    const formatter = config.createFormatter();

    const result = try formatter.format(
        std.testing.allocator,
        "test message",
        .UserWarning,
        "test.py",
        42,
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "test.py") != null);
    // Line number should not be present
    try std.testing.expect(std.mem.indexOf(u8, result, ":42:") == null);
}

test "config_format_no_category" {
    const config = ShowWarningConfig{ .show_category = false };
    const formatter = config.createFormatter();

    const result = try formatter.format(
        std.testing.allocator,
        "test message",
        .UserWarning,
        "test.py",
        42,
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "UserWarning") == null);
    try std.testing.expect(std.mem.indexOf(u8, result, "test message") != null);
}

// ============================================================================
// Line Parser Tests
// ============================================================================

test "parser_full_line" {
    const parser = WarningLineParser.init(std.testing.allocator);

    const parsed = parser.parse("test.py:42: UserWarning: test message");

    try std.testing.expectEqualStrings("test.py", parsed.filename.?);
    try std.testing.expectEqual(@as(usize, 42), parsed.lineno.?);
    try std.testing.expectEqualStrings("UserWarning", parsed.category.?);
    try std.testing.expectEqualStrings("test message", parsed.message.?);
}

test "parser_different_categories" {
    const parser = WarningLineParser.init(std.testing.allocator);

    const deprecation = parser.parse("mod.py:10: DeprecationWarning: old feature");
    try std.testing.expectEqualStrings("DeprecationWarning", deprecation.category.?);

    const runtime = parser.parse("mod.py:20: RuntimeWarning: runtime issue");
    try std.testing.expectEqualStrings("RuntimeWarning", runtime.category.?);
}

test "parser_with_colons_in_message" {
    const parser = WarningLineParser.init(std.testing.allocator);

    const parsed = parser.parse("test.py:1: UserWarning: message: with: colons");

    try std.testing.expectEqualStrings("test.py", parsed.filename.?);
    try std.testing.expectEqual(@as(usize, 1), parsed.lineno.?);
}

// ============================================================================
// Integration Tests
// ============================================================================

test "integration_showwarning_workflow" {
    var mock = MockShowWarning.init(std.testing.allocator);
    defer mock.deinit();

    // Simulate warning workflow
    try mock.showWarning("feature X is deprecated", .DeprecationWarning, "mymodule.py", 50);
    try mock.showWarning("use feature Y instead", .UserWarning, "mymodule.py", 51);

    try std.testing.expectEqual(@as(usize, 2), mock.call_count);
    try std.testing.expect(mock.output.containsSubstring("DeprecationWarning"));
    try std.testing.expect(mock.output.containsSubstring("UserWarning"));
}

test "integration_all_categories" {
    var mock = MockShowWarning.init(std.testing.allocator);
    defer mock.deinit();

    const categories = [_]warnings.WarningCategory{
        .Warning,
        .UserWarning,
        .DeprecationWarning,
        .PendingDeprecationWarning,
        .SyntaxWarning,
        .RuntimeWarning,
        .FutureWarning,
        .ImportWarning,
        .UnicodeWarning,
        .BytesWarning,
        .EncodingWarning,
        .ResourceWarning,
    };

    for (categories, 0..) |cat, i| {
        try mock.showWarning("test", cat, "test.py", i);
    }

    try std.testing.expectEqual(@as(usize, 12), mock.call_count);
}

test "integration_custom_formatter" {
    const config = ShowWarningConfig{
        .show_filename = true,
        .show_lineno = true,
        .show_category = true,
    };

    const formatter = config.createFormatter();

    const categories = [_]warnings.WarningCategory{
        .UserWarning,
        .DeprecationWarning,
        .RuntimeWarning,
    };

    for (categories, 0..) |cat, i| {
        const result = try formatter.format(
            std.testing.allocator,
            "test message",
            cat,
            "test.py",
            i + 1,
        );
        defer std.testing.allocator.free(result);

        try std.testing.expect(std.mem.indexOf(u8, result, cat.name()) != null);
    }
}
