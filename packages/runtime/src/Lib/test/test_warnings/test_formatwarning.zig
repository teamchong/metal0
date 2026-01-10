//! test.test_warnings.test_formatwarning - Comprehensive tests for formatwarning
//!
//! Tests the formatwarning function for creating formatted warning messages.
//! Mirrors CPython's formatwarning tests.

const std = @import("std");
const warnings = @import("Lib.warnings");

// ============================================================================
// Test Types
// ============================================================================

/// Warning format specification
pub const FormatSpec = struct {
    include_filename: bool = true,
    include_lineno: bool = true,
    include_category: bool = true,
    include_message: bool = true,
    include_source: bool = false,
    newline: []const u8 = "\n",

    pub fn format(
        self: FormatSpec,
        allocator: std.mem.Allocator,
        message: []const u8,
        category: warnings.WarningCategory,
        filename: []const u8,
        lineno: usize,
        source: ?[]const u8,
    ) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        const writer = result.writer();

        // Standard format: "filename:lineno: category: message\n"
        if (self.include_filename) {
            try writer.print("{s}", .{filename});
        }

        if (self.include_lineno) {
            if (self.include_filename) {
                try writer.print(":{d}", .{lineno});
            } else {
                try writer.print("{d}", .{lineno});
            }
        }

        if (self.include_category) {
            if (self.include_filename or self.include_lineno) {
                try writer.print(": {s}", .{category.name()});
            } else {
                try writer.print("{s}", .{category.name()});
            }
        }

        if (self.include_message) {
            if (self.include_filename or self.include_lineno or self.include_category) {
                try writer.print(": {s}", .{message});
            } else {
                try writer.print("{s}", .{message});
            }
        }

        try writer.writeAll(self.newline);

        if (self.include_source) {
            if (source) |src| {
                try writer.print("  {s}{s}", .{ src, self.newline });
            }
        }

        return result.toOwnedSlice();
    }
};

/// Format test case
pub const FormatTestCase = struct {
    message: []const u8,
    category: warnings.WarningCategory,
    filename: []const u8,
    lineno: usize,
    source: ?[]const u8 = null,
    expected_contains: []const []const u8,

    pub fn run(self: FormatTestCase, allocator: std.mem.Allocator) !bool {
        const result = try warnings.formatWarning(
            allocator,
            self.message,
            self.category,
            self.filename,
            self.lineno,
            self.source,
        );
        defer allocator.free(result);

        for (self.expected_contains) |expected| {
            if (std.mem.indexOf(u8, result, expected) == null) {
                return false;
            }
        }

        return true;
    }
};

/// Format builder for constructing warning messages
pub const FormatBuilder = struct {
    parts: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FormatBuilder {
        return .{
            .parts = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FormatBuilder) void {
        for (self.parts.items) |part| {
            self.allocator.free(part);
        }
        self.parts.deinit();
    }

    pub fn addFilename(self: *FormatBuilder, filename: []const u8) !void {
        const copy = try self.allocator.dupe(u8, filename);
        try self.parts.append(copy);
    }

    pub fn addLineno(self: *FormatBuilder, lineno: usize) !void {
        const str = try std.fmt.allocPrint(self.allocator, ":{d}", .{lineno});
        try self.parts.append(str);
    }

    pub fn addCategory(self: *FormatBuilder, category: warnings.WarningCategory) !void {
        const str = try std.fmt.allocPrint(self.allocator, ": {s}", .{category.name()});
        try self.parts.append(str);
    }

    pub fn addMessage(self: *FormatBuilder, message: []const u8) !void {
        const str = try std.fmt.allocPrint(self.allocator, ": {s}", .{message});
        try self.parts.append(str);
    }

    pub fn build(self: FormatBuilder) ![]u8 {
        var total_len: usize = 0;
        for (self.parts.items) |part| {
            total_len += part.len;
        }
        total_len += 1; // newline

        var result = try self.allocator.alloc(u8, total_len);
        var offset: usize = 0;
        for (self.parts.items) |part| {
            @memcpy(result[offset .. offset + part.len], part);
            offset += part.len;
        }
        result[offset] = '\n';

        return result;
    }
};

/// Format validator
pub const FormatValidator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FormatValidator {
        return .{ .allocator = allocator };
    }

    pub fn validate(self: FormatValidator, formatted: []const u8) ValidationResult {
        _ = self;
        var result = ValidationResult{};

        // Check for filename:lineno pattern
        if (std.mem.indexOf(u8, formatted, ":")) |colon_pos| {
            result.has_filename = colon_pos > 0;

            const rest = formatted[colon_pos + 1 ..];
            if (std.mem.indexOf(u8, rest, ":")) |_| {
                result.has_lineno = true;
            }
        }

        // Check for category names
        const categories = [_][]const u8{
            "Warning",           "UserWarning",      "DeprecationWarning",
            "SyntaxWarning",     "RuntimeWarning",   "FutureWarning",
            "ImportWarning",     "UnicodeWarning",   "BytesWarning",
            "EncodingWarning",   "ResourceWarning",
        };

        for (categories) |cat| {
            if (std.mem.indexOf(u8, formatted, cat) != null) {
                result.has_category = true;
                break;
            }
        }

        // Check for newline at end
        result.has_newline = formatted.len > 0 and formatted[formatted.len - 1] == '\n';

        return result;
    }

    pub const ValidationResult = struct {
        has_filename: bool = false,
        has_lineno: bool = false,
        has_category: bool = false,
        has_newline: bool = false,

        pub fn isValid(self: ValidationResult) bool {
            return self.has_filename and self.has_lineno and self.has_category and self.has_newline;
        }
    };
};

// ============================================================================
// Basic Format Tests
// ============================================================================

test "formatwarning_basic" {
    const allocator = std.testing.allocator;

    const result = try warnings.formatWarning(
        allocator,
        "test message",
        .UserWarning,
        "test.py",
        42,
        null,
    );
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "test.py") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "42") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "UserWarning") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "test message") != null);
}

test "formatwarning_with_source" {
    const allocator = std.testing.allocator;

    const result = try warnings.formatWarning(
        allocator,
        "warning",
        .UserWarning,
        "test.py",
        10,
        "x = deprecated_func()",
    );
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "test.py") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "x = deprecated_func()") != null);
}

test "formatwarning_all_categories" {
    const allocator = std.testing.allocator;

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

    for (categories) |cat| {
        const result = try warnings.formatWarning(
            allocator,
            "test",
            cat,
            "test.py",
            1,
            null,
        );
        defer allocator.free(result);

        try std.testing.expect(std.mem.indexOf(u8, result, cat.name()) != null);
    }
}

// ============================================================================
// Format Spec Tests
// ============================================================================

test "format_spec_default" {
    const spec = FormatSpec{};
    try std.testing.expect(spec.include_filename);
    try std.testing.expect(spec.include_lineno);
    try std.testing.expect(spec.include_category);
    try std.testing.expect(spec.include_message);
    try std.testing.expect(!spec.include_source);
}

test "format_spec_full" {
    const spec = FormatSpec{};

    const result = try spec.format(
        std.testing.allocator,
        "test message",
        .UserWarning,
        "test.py",
        42,
        null,
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "test.py") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "42") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "UserWarning") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "test message") != null);
}

test "format_spec_with_source" {
    const spec = FormatSpec{ .include_source = true };

    const result = try spec.format(
        std.testing.allocator,
        "warning",
        .DeprecationWarning,
        "mod.py",
        100,
        "old_function()",
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "old_function()") != null);
}

test "format_spec_no_filename" {
    const spec = FormatSpec{ .include_filename = false };

    const result = try spec.format(
        std.testing.allocator,
        "test",
        .UserWarning,
        "test.py",
        1,
        null,
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "test.py") == null);
}

test "format_spec_no_lineno" {
    const spec = FormatSpec{ .include_lineno = false };

    const result = try spec.format(
        std.testing.allocator,
        "test",
        .UserWarning,
        "test.py",
        42,
        null,
    );
    defer std.testing.allocator.free(result);

    // Should not have the :42 pattern
    try std.testing.expect(std.mem.indexOf(u8, result, ":42") == null);
}

test "format_spec_no_category" {
    const spec = FormatSpec{ .include_category = false };

    const result = try spec.format(
        std.testing.allocator,
        "test",
        .UserWarning,
        "test.py",
        1,
        null,
    );
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "UserWarning") == null);
}

// ============================================================================
// Format Builder Tests
// ============================================================================

test "format_builder_init" {
    var builder = FormatBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try std.testing.expectEqual(@as(usize, 0), builder.parts.items.len);
}

test "format_builder_add_parts" {
    var builder = FormatBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.addFilename("test.py");
    try builder.addLineno(42);
    try builder.addCategory(.UserWarning);
    try builder.addMessage("test message");

    try std.testing.expectEqual(@as(usize, 4), builder.parts.items.len);
}

test "format_builder_build" {
    var builder = FormatBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.addFilename("test.py");
    try builder.addLineno(42);
    try builder.addCategory(.UserWarning);
    try builder.addMessage("test message");

    const result = try builder.build();
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "test.py") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, ":42") != null);
    try std.testing.expect(result[result.len - 1] == '\n');
}

// ============================================================================
// Format Validator Tests
// ============================================================================

test "validator_valid_format" {
    const validator = FormatValidator.init(std.testing.allocator);

    const formatted = "test.py:42: UserWarning: test message\n";
    const result = validator.validate(formatted);

    try std.testing.expect(result.has_filename);
    try std.testing.expect(result.has_lineno);
    try std.testing.expect(result.has_category);
    try std.testing.expect(result.has_newline);
    try std.testing.expect(result.isValid());
}

test "validator_missing_newline" {
    const validator = FormatValidator.init(std.testing.allocator);

    const formatted = "test.py:42: UserWarning: test message";
    const result = validator.validate(formatted);

    try std.testing.expect(!result.has_newline);
    try std.testing.expect(!result.isValid());
}

test "validator_different_categories" {
    const validator = FormatValidator.init(std.testing.allocator);

    const test_cases = [_][]const u8{
        "test.py:1: UserWarning: msg\n",
        "test.py:1: DeprecationWarning: msg\n",
        "test.py:1: RuntimeWarning: msg\n",
        "test.py:1: SyntaxWarning: msg\n",
    };

    for (test_cases) |formatted| {
        const result = validator.validate(formatted);
        try std.testing.expect(result.has_category);
    }
}

// ============================================================================
// Format Test Case Tests
// ============================================================================

test "test_case_basic" {
    const case = FormatTestCase{
        .message = "test message",
        .category = .UserWarning,
        .filename = "test.py",
        .lineno = 42,
        .expected_contains = &[_][]const u8{ "test.py", "42", "UserWarning", "test message" },
    };

    const result = try case.run(std.testing.allocator);
    try std.testing.expect(result);
}

test "test_case_deprecation" {
    const case = FormatTestCase{
        .message = "feature X is deprecated",
        .category = .DeprecationWarning,
        .filename = "module.py",
        .lineno = 100,
        .expected_contains = &[_][]const u8{ "module.py", "100", "DeprecationWarning", "deprecated" },
    };

    const result = try case.run(std.testing.allocator);
    try std.testing.expect(result);
}

// ============================================================================
// Edge Cases
// ============================================================================

test "formatwarning_empty_message" {
    const allocator = std.testing.allocator;

    const result = try warnings.formatWarning(
        allocator,
        "",
        .UserWarning,
        "test.py",
        1,
        null,
    );
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "UserWarning") != null);
}

test "formatwarning_long_filename" {
    const allocator = std.testing.allocator;

    const long_filename = "/very/long/path/to/some/deeply/nested/module/file.py";
    const result = try warnings.formatWarning(
        allocator,
        "test",
        .UserWarning,
        long_filename,
        1,
        null,
    );
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, long_filename) != null);
}

test "formatwarning_large_lineno" {
    const allocator = std.testing.allocator;

    const result = try warnings.formatWarning(
        allocator,
        "test",
        .UserWarning,
        "test.py",
        999999,
        null,
    );
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "999999") != null);
}

test "formatwarning_unicode_message" {
    const allocator = std.testing.allocator;

    const result = try warnings.formatWarning(
        allocator,
        "message with unicode",
        .UserWarning,
        "test.py",
        1,
        null,
    );
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "unicode") != null);
}

test "formatwarning_special_characters" {
    const allocator = std.testing.allocator;

    const result = try warnings.formatWarning(
        allocator,
        "message with 'quotes' and \"double quotes\"",
        .UserWarning,
        "test.py",
        1,
        null,
    );
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "'quotes'") != null);
}
