//! test.test_peg_generator.test_errors - Error recovery tests
//!
//! This module tests error handling and recovery in PEG parsers,
//! including error messages, synchronization, and error recovery strategies.

const std = @import("std");

/// Severity levels for parse errors
pub const ErrorSeverity = enum {
    warning,
    error_,
    fatal,

    pub fn isRecoverable(self: ErrorSeverity) bool {
        return self != .fatal;
    }

    pub fn toString(self: ErrorSeverity) []const u8 {
        return switch (self) {
            .warning => "warning",
            .error_ => "error",
            .fatal => "fatal",
        };
    }
};

/// A single parse error
pub const ParseError = struct {
    message: []const u8,
    position: usize,
    line: usize,
    column: usize,
    severity: ErrorSeverity,
    expected: ?[]const u8,
    found: ?[]const u8,
    rule_name: []const u8,
    context: ?[]const u8,

    pub fn init(message: []const u8, position: usize, line: usize, column: usize) ParseError {
        return .{
            .message = message,
            .position = position,
            .line = line,
            .column = column,
            .severity = .error_,
            .expected = null,
            .found = null,
            .rule_name = "",
            .context = null,
        };
    }

    pub fn withSeverity(self: ParseError, severity: ErrorSeverity) ParseError {
        var copy = self;
        copy.severity = severity;
        return copy;
    }

    pub fn withExpected(self: ParseError, expected: []const u8, found: ?[]const u8) ParseError {
        var copy = self;
        copy.expected = expected;
        copy.found = found;
        return copy;
    }

    pub fn withRule(self: ParseError, rule_name: []const u8) ParseError {
        var copy = self;
        copy.rule_name = rule_name;
        return copy;
    }

    pub fn withContext(self: ParseError, context: []const u8) ParseError {
        var copy = self;
        copy.context = context;
        return copy;
    }

    pub fn format(self: ParseError, allocator: std.mem.Allocator) ![]u8 {
        var parts = std.ArrayList(u8).init(allocator);
        const writer = parts.writer();

        try writer.print("{s} at line {d}, column {d}: {s}", .{
            self.severity.toString(),
            self.line,
            self.column,
            self.message,
        });

        if (self.expected) |exp| {
            try writer.print("\n  expected: {s}", .{exp});
            if (self.found) |fnd| {
                try writer.print("\n  found: {s}", .{fnd});
            }
        }

        if (self.context) |ctx| {
            try writer.print("\n  context: {s}", .{ctx});
        }

        return parts.toOwnedSlice();
    }
};

/// Collection of parse errors
pub const ErrorList = struct {
    errors: std.ArrayList(ParseError),
    allocator: std.mem.Allocator,
    max_errors: usize,
    has_fatal: bool,

    pub fn init(allocator: std.mem.Allocator) ErrorList {
        return .{
            .errors = std.ArrayList(ParseError).init(allocator),
            .allocator = allocator,
            .max_errors = 100,
            .has_fatal = false,
        };
    }

    pub fn deinit(self: *ErrorList) void {
        self.errors.deinit();
    }

    pub fn add(self: *ErrorList, err: ParseError) !void {
        if (self.errors.items.len >= self.max_errors) {
            return error.TooManyErrors;
        }

        if (err.severity == .fatal) {
            self.has_fatal = true;
        }

        try self.errors.append(err);
    }

    pub fn addError(self: *ErrorList, message: []const u8, position: usize, line: usize, column: usize) !void {
        try self.add(ParseError.init(message, position, line, column));
    }

    pub fn addWarning(self: *ErrorList, message: []const u8, position: usize, line: usize, column: usize) !void {
        try self.add(ParseError.init(message, position, line, column).withSeverity(.warning));
    }

    pub fn count(self: ErrorList) usize {
        return self.errors.items.len;
    }

    pub fn hasErrors(self: ErrorList) bool {
        for (self.errors.items) |err| {
            if (err.severity == .error_ or err.severity == .fatal) {
                return true;
            }
        }
        return false;
    }

    pub fn hasFatalError(self: ErrorList) bool {
        return self.has_fatal;
    }

    pub fn getErrors(self: ErrorList) []const ParseError {
        return self.errors.items;
    }

    pub fn clear(self: *ErrorList) void {
        self.errors.clearRetainingCapacity();
        self.has_fatal = false;
    }

    pub fn sortByPosition(self: *ErrorList) void {
        std.mem.sort(ParseError, self.errors.items, {}, struct {
            fn lessThan(_: void, a: ParseError, b: ParseError) bool {
                return a.position < b.position;
            }
        }.lessThan);
    }
};

/// Error recovery strategies
pub const RecoveryStrategy = enum {
    panic, // Stop parsing immediately
    skip_token, // Skip current token and continue
    skip_until, // Skip until synchronization token
    insert_token, // Insert expected token and continue
    delete_token, // Delete unexpected token and continue
    replace_token, // Replace unexpected with expected

    pub fn description(self: RecoveryStrategy) []const u8 {
        return switch (self) {
            .panic => "stop parsing",
            .skip_token => "skip current token",
            .skip_until => "skip until sync point",
            .insert_token => "insert expected token",
            .delete_token => "delete unexpected token",
            .replace_token => "replace token",
        };
    }
};

/// Error recovery handler
pub const ErrorRecovery = struct {
    strategy: RecoveryStrategy,
    sync_tokens: std.ArrayList([]const u8),
    recovery_points: std.ArrayList(usize),
    allocator: std.mem.Allocator,
    max_recovery_attempts: usize,
    current_attempts: usize,

    pub fn init(allocator: std.mem.Allocator) ErrorRecovery {
        return .{
            .strategy = .skip_until,
            .sync_tokens = std.ArrayList([]const u8).init(allocator),
            .recovery_points = std.ArrayList(usize).init(allocator),
            .allocator = allocator,
            .max_recovery_attempts = 10,
            .current_attempts = 0,
        };
    }

    pub fn deinit(self: *ErrorRecovery) void {
        self.sync_tokens.deinit();
        self.recovery_points.deinit();
    }

    pub fn setStrategy(self: *ErrorRecovery, strategy: RecoveryStrategy) void {
        self.strategy = strategy;
    }

    pub fn addSyncToken(self: *ErrorRecovery, token: []const u8) !void {
        try self.sync_tokens.append(token);
    }

    pub fn pushRecoveryPoint(self: *ErrorRecovery, position: usize) !void {
        try self.recovery_points.append(position);
    }

    pub fn popRecoveryPoint(self: *ErrorRecovery) ?usize {
        return self.recovery_points.popOrNull();
    }

    pub fn isSyncToken(self: ErrorRecovery, token: []const u8) bool {
        for (self.sync_tokens.items) |sync| {
            if (std.mem.eql(u8, sync, token)) {
                return true;
            }
        }
        return false;
    }

    pub fn canRecover(self: ErrorRecovery) bool {
        if (self.strategy == .panic) return false;
        return self.current_attempts < self.max_recovery_attempts;
    }

    pub fn attemptRecovery(self: *ErrorRecovery) bool {
        if (!self.canRecover()) return false;
        self.current_attempts += 1;
        return true;
    }

    pub fn resetAttempts(self: *ErrorRecovery) void {
        self.current_attempts = 0;
    }

    pub fn getRecoveryPosition(self: ErrorRecovery) ?usize {
        if (self.recovery_points.items.len == 0) return null;
        return self.recovery_points.items[self.recovery_points.items.len - 1];
    }
};

/// Expected tokens tracker for better error messages
pub const ExpectedTracker = struct {
    expected: std.StringHashMap(void),
    position: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ExpectedTracker {
        return .{
            .expected = std.StringHashMap(void).init(allocator),
            .position = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ExpectedTracker) void {
        self.expected.deinit();
    }

    pub fn add(self: *ExpectedTracker, position: usize, token: []const u8) !void {
        if (position > self.position) {
            // New furthest position, reset expected
            self.expected.clearRetainingCapacity();
            self.position = position;
        }
        if (position == self.position) {
            try self.expected.put(token, {});
        }
    }

    pub fn getExpected(self: ExpectedTracker, allocator: std.mem.Allocator) ![]const []const u8 {
        var list = std.ArrayList([]const u8).init(allocator);
        var iter = self.expected.keyIterator();
        while (iter.next()) |key| {
            try list.append(key.*);
        }
        return list.toOwnedSlice();
    }

    pub fn formatExpected(self: ExpectedTracker, allocator: std.mem.Allocator) ![]u8 {
        const expected = try self.getExpected(allocator);
        defer allocator.free(expected);

        if (expected.len == 0) return try allocator.dupe(u8, "nothing");
        if (expected.len == 1) return try allocator.dupe(u8, expected[0]);

        var result = std.ArrayList(u8).init(allocator);
        for (expected, 0..) |exp, i| {
            if (i > 0) {
                if (i == expected.len - 1) {
                    try result.appendSlice(" or ");
                } else {
                    try result.appendSlice(", ");
                }
            }
            try result.appendSlice(exp);
        }
        return result.toOwnedSlice();
    }

    pub fn clear(self: *ExpectedTracker) void {
        self.expected.clearRetainingCapacity();
        self.position = 0;
    }

    pub fn count(self: ExpectedTracker) usize {
        return self.expected.count();
    }
};

// Tests
test "error_severity_recoverable" {
    try std.testing.expect(ErrorSeverity.warning.isRecoverable());
    try std.testing.expect(ErrorSeverity.error_.isRecoverable());
    try std.testing.expect(!ErrorSeverity.fatal.isRecoverable());
}

test "error_severity_to_string" {
    try std.testing.expectEqualStrings("warning", ErrorSeverity.warning.toString());
    try std.testing.expectEqualStrings("error", ErrorSeverity.error_.toString());
    try std.testing.expectEqualStrings("fatal", ErrorSeverity.fatal.toString());
}

test "parse_error_init" {
    const err = ParseError.init("unexpected token", 10, 2, 5);
    try std.testing.expectEqualStrings("unexpected token", err.message);
    try std.testing.expectEqual(@as(usize, 10), err.position);
    try std.testing.expectEqual(@as(usize, 2), err.line);
    try std.testing.expectEqual(@as(usize, 5), err.column);
    try std.testing.expect(err.severity == .error_);
}

test "parse_error_with_severity" {
    const err = ParseError.init("test", 0, 1, 1).withSeverity(.warning);
    try std.testing.expect(err.severity == .warning);
}

test "parse_error_with_expected" {
    const err = ParseError.init("test", 0, 1, 1).withExpected("number", "string");
    try std.testing.expectEqualStrings("number", err.expected.?);
    try std.testing.expectEqualStrings("string", err.found.?);
}

test "parse_error_with_rule" {
    const err = ParseError.init("test", 0, 1, 1).withRule("expression");
    try std.testing.expectEqualStrings("expression", err.rule_name);
}

test "parse_error_with_context" {
    const err = ParseError.init("test", 0, 1, 1).withContext("parsing statement");
    try std.testing.expectEqualStrings("parsing statement", err.context.?);
}

test "error_list_add" {
    var list = ErrorList.init(std.testing.allocator);
    defer list.deinit();

    try list.add(ParseError.init("error 1", 0, 1, 1));
    try list.add(ParseError.init("error 2", 5, 1, 6));

    try std.testing.expectEqual(@as(usize, 2), list.count());
}

test "error_list_add_error" {
    var list = ErrorList.init(std.testing.allocator);
    defer list.deinit();

    try list.addError("test error", 0, 1, 1);
    try std.testing.expect(list.hasErrors());
}

test "error_list_add_warning" {
    var list = ErrorList.init(std.testing.allocator);
    defer list.deinit();

    try list.addWarning("test warning", 0, 1, 1);
    try std.testing.expect(!list.hasErrors()); // Warnings don't count as errors
}

test "error_list_has_fatal" {
    var list = ErrorList.init(std.testing.allocator);
    defer list.deinit();

    try list.add(ParseError.init("test", 0, 1, 1).withSeverity(.fatal));
    try std.testing.expect(list.hasFatalError());
}

test "error_list_clear" {
    var list = ErrorList.init(std.testing.allocator);
    defer list.deinit();

    try list.addError("error", 0, 1, 1);
    try std.testing.expectEqual(@as(usize, 1), list.count());

    list.clear();
    try std.testing.expectEqual(@as(usize, 0), list.count());
}

test "error_list_sort" {
    var list = ErrorList.init(std.testing.allocator);
    defer list.deinit();

    try list.add(ParseError.init("third", 20, 1, 21));
    try list.add(ParseError.init("first", 5, 1, 6));
    try list.add(ParseError.init("second", 10, 1, 11));

    list.sortByPosition();

    const errors = list.getErrors();
    try std.testing.expectEqual(@as(usize, 5), errors[0].position);
    try std.testing.expectEqual(@as(usize, 10), errors[1].position);
    try std.testing.expectEqual(@as(usize, 20), errors[2].position);
}

test "recovery_strategy_description" {
    try std.testing.expectEqualStrings("stop parsing", RecoveryStrategy.panic.description());
    try std.testing.expectEqualStrings("skip until sync point", RecoveryStrategy.skip_until.description());
}

test "error_recovery_init" {
    var recovery = ErrorRecovery.init(std.testing.allocator);
    defer recovery.deinit();

    try std.testing.expect(recovery.strategy == .skip_until);
    try std.testing.expect(recovery.canRecover());
}

test "error_recovery_set_strategy" {
    var recovery = ErrorRecovery.init(std.testing.allocator);
    defer recovery.deinit();

    recovery.setStrategy(.panic);
    try std.testing.expect(recovery.strategy == .panic);
    try std.testing.expect(!recovery.canRecover());
}

test "error_recovery_sync_tokens" {
    var recovery = ErrorRecovery.init(std.testing.allocator);
    defer recovery.deinit();

    try recovery.addSyncToken(";");
    try recovery.addSyncToken("}");

    try std.testing.expect(recovery.isSyncToken(";"));
    try std.testing.expect(recovery.isSyncToken("}"));
    try std.testing.expect(!recovery.isSyncToken("x"));
}

test "error_recovery_points" {
    var recovery = ErrorRecovery.init(std.testing.allocator);
    defer recovery.deinit();

    try recovery.pushRecoveryPoint(10);
    try recovery.pushRecoveryPoint(20);

    try std.testing.expectEqual(@as(?usize, 20), recovery.getRecoveryPosition());
    try std.testing.expectEqual(@as(?usize, 20), recovery.popRecoveryPoint());
    try std.testing.expectEqual(@as(?usize, 10), recovery.popRecoveryPoint());
    try std.testing.expect(recovery.popRecoveryPoint() == null);
}

test "error_recovery_attempts" {
    var recovery = ErrorRecovery.init(std.testing.allocator);
    defer recovery.deinit();

    recovery.max_recovery_attempts = 3;

    try std.testing.expect(recovery.attemptRecovery());
    try std.testing.expect(recovery.attemptRecovery());
    try std.testing.expect(recovery.attemptRecovery());
    try std.testing.expect(!recovery.attemptRecovery());

    recovery.resetAttempts();
    try std.testing.expect(recovery.attemptRecovery());
}

test "expected_tracker_add" {
    var tracker = ExpectedTracker.init(std.testing.allocator);
    defer tracker.deinit();

    try tracker.add(5, "number");
    try tracker.add(5, "string");

    try std.testing.expectEqual(@as(usize, 2), tracker.count());
}

test "expected_tracker_furthest_position" {
    var tracker = ExpectedTracker.init(std.testing.allocator);
    defer tracker.deinit();

    try tracker.add(5, "a");
    try tracker.add(10, "b");
    try tracker.add(5, "c"); // Should be ignored (behind furthest)

    try std.testing.expectEqual(@as(usize, 1), tracker.count());
    try std.testing.expectEqual(@as(usize, 10), tracker.position);
}

test "expected_tracker_clear" {
    var tracker = ExpectedTracker.init(std.testing.allocator);
    defer tracker.deinit();

    try tracker.add(5, "token");
    tracker.clear();

    try std.testing.expectEqual(@as(usize, 0), tracker.count());
    try std.testing.expectEqual(@as(usize, 0), tracker.position);
}

test "parse_error_format" {
    const err = ParseError.init("unexpected token", 10, 2, 5)
        .withExpected("identifier", "number");

    const formatted = try err.format(std.testing.allocator);
    defer std.testing.allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "line 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "column 5") != null);
}
