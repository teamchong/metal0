//! test.test_doctest.test_part6 - Error Handling implementation
//! Handle errors and exceptions in doctest examples.
const std = @import("std");

/// Types of errors that can occur during doctest execution
pub const ErrorKind = enum {
    syntax_error,
    runtime_error,
    unexpected_exception,
    wrong_exception,
    output_mismatch,
    timeout,
    import_error,
    attribute_error,
    assertion_error,
    unknown,

    pub fn fromName(name: []const u8) ?@This() {
        const map = std.StaticStringMap(@This()).initComptime(.{
            .{ "SyntaxError", .syntax_error },
            .{ "RuntimeError", .runtime_error },
            .{ "ImportError", .import_error },
            .{ "AttributeError", .attribute_error },
            .{ "AssertionError", .assertion_error },
            .{ "TimeoutError", .timeout },
        });
        return map.get(name);
    }
};

/// Represents an error from doctest execution
pub const DocTestError = struct {
    kind: ErrorKind,
    message: []const u8,
    lineno: usize,
    source: []const u8,
    traceback: ?[]const u8 = null,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s} at line {d}: {s}", .{
            @tagName(self.kind),
            self.lineno,
            self.message,
        });
        if (self.traceback) |tb| {
            try writer.print("\nTraceback:\n{s}", .{tb});
        }
    }
};

/// Exception information parsed from doctest output
pub const ExceptionInfo = struct {
    type_name: []const u8,
    message: ?[]const u8 = null,
    traceback_lines: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, type_name: []const u8) @This() {
        return .{
            .type_name = type_name,
            .traceback_lines = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.traceback_lines.deinit();
    }

    pub fn addTracebackLine(self: *@This(), line: []const u8) !void {
        try self.traceback_lines.append(line);
    }

    pub fn matches(self: @This(), expected_type: []const u8) bool {
        return std.mem.eql(u8, self.type_name, expected_type);
    }

    pub fn matchesAny(self: @This(), types: []const []const u8) bool {
        for (types) |t| {
            if (std.mem.eql(u8, self.type_name, t)) return true;
        }
        return false;
    }
};

/// Parse exception from output text
pub fn parseException(allocator: std.mem.Allocator, output: []const u8) ?ExceptionInfo {
    var lines = std.mem.splitScalar(u8, output, '\n');

    // Look for exception type line (e.g., "ValueError: message")
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");

        // Skip traceback header
        if (std.mem.startsWith(u8, trimmed, "Traceback")) continue;
        if (std.mem.startsWith(u8, trimmed, "File \"")) continue;

        // Look for ExceptionType: message pattern
        if (std.mem.indexOf(u8, trimmed, ":")) |colon_pos| {
            const type_name = trimmed[0..colon_pos];

            // Check if it looks like an exception (starts with uppercase)
            if (type_name.len > 0 and std.ascii.isUpper(type_name[0])) {
                var info = ExceptionInfo.init(allocator, type_name);
                if (colon_pos + 1 < trimmed.len) {
                    info.message = std.mem.trim(u8, trimmed[colon_pos + 1 ..], " ");
                }
                return info;
            }
        }
    }

    return null;
}

/// Error collector for doctest runs
pub const ErrorCollector = struct {
    errors: std.ArrayList(DocTestError),
    allocator: std.mem.Allocator,
    max_errors: usize = 100,
    fail_fast: bool = false,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .errors = std.ArrayList(DocTestError).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.errors.deinit();
    }

    pub fn addError(self: *@This(), err: DocTestError) !void {
        if (self.errors.items.len >= self.max_errors) {
            return error.TooManyErrors;
        }
        try self.errors.append(err);
    }

    pub fn hasErrors(self: @This()) bool {
        return self.errors.items.len > 0;
    }

    pub fn errorCount(self: @This()) usize {
        return self.errors.items.len;
    }

    pub fn clear(self: *@This()) void {
        self.errors.clearRetainingCapacity();
    }

    pub fn getErrors(self: @This()) []const DocTestError {
        return self.errors.items;
    }

    pub fn errorsOfKind(self: @This(), kind: ErrorKind) usize {
        var count: usize = 0;
        for (self.errors.items) |err| {
            if (err.kind == kind) count += 1;
        }
        return count;
    }

    pub fn report(self: @This(), writer: anytype) !void {
        if (self.errors.items.len == 0) {
            try writer.writeAll("No errors.\n");
            return;
        }

        try writer.print("{d} error(s):\n", .{self.errors.items.len});
        for (self.errors.items, 0..) |err, i| {
            try writer.print("\n{d}. {}\n", .{ i + 1, err });
        }
    }
};

/// Failure report for a single doctest
pub const FailureReport = struct {
    test_name: []const u8,
    example_lineno: usize,
    source: []const u8,
    expected: []const u8,
    actual: []const u8,
    error_info: ?DocTestError = null,

    pub fn write(self: @This(), writer: anytype) !void {
        try writer.print(
            \\**********************************************************************
            \\File "{s}", line {d}, in {s}
            \\Failed example:
            \\    {s}
            \\Expected:
            \\    {s}
            \\Got:
            \\    {s}
            \\
        , .{
            "test_file.py", // Would be real file
            self.example_lineno,
            self.test_name,
            self.source,
            self.expected,
            self.actual,
        });

        if (self.error_info) |err| {
            try writer.print("Error: {}\n", .{err});
        }
    }
};

/// Handle expected exceptions in examples
pub const ExpectedExceptionHandler = struct {
    expected_types: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    ignore_message: bool = false,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .expected_types = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.expected_types.deinit();
    }

    pub fn expectException(self: *@This(), type_name: []const u8) !void {
        try self.expected_types.append(type_name);
    }

    pub fn checkException(self: @This(), actual_type: []const u8) bool {
        for (self.expected_types.items) |expected| {
            if (std.mem.eql(u8, expected, actual_type)) {
                return true;
            }
        }
        return false;
    }

    pub fn checkExceptionOutput(self: @This(), output: []const u8) bool {
        if (parseException(self.allocator, output)) |info| {
            const result = self.checkException(info.type_name);
            // Note: info is stack-allocated here, so we need to be careful
            return result;
        }
        return false;
    }
};

/// Traceback parser for exception output
pub const TracebackParser = struct {
    lines: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{
            .lines = std.ArrayList([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.lines.deinit();
    }

    /// Parse traceback from output
    pub fn parse(self: *@This(), output: []const u8) !void {
        var in_traceback = false;
        var line_iter = std.mem.splitScalar(u8, output, '\n');

        while (line_iter.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            if (std.mem.startsWith(u8, trimmed, "Traceback")) {
                in_traceback = true;
                try self.lines.append(trimmed);
            } else if (in_traceback) {
                try self.lines.append(trimmed);

                // Exception line ends traceback
                if (trimmed.len > 0 and std.ascii.isUpper(trimmed[0])) {
                    if (std.mem.indexOf(u8, trimmed, ":")) |_| {
                        break;
                    }
                }
            }
        }
    }

    /// Get last frame from traceback
    pub fn getLastFrame(self: @This()) ?[]const u8 {
        for (0..self.lines.items.len) |i| {
            const idx = self.lines.items.len - 1 - i;
            const line = self.lines.items[idx];
            if (std.mem.startsWith(u8, line, "File \"")) {
                return line;
            }
        }
        return null;
    }

    /// Get exception type and message
    pub fn getException(self: @This()) ?struct { type_name: []const u8, message: []const u8 } {
        if (self.lines.items.len == 0) return null;

        const last = self.lines.items[self.lines.items.len - 1];
        if (std.mem.indexOf(u8, last, ":")) |colon| {
            return .{
                .type_name = last[0..colon],
                .message = if (colon + 1 < last.len) std.mem.trim(u8, last[colon + 1 ..], " ") else "",
            };
        }
        return null;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ErrorKind_fromName" {
    try std.testing.expectEqual(ErrorKind.syntax_error, ErrorKind.fromName("SyntaxError").?);
    try std.testing.expectEqual(ErrorKind.import_error, ErrorKind.fromName("ImportError").?);
    try std.testing.expect(ErrorKind.fromName("UnknownError") == null);
}

test "DocTestError_format" {
    const err = DocTestError{
        .kind = .syntax_error,
        .message = "invalid syntax",
        .lineno = 10,
        .source = "x = ",
    };

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try stream.writer().print("{}", .{err});

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "syntax_error") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "line 10") != null);
}

test "ExceptionInfo_init" {
    var info = ExceptionInfo.init(std.testing.allocator, "ValueError");
    defer info.deinit();

    try std.testing.expectEqualStrings("ValueError", info.type_name);
    try std.testing.expect(info.message == null);
}

test "ExceptionInfo_matches" {
    var info = ExceptionInfo.init(std.testing.allocator, "TypeError");
    defer info.deinit();

    try std.testing.expect(info.matches("TypeError"));
    try std.testing.expect(!info.matches("ValueError"));
}

test "ExceptionInfo_matchesAny" {
    var info = ExceptionInfo.init(std.testing.allocator, "ValueError");
    defer info.deinit();

    try std.testing.expect(info.matchesAny(&.{ "TypeError", "ValueError" }));
    try std.testing.expect(!info.matchesAny(&.{ "TypeError", "KeyError" }));
}

test "parseException_simple" {
    const output = "ValueError: invalid value";
    var info = parseException(std.testing.allocator, output).?;
    defer info.deinit();

    try std.testing.expectEqualStrings("ValueError", info.type_name);
    try std.testing.expectEqualStrings("invalid value", info.message.?);
}

test "parseException_with_traceback" {
    const output =
        \\Traceback (most recent call last):
        \\  File "test.py", line 1
        \\    x = bad
        \\TypeError: something wrong
    ;

    var info = parseException(std.testing.allocator, output).?;
    defer info.deinit();

    try std.testing.expectEqualStrings("TypeError", info.type_name);
}

test "parseException_no_exception" {
    const output = "regular output\nno errors here";
    try std.testing.expect(parseException(std.testing.allocator, output) == null);
}

test "ErrorCollector_init" {
    var collector = ErrorCollector.init(std.testing.allocator);
    defer collector.deinit();

    try std.testing.expect(!collector.hasErrors());
    try std.testing.expectEqual(@as(usize, 0), collector.errorCount());
}

test "ErrorCollector_addError" {
    var collector = ErrorCollector.init(std.testing.allocator);
    defer collector.deinit();

    try collector.addError(.{
        .kind = .syntax_error,
        .message = "test error",
        .lineno = 5,
        .source = "x =",
    });

    try std.testing.expect(collector.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), collector.errorCount());
}

test "ErrorCollector_errorsOfKind" {
    var collector = ErrorCollector.init(std.testing.allocator);
    defer collector.deinit();

    try collector.addError(.{ .kind = .syntax_error, .message = "1", .lineno = 1, .source = "" });
    try collector.addError(.{ .kind = .runtime_error, .message = "2", .lineno = 2, .source = "" });
    try collector.addError(.{ .kind = .syntax_error, .message = "3", .lineno = 3, .source = "" });

    try std.testing.expectEqual(@as(usize, 2), collector.errorsOfKind(.syntax_error));
    try std.testing.expectEqual(@as(usize, 1), collector.errorsOfKind(.runtime_error));
}

test "ErrorCollector_clear" {
    var collector = ErrorCollector.init(std.testing.allocator);
    defer collector.deinit();

    try collector.addError(.{ .kind = .syntax_error, .message = "test", .lineno = 1, .source = "" });
    try std.testing.expect(collector.hasErrors());

    collector.clear();
    try std.testing.expect(!collector.hasErrors());
}

test "FailureReport_write" {
    const report = FailureReport{
        .test_name = "test_example",
        .example_lineno = 5,
        .source = "1 + 1",
        .expected = "3",
        .actual = "2",
    };

    var buf: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try report.write(stream.writer());

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "test_example") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "1 + 1") != null);
}

test "ExpectedExceptionHandler_checkException" {
    var handler = ExpectedExceptionHandler.init(std.testing.allocator);
    defer handler.deinit();

    try handler.expectException("ValueError");
    try handler.expectException("TypeError");

    try std.testing.expect(handler.checkException("ValueError"));
    try std.testing.expect(handler.checkException("TypeError"));
    try std.testing.expect(!handler.checkException("KeyError"));
}

test "TracebackParser_parse" {
    var parser = TracebackParser.init(std.testing.allocator);
    defer parser.deinit();

    const output =
        \\Traceback (most recent call last):
        \\  File "test.py", line 5, in <module>
        \\    raise ValueError("bad")
        \\ValueError: bad
    ;

    try parser.parse(output);

    try std.testing.expect(parser.lines.items.len > 0);
}

test "TracebackParser_getException" {
    var parser = TracebackParser.init(std.testing.allocator);
    defer parser.deinit();

    const output =
        \\Traceback (most recent call last):
        \\  File "test.py", line 1
        \\ValueError: test message
    ;

    try parser.parse(output);

    const exc = parser.getException().?;
    try std.testing.expectEqualStrings("ValueError", exc.type_name);
    try std.testing.expectEqualStrings("test message", exc.message);
}

test "TracebackParser_getLastFrame" {
    var parser = TracebackParser.init(std.testing.allocator);
    defer parser.deinit();

    const output =
        \\Traceback (most recent call last):
        \\  File "outer.py", line 10, in outer
        \\  File "inner.py", line 5, in inner
        \\ValueError: error
    ;

    try parser.parse(output);

    const frame = parser.getLastFrame();
    try std.testing.expect(frame != null);
    try std.testing.expect(std.mem.indexOf(u8, frame.?, "inner.py") != null);
}
