//! test.test_future_stmt.test_print - Tests for `from __future__ import print_function`
//!
//! PEP 3105 made print a function instead of a statement in Python 3.
//! In Python 2, `print x` was a statement. With this future import (or Python 3),
//! `print(x)` is required as print becomes a function.
//!
//! This module tests print function semantics and output formatting.
//!
//! CPython Reference: https://docs.python.org/3/library/__future__.html
//! PEP 3105: https://peps.python.org/pep-3105/

const std = @import("std");
const testing = std.testing;

// ============================================================================
// Print Configuration
// ============================================================================

/// Configuration for print function behavior
pub const PrintConfig = struct {
    /// Separator between values (default: space)
    sep: []const u8 = " ",
    /// String appended after the last value (default: newline)
    end: []const u8 = "\n",
    /// Whether to flush the output buffer
    flush: bool = false,
    /// Output file/stream (null means stdout)
    file: ?*std.fs.File = null,

    const Self = @This();

    /// Create a default configuration
    pub fn default() Self {
        return .{};
    }

    /// Create configuration with custom separator
    pub fn withSep(sep: []const u8) Self {
        return .{ .sep = sep };
    }

    /// Create configuration with custom ending
    pub fn withEnd(ending: []const u8) Self {
        return .{ .end = ending };
    }

    /// Create configuration for inline output (no newline)
    pub fn inline_() Self {
        return .{ .end = "" };
    }

    /// Create configuration with flush enabled
    pub fn withFlush() Self {
        return .{ .flush = true };
    }
};

// ============================================================================
// Print Buffer for Testing
// ============================================================================

/// Buffer to capture print output for testing
pub const PrintBuffer = struct {
    buffer: std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .buffer = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Write a string to the buffer
    pub fn write(self: *Self, data: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, data);
    }

    /// Get the current buffer contents
    pub fn getContents(self: Self) []const u8 {
        return self.buffer.items;
    }

    /// Clear the buffer
    pub fn clear(self: *Self) void {
        self.buffer.clearRetainingCapacity();
    }

    /// Get the number of bytes written
    pub fn len(self: Self) usize {
        return self.buffer.items.len;
    }
};

// ============================================================================
// Print Function Implementation
// ============================================================================

/// Print multiple values with configuration
pub fn print(buffer: *PrintBuffer, config: PrintConfig, values: []const []const u8) !void {
    for (values, 0..) |value, i| {
        if (i > 0) {
            try buffer.write(config.sep);
        }
        try buffer.write(value);
    }
    try buffer.write(config.end);
}

/// Print a single value with default configuration
pub fn printOne(buffer: *PrintBuffer, value: []const u8) !void {
    try print(buffer, PrintConfig.default(), &.{value});
}

/// Print multiple values with default configuration
pub fn printMany(buffer: *PrintBuffer, values: []const []const u8) !void {
    try print(buffer, PrintConfig.default(), values);
}

// ============================================================================
// Value Formatting
// ============================================================================

/// Format a value for printing (simulates Python's str())
pub const Formatter = struct {
    buffer: std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .buffer = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Format an integer
    pub fn formatInt(self: *Self, value: i64) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        var buf: [32]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return error.FormatError;
        try self.buffer.appendSlice(self.allocator, slice);
        return self.buffer.items;
    }

    /// Format a float
    pub fn formatFloat(self: *Self, value: f64) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        var buf: [64]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return error.FormatError;
        try self.buffer.appendSlice(self.allocator, slice);
        return self.buffer.items;
    }

    /// Format a boolean
    pub fn formatBool(self: *Self, value: bool) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        try self.buffer.appendSlice(self.allocator, if (value) "True" else "False");
        return self.buffer.items;
    }

    /// Format None
    pub fn formatNone(self: *Self) ![]const u8 {
        self.buffer.clearRetainingCapacity();
        try self.buffer.appendSlice(self.allocator, "None");
        return self.buffer.items;
    }
};

// ============================================================================
// Print Context Manager
// ============================================================================

/// Context manager for redirecting print output
pub const PrintRedirect = struct {
    original_buffer: ?*PrintBuffer,
    redirect_buffer: *PrintBuffer,
    active: bool = false,

    const Self = @This();

    pub fn init(redirect_to: *PrintBuffer) Self {
        return .{
            .original_buffer = null,
            .redirect_buffer = redirect_to,
        };
    }

    pub fn __enter__(self: *Self) *PrintBuffer {
        self.active = true;
        return self.redirect_buffer;
    }

    pub fn __exit__(self: *Self) void {
        self.active = false;
    }

    pub fn isActive(self: Self) bool {
        return self.active;
    }
};

// ============================================================================
// Output Stream Types
// ============================================================================

/// Represents different output stream types
pub const StreamType = enum {
    stdout,
    stderr,
    file,
    buffer,

    pub fn name(self: StreamType) []const u8 {
        return switch (self) {
            .stdout => "stdout",
            .stderr => "stderr",
            .file => "file",
            .buffer => "buffer",
        };
    }

    pub fn isTerminal(self: StreamType) bool {
        return self == .stdout or self == .stderr;
    }
};

/// Output stream wrapper
pub const OutputStream = struct {
    stream_type: StreamType,
    buffer: ?*PrintBuffer = null,
    encoding: []const u8 = "utf-8",

    const Self = @This();

    pub fn stdout() Self {
        return .{ .stream_type = .stdout };
    }

    pub fn stderr() Self {
        return .{ .stream_type = .stderr };
    }

    pub fn fromBuffer(buffer: *PrintBuffer) Self {
        return .{ .stream_type = .buffer, .buffer = buffer };
    }

    pub fn write(self: *Self, data: []const u8) !void {
        if (self.stream_type == .buffer) {
            if (self.buffer) |buf| {
                try buf.write(data);
            }
        }
        // stdout, stderr, file not implemented for test module
    }

    pub fn flush(self: *Self) !void {
        // No-op for now
        _ = self;
    }
};

// ============================================================================
// Print Statement to Function Migration
// ============================================================================

/// Represents the transition from print statement to print function
pub const PrintMigration = struct {
    /// Check if a string looks like a Python 2 print statement
    pub fn isPrintStatement(code: []const u8) bool {
        // Simple heuristic: "print " without parentheses
        if (!std.mem.startsWith(u8, code, "print ")) return false;
        if (std.mem.indexOf(u8, code, "(") != null) return false;
        return true;
    }

    /// Convert print statement to print function (simple cases)
    pub fn convert(allocator: std.mem.Allocator, statement: []const u8) ![]u8 {
        if (!std.mem.startsWith(u8, statement, "print ")) {
            // Already a function call or not a print
            return try allocator.dupe(u8, statement);
        }

        // Extract the arguments after "print "
        const args = statement[6..];

        // Check for special cases
        if (std.mem.startsWith(u8, args, ">>")) {
            // print >> stderr, "msg" -> print("msg", file=stderr)
            // Simplified handling
            return try std.fmt.allocPrint(allocator, "print({s}, file=stderr)", .{args[2..]});
        }

        // Simple conversion: print x, y -> print(x, y)
        var result: std.ArrayListUnmanaged(u8) = .{};
        try result.appendSlice(allocator, "print(");
        try result.appendSlice(allocator, std.mem.trim(u8, args, " \t\n"));
        try result.append(allocator, ')');
        return try result.toOwnedSlice(allocator);
    }
};

// ============================================================================
// Soft Space Handling (Python 2 compatibility)
// ============================================================================

/// Simulates Python 2's softspace behavior
/// In Python 2, print statements maintained a "softspace" flag
pub const SoftSpace = struct {
    need_space: bool = false,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    /// Write with automatic spacing
    pub fn write(self: *Self, buffer: *PrintBuffer, value: []const u8) !void {
        if (self.need_space and value.len > 0) {
            try buffer.write(" ");
        }
        try buffer.write(value);
        // Set softspace based on last character
        if (value.len > 0) {
            const last = value[value.len - 1];
            self.need_space = last != '\n' and last != '\t' and last != ' ';
        }
    }

    /// Reset the softspace flag
    pub fn reset(self: *Self) void {
        self.need_space = false;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "print_buffer_basic" {
    var buffer = PrintBuffer.init(testing.allocator);
    defer buffer.deinit();

    try buffer.write("hello");
    try testing.expectEqualStrings("hello", buffer.getContents());
}

test "print_buffer_multiple_writes" {
    var buffer = PrintBuffer.init(testing.allocator);
    defer buffer.deinit();

    try buffer.write("hello");
    try buffer.write(" ");
    try buffer.write("world");
    try testing.expectEqualStrings("hello world", buffer.getContents());
}

test "print_single_value" {
    var buffer = PrintBuffer.init(testing.allocator);
    defer buffer.deinit();

    try printOne(&buffer, "hello");
    try testing.expectEqualStrings("hello\n", buffer.getContents());
}

test "print_multiple_values" {
    var buffer = PrintBuffer.init(testing.allocator);
    defer buffer.deinit();

    try printMany(&buffer, &.{ "a", "b", "c" });
    try testing.expectEqualStrings("a b c\n", buffer.getContents());
}

test "print_custom_separator" {
    var buffer = PrintBuffer.init(testing.allocator);
    defer buffer.deinit();

    try print(&buffer, PrintConfig.withSep(", "), &.{ "x", "y", "z" });
    try testing.expectEqualStrings("x, y, z\n", buffer.getContents());
}

test "print_custom_ending" {
    var buffer = PrintBuffer.init(testing.allocator);
    defer buffer.deinit();

    try print(&buffer, PrintConfig.withEnd("!\n"), &.{"hello"});
    try testing.expectEqualStrings("hello!\n", buffer.getContents());
}

test "print_inline_no_newline" {
    var buffer = PrintBuffer.init(testing.allocator);
    defer buffer.deinit();

    try print(&buffer, PrintConfig.inline_(), &.{"hello"});
    try testing.expectEqualStrings("hello", buffer.getContents());
}

test "formatter_int" {
    var formatter = Formatter.init(testing.allocator);
    defer formatter.deinit();

    const result = try formatter.formatInt(42);
    try testing.expectEqualStrings("42", result);
}

test "formatter_negative_int" {
    var formatter = Formatter.init(testing.allocator);
    defer formatter.deinit();

    const result = try formatter.formatInt(-123);
    try testing.expectEqualStrings("-123", result);
}

test "formatter_bool" {
    var formatter = Formatter.init(testing.allocator);
    defer formatter.deinit();

    try testing.expectEqualStrings("True", try formatter.formatBool(true));
    try testing.expectEqualStrings("False", try formatter.formatBool(false));
}

test "formatter_none" {
    var formatter = Formatter.init(testing.allocator);
    defer formatter.deinit();

    try testing.expectEqualStrings("None", try formatter.formatNone());
}

test "print_redirect_context" {
    var buffer = PrintBuffer.init(testing.allocator);
    defer buffer.deinit();

    var redirect = PrintRedirect.init(&buffer);
    try testing.expect(!redirect.isActive());

    const captured = redirect.__enter__();
    try testing.expect(redirect.isActive());
    try captured.write("captured output");
    redirect.__exit__();

    try testing.expect(!redirect.isActive());
    try testing.expectEqualStrings("captured output", buffer.getContents());
}

test "stream_type_names" {
    try testing.expectEqualStrings("stdout", StreamType.stdout.name());
    try testing.expectEqualStrings("stderr", StreamType.stderr.name());
    try testing.expectEqualStrings("file", StreamType.file.name());
    try testing.expectEqualStrings("buffer", StreamType.buffer.name());
}

test "stream_type_is_terminal" {
    try testing.expect(StreamType.stdout.isTerminal());
    try testing.expect(StreamType.stderr.isTerminal());
    try testing.expect(!StreamType.file.isTerminal());
    try testing.expect(!StreamType.buffer.isTerminal());
}

test "is_print_statement" {
    try testing.expect(PrintMigration.isPrintStatement("print x"));
    try testing.expect(PrintMigration.isPrintStatement("print x, y"));
    try testing.expect(!PrintMigration.isPrintStatement("print(x)"));
    try testing.expect(!PrintMigration.isPrintStatement("print(x, y)"));
    try testing.expect(!PrintMigration.isPrintStatement("printf(x)"));
}

test "convert_print_statement" {
    const result = try PrintMigration.convert(testing.allocator, "print x, y");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("print(x, y)", result);
}

test "softspace_behavior" {
    var buffer = PrintBuffer.init(testing.allocator);
    defer buffer.deinit();

    var ss = SoftSpace.init();
    try ss.write(&buffer, "hello");
    try ss.write(&buffer, "world");
    try testing.expectEqualStrings("hello world", buffer.getContents());
}

test "softspace_after_newline" {
    var buffer = PrintBuffer.init(testing.allocator);
    defer buffer.deinit();

    var ss = SoftSpace.init();
    try ss.write(&buffer, "hello\n");
    try ss.write(&buffer, "world");
    try testing.expectEqualStrings("hello\nworld", buffer.getContents());
}

test "print_buffer_clear" {
    var buffer = PrintBuffer.init(testing.allocator);
    defer buffer.deinit();

    try buffer.write("hello");
    try testing.expectEqual(@as(usize, 5), buffer.len());

    buffer.clear();
    try testing.expectEqual(@as(usize, 0), buffer.len());
}

test "output_stream_buffer_write" {
    var buffer = PrintBuffer.init(testing.allocator);
    defer buffer.deinit();

    var stream = OutputStream.fromBuffer(&buffer);
    try stream.write("test output");
    try testing.expectEqualStrings("test output", buffer.getContents());
}

test "print_config_default" {
    const config = PrintConfig.default();
    try testing.expectEqualStrings(" ", config.sep);
    try testing.expectEqualStrings("\n", config.end);
    try testing.expect(!config.flush);
}

test "print_empty_values" {
    var buffer = PrintBuffer.init(testing.allocator);
    defer buffer.deinit();

    try print(&buffer, PrintConfig.default(), &.{});
    try testing.expectEqualStrings("\n", buffer.getContents());
}
