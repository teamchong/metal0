//! test.test_concurrent_futures.test_exception - Exception handling tests
//!
//! Tests for exception handling in futures including exception propagation,
//! exception chaining, and exception info extraction.

const std = @import("std");
const testing = std.testing;

/// Error types for exception handling
pub const ExceptionError = error{
    ExceptionNotSet,
    ExceptionAlreadySet,
    InvalidExceptionType,
    ChainedExceptionLoop,
    ExceptionReraise,
};

/// Exception severity levels
pub const ExceptionSeverity = enum(u8) {
    warning = 0,
    error_ = 1,
    critical = 2,
    fatal = 3,

    pub fn isRecoverable(self: ExceptionSeverity) bool {
        return self == .warning or self == .error_;
    }

    pub fn shouldAbort(self: ExceptionSeverity) bool {
        return self == .fatal;
    }

    pub fn level(self: ExceptionSeverity) u8 {
        return @intFromEnum(self);
    }
};

/// Exception info structure with full context
pub const ExceptionInfo = struct {
    const Self = @This();

    err: anyerror,
    message: ?[]const u8 = null,
    traceback: ?[]const u8 = null,
    severity: ExceptionSeverity = .error_,
    timestamp: i64,
    cause: ?*const Self = null,
    context: ?*const anyopaque = null,

    pub fn init(err: anyerror) Self {
        return .{
            .err = err,
            .timestamp = std.time.milliTimestamp(),
        };
    }

    pub fn withMessage(err: anyerror, message: []const u8) Self {
        return .{
            .err = err,
            .message = message,
            .timestamp = std.time.milliTimestamp(),
        };
    }

    pub fn withSeverity(err: anyerror, severity: ExceptionSeverity) Self {
        return .{
            .err = err,
            .severity = severity,
            .timestamp = std.time.milliTimestamp(),
        };
    }

    pub fn withCause(err: anyerror, cause: *const Self) Self {
        return .{
            .err = err,
            .cause = cause,
            .timestamp = std.time.milliTimestamp(),
        };
    }

    pub fn getErrorName(self: Self) []const u8 {
        return @errorName(self.err);
    }

    pub fn hasCause(self: Self) bool {
        return self.cause != null;
    }

    pub fn getCauseChainLength(self: Self) usize {
        var length: usize = 0;
        var current: ?*const Self = self.cause;
        while (current) |c| {
            length += 1;
            current = c.cause;
        }
        return length;
    }

    pub fn getRootCause(self: *const Self) *const Self {
        var current: *const Self = self;
        while (current.cause) |c| {
            current = c;
        }
        return current;
    }

    pub fn format(self: Self, allocator: std.mem.Allocator) ![]const u8 {
        var parts = std.ArrayList(u8).init(allocator);
        defer parts.deinit();

        const writer = parts.writer();

        try writer.print("{s}", .{self.getErrorName()});
        if (self.message) |msg| {
            try writer.print(": {s}", .{msg});
        }

        return try parts.toOwnedSlice();
    }
};

/// Exception handler for managing caught exceptions
pub const ExceptionHandler = struct {
    const Self = @This();

    handled_count: usize = 0,
    suppressed_count: usize = 0,
    reraised_count: usize = 0,
    current_exception: ?ExceptionInfo = null,
    suppression_enabled: bool = false,

    pub fn init() Self {
        return .{};
    }

    pub fn handle(self: *Self, exc: ExceptionInfo) void {
        self.current_exception = exc;
        self.handled_count += 1;
    }

    pub fn suppress(self: *Self, exc: ExceptionInfo) void {
        _ = exc;
        self.suppressed_count += 1;
    }

    pub fn reraise(self: *Self) ExceptionError!void {
        if (self.current_exception == null) {
            return ExceptionError.ExceptionNotSet;
        }
        self.reraised_count += 1;
        return ExceptionError.ExceptionReraise;
    }

    pub fn clear(self: *Self) void {
        self.current_exception = null;
    }

    pub fn hasException(self: Self) bool {
        return self.current_exception != null;
    }

    pub fn getStats(self: Self) ExceptionStats {
        return .{
            .handled = self.handled_count,
            .suppressed = self.suppressed_count,
            .reraised = self.reraised_count,
        };
    }
};

/// Statistics for exception handling
pub const ExceptionStats = struct {
    handled: usize = 0,
    suppressed: usize = 0,
    reraised: usize = 0,

    pub fn total(self: ExceptionStats) usize {
        return self.handled + self.suppressed;
    }

    pub fn suppressionRate(self: ExceptionStats) f64 {
        const t = self.total();
        if (t == 0) return 0;
        return @as(f64, @floatFromInt(self.suppressed)) / @as(f64, @floatFromInt(t));
    }
};

/// Future with exception support
pub fn ExceptionFuture(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const State = enum {
            pending,
            running,
            completed,
            failed,
            cancelled,
        };

        id: u64,
        state: State = .pending,
        result: ?T = null,
        exception_info: ?ExceptionInfo = null,
        creation_time: i64,

        pub fn init(id: u64) Self {
            return .{
                .id = id,
                .creation_time = std.time.milliTimestamp(),
            };
        }

        pub fn setResult(self: *Self, value: T) ExceptionError!void {
            if (self.exception_info != null) {
                return ExceptionError.ExceptionAlreadySet;
            }
            self.result = value;
            self.state = .completed;
        }

        pub fn setException(self: *Self, err: anyerror) ExceptionError!void {
            return self.setExceptionInfo(ExceptionInfo.init(err));
        }

        pub fn setExceptionInfo(self: *Self, exc: ExceptionInfo) ExceptionError!void {
            if (self.result != null) {
                return ExceptionError.ExceptionAlreadySet;
            }
            self.exception_info = exc;
            self.state = .failed;
        }

        pub fn setExceptionWithMessage(self: *Self, err: anyerror, message: []const u8) ExceptionError!void {
            return self.setExceptionInfo(ExceptionInfo.withMessage(err, message));
        }

        pub fn result(self: Self) anyerror!T {
            if (self.exception_info) |exc| {
                return exc.err;
            }
            if (self.result) |r| {
                return r;
            }
            return ExceptionError.ExceptionNotSet;
        }

        pub fn exception(self: Self) ?ExceptionInfo {
            return self.exception_info;
        }

        pub fn hasException(self: Self) bool {
            return self.exception_info != null;
        }

        pub fn isDone(self: Self) bool {
            return self.state == .completed or self.state == .failed or self.state == .cancelled;
        }

        pub fn getExceptionError(self: Self) ?anyerror {
            if (self.exception_info) |exc| {
                return exc.err;
            }
            return null;
        }

        pub fn getExceptionMessage(self: Self) ?[]const u8 {
            if (self.exception_info) |exc| {
                return exc.message;
            }
            return null;
        }
    };
}

/// Exception group for managing multiple exceptions
pub const ExceptionGroup = struct {
    const Self = @This();

    exceptions: std.ArrayList(ExceptionInfo),
    allocator: std.mem.Allocator,
    message: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .exceptions = std.ArrayList(ExceptionInfo).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn initWithMessage(allocator: std.mem.Allocator, message: []const u8) Self {
        return .{
            .exceptions = std.ArrayList(ExceptionInfo).init(allocator),
            .allocator = allocator,
            .message = message,
        };
    }

    pub fn deinit(self: *Self) void {
        self.exceptions.deinit();
    }

    pub fn add(self: *Self, exc: ExceptionInfo) !void {
        try self.exceptions.append(exc);
    }

    pub fn addError(self: *Self, err: anyerror) !void {
        try self.exceptions.append(ExceptionInfo.init(err));
    }

    pub fn count(self: Self) usize {
        return self.exceptions.items.len;
    }

    pub fn isEmpty(self: Self) bool {
        return self.exceptions.items.len == 0;
    }

    pub fn getFirst(self: Self) ?ExceptionInfo {
        if (self.exceptions.items.len == 0) return null;
        return self.exceptions.items[0];
    }

    pub fn getLast(self: Self) ?ExceptionInfo {
        if (self.exceptions.items.len == 0) return null;
        return self.exceptions.items[self.exceptions.items.len - 1];
    }

    pub fn getBySeverity(self: Self, severity: ExceptionSeverity) []ExceptionInfo {
        var matching = std.ArrayList(ExceptionInfo).init(self.allocator);
        for (self.exceptions.items) |exc| {
            if (exc.severity == severity) {
                matching.append(exc) catch {};
            }
        }
        return matching.items;
    }

    pub fn hasFatal(self: Self) bool {
        for (self.exceptions.items) |exc| {
            if (exc.severity == .fatal) return true;
        }
        return false;
    }

    pub fn getMaxSeverity(self: Self) ?ExceptionSeverity {
        var max: ?ExceptionSeverity = null;
        for (self.exceptions.items) |exc| {
            if (max == null or exc.severity.level() > max.?.level()) {
                max = exc.severity;
            }
        }
        return max;
    }

    pub fn clear(self: *Self) void {
        self.exceptions.clearRetainingCapacity();
    }
};

/// Exception filter for selective handling
pub const ExceptionFilter = struct {
    const Self = @This();

    allowed_errors: std.ArrayList(anyerror),
    blocked_errors: std.ArrayList(anyerror),
    min_severity: ExceptionSeverity = .warning,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allowed_errors = std.ArrayList(anyerror).init(allocator),
            .blocked_errors = std.ArrayList(anyerror).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allowed_errors.deinit();
        self.blocked_errors.deinit();
    }

    pub fn allow(self: *Self, err: anyerror) !void {
        try self.allowed_errors.append(err);
    }

    pub fn block(self: *Self, err: anyerror) !void {
        try self.blocked_errors.append(err);
    }

    pub fn setMinSeverity(self: *Self, severity: ExceptionSeverity) void {
        self.min_severity = severity;
    }

    pub fn shouldHandle(self: Self, exc: ExceptionInfo) bool {
        // Check blocked list first
        for (self.blocked_errors.items) |blocked| {
            if (blocked == exc.err) return false;
        }

        // Check severity
        if (exc.severity.level() < self.min_severity.level()) return false;

        // If allowed list is empty, handle all non-blocked
        if (self.allowed_errors.items.len == 0) return true;

        // Check allowed list
        for (self.allowed_errors.items) |allowed| {
            if (allowed == exc.err) return true;
        }

        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "exception_severity_levels" {
    try testing.expect(ExceptionSeverity.warning.isRecoverable());
    try testing.expect(ExceptionSeverity.error_.isRecoverable());
    try testing.expect(!ExceptionSeverity.critical.isRecoverable());
    try testing.expect(!ExceptionSeverity.fatal.isRecoverable());

    try testing.expect(!ExceptionSeverity.warning.shouldAbort());
    try testing.expect(ExceptionSeverity.fatal.shouldAbort());
}

test "exception_info_basic" {
    const exc = ExceptionInfo.init(error.SomeError);

    try testing.expectEqual(error.SomeError, exc.err);
    try testing.expectEqual(ExceptionSeverity.error_, exc.severity);
    try testing.expect(!exc.hasCause());
}

test "exception_info_with_message" {
    const exc = ExceptionInfo.withMessage(error.ValueError, "Invalid input");

    try testing.expectEqual(error.ValueError, exc.err);
    try testing.expectEqualStrings("Invalid input", exc.message.?);
}

test "exception_info_with_severity" {
    const exc = ExceptionInfo.withSeverity(error.CriticalError, .critical);

    try testing.expectEqual(ExceptionSeverity.critical, exc.severity);
    try testing.expect(!exc.severity.isRecoverable());
}

test "exception_info_chain" {
    const root = ExceptionInfo.init(error.RootCause);
    const middle = ExceptionInfo.withCause(error.MiddleError, &root);
    const top = ExceptionInfo.withCause(error.TopError, &middle);

    try testing.expect(top.hasCause());
    try testing.expectEqual(@as(usize, 2), top.getCauseChainLength());

    const found_root = top.getRootCause();
    try testing.expectEqual(error.RootCause, found_root.err);
}

test "exception_info_format" {
    const exc = ExceptionInfo.withMessage(error.TestError, "something went wrong");
    const formatted = try exc.format(testing.allocator);
    defer testing.allocator.free(formatted);

    try testing.expectEqualStrings("TestError: something went wrong", formatted);
}

test "exception_handler_basic" {
    var handler = ExceptionHandler.init();

    try testing.expect(!handler.hasException());

    handler.handle(ExceptionInfo.init(error.SomeError));
    try testing.expect(handler.hasException());
    try testing.expectEqual(@as(usize, 1), handler.handled_count);

    handler.clear();
    try testing.expect(!handler.hasException());
}

test "exception_handler_reraise" {
    var handler = ExceptionHandler.init();

    // Cannot reraise without exception
    try testing.expectError(ExceptionError.ExceptionNotSet, handler.reraise());

    handler.handle(ExceptionInfo.init(error.SomeError));
    try testing.expectError(ExceptionError.ExceptionReraise, handler.reraise());
    try testing.expectEqual(@as(usize, 1), handler.reraised_count);
}

test "exception_handler_stats" {
    var handler = ExceptionHandler.init();

    handler.handle(ExceptionInfo.init(error.E1));
    handler.handle(ExceptionInfo.init(error.E2));
    handler.suppress(ExceptionInfo.init(error.E3));

    const stats = handler.getStats();
    try testing.expectEqual(@as(usize, 2), stats.handled);
    try testing.expectEqual(@as(usize, 1), stats.suppressed);
    try testing.expectEqual(@as(usize, 3), stats.total());
    try testing.expectApproxEqAbs(@as(f64, 0.333), stats.suppressionRate(), 0.01);
}

test "exception_future_basic" {
    var future = ExceptionFuture(i32).init(1);

    try testing.expect(!future.hasException());
    try testing.expect(!future.isDone());

    try future.setResult(42);
    try testing.expect(future.isDone());
    try testing.expect(!future.hasException());
    try testing.expectEqual(@as(i32, 42), try future.result());
}

test "exception_future_with_exception" {
    var future = ExceptionFuture(i32).init(1);

    try future.setException(error.TaskFailed);
    try testing.expect(future.hasException());
    try testing.expect(future.isDone());
    try testing.expectEqual(error.TaskFailed, future.getExceptionError().?);
    try testing.expectError(error.TaskFailed, future.result());
}

test "exception_future_with_message" {
    var future = ExceptionFuture(i32).init(1);

    try future.setExceptionWithMessage(error.ValidationError, "Invalid data");
    try testing.expectEqualStrings("Invalid data", future.getExceptionMessage().?);
}

test "exception_future_cannot_set_both" {
    var future = ExceptionFuture(i32).init(1);

    try future.setResult(42);
    try testing.expectError(ExceptionError.ExceptionAlreadySet, future.setException(error.SomeError));
}

test "exception_group_basic" {
    var group = ExceptionGroup.init(testing.allocator);
    defer group.deinit();

    try testing.expect(group.isEmpty());

    try group.addError(error.Error1);
    try group.addError(error.Error2);

    try testing.expectEqual(@as(usize, 2), group.count());
    try testing.expect(!group.isEmpty());
}

test "exception_group_severity" {
    var group = ExceptionGroup.init(testing.allocator);
    defer group.deinit();

    try group.add(ExceptionInfo.withSeverity(error.E1, .warning));
    try group.add(ExceptionInfo.withSeverity(error.E2, .critical));
    try group.add(ExceptionInfo.withSeverity(error.E3, .error_));

    try testing.expect(!group.hasFatal());
    try testing.expectEqual(ExceptionSeverity.critical, group.getMaxSeverity().?);

    try group.add(ExceptionInfo.withSeverity(error.E4, .fatal));
    try testing.expect(group.hasFatal());
    try testing.expectEqual(ExceptionSeverity.fatal, group.getMaxSeverity().?);
}

test "exception_filter_basic" {
    var filter = ExceptionFilter.init(testing.allocator);
    defer filter.deinit();

    try filter.allow(error.AllowedError);
    try filter.block(error.BlockedError);

    const allowed_exc = ExceptionInfo.init(error.AllowedError);
    const blocked_exc = ExceptionInfo.init(error.BlockedError);
    const other_exc = ExceptionInfo.init(error.OtherError);

    try testing.expect(filter.shouldHandle(allowed_exc));
    try testing.expect(!filter.shouldHandle(blocked_exc));
    try testing.expect(!filter.shouldHandle(other_exc)); // Not in allowed list
}

test "exception_filter_min_severity" {
    var filter = ExceptionFilter.init(testing.allocator);
    defer filter.deinit();

    filter.setMinSeverity(.critical);

    const warning = ExceptionInfo.withSeverity(error.E1, .warning);
    const critical = ExceptionInfo.withSeverity(error.E2, .critical);

    try testing.expect(!filter.shouldHandle(warning));
    try testing.expect(filter.shouldHandle(critical));
}

test "exception_group_first_last" {
    var group = ExceptionGroup.init(testing.allocator);
    defer group.deinit();

    try testing.expect(group.getFirst() == null);
    try testing.expect(group.getLast() == null);

    try group.addError(error.First);
    try group.addError(error.Middle);
    try group.addError(error.Last);

    try testing.expectEqual(error.First, group.getFirst().?.err);
    try testing.expectEqual(error.Last, group.getLast().?.err);
}
