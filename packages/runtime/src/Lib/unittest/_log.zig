//! unittest._log - Logging support for unittest
//! Reference: cpython/Lib/unittest/_log.py
//!
//! CPython exports: _AssertLogsContext, _CapturingHandler
//!
//! Provides logging capture functionality for assertLogs/assertNoLogs.

const std = @import("std");

// ============================================================================
// Log Record
// ============================================================================

/// A captured log record
/// CPython: logging.LogRecord
pub const LogRecord = struct {
    /// Logger name
    name: []const u8,
    /// Log level (DEBUG=10, INFO=20, WARNING=30, ERROR=40, CRITICAL=50)
    level: u8,
    /// Log message
    message: []const u8,
    /// Formatted message
    formatted: []const u8,
    /// Timestamp
    created: i64,
    /// Source filename
    filename: []const u8 = "",
    /// Source line number
    lineno: usize = 0,
    /// Function name
    funcName: []const u8 = "",
};

// ============================================================================
// Log Levels (CPython logging module constants)
// ============================================================================

pub const DEBUG: u8 = 10;
pub const INFO: u8 = 20;
pub const WARNING: u8 = 30;
pub const ERROR: u8 = 40;
pub const CRITICAL: u8 = 50;
pub const NOTSET: u8 = 0;

/// Convert level name to number
pub fn getLevelNum(level_name: []const u8) u8 {
    if (std.mem.eql(u8, level_name, "DEBUG")) return DEBUG;
    if (std.mem.eql(u8, level_name, "INFO")) return INFO;
    if (std.mem.eql(u8, level_name, "WARNING")) return WARNING;
    if (std.mem.eql(u8, level_name, "WARN")) return WARNING;
    if (std.mem.eql(u8, level_name, "ERROR")) return ERROR;
    if (std.mem.eql(u8, level_name, "CRITICAL")) return CRITICAL;
    if (std.mem.eql(u8, level_name, "FATAL")) return CRITICAL;
    return NOTSET;
}

/// Convert level number to name
pub fn getLevelName(level: u8) []const u8 {
    return switch (level) {
        DEBUG => "DEBUG",
        INFO => "INFO",
        WARNING => "WARNING",
        ERROR => "ERROR",
        CRITICAL => "CRITICAL",
        else => "NOTSET",
    };
}

// ============================================================================
// Capturing Handler
// ============================================================================

/// CPython: class _CapturingHandler(logging.Handler)
/// A logging handler that captures log records for assertion testing.
pub const CapturingHandler = struct {
    records: std.ArrayListUnmanaged(LogRecord) = .{},
    level: u8 = NOTSET,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CapturingHandler {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CapturingHandler) void {
        self.records.deinit(self.allocator);
    }

    /// CPython: def emit(self, record)
    /// Capture a log record
    pub fn emit(self: *CapturingHandler, record: LogRecord) !void {
        if (record.level >= self.level) {
            try self.records.append(self.allocator, record);
        }
    }

    /// CPython: def flush(self)
    /// Flush is a no-op for capturing handler
    pub fn flush(_: *CapturingHandler) void {}

    /// CPython: def close(self)
    /// Close the handler
    pub fn close(self: *CapturingHandler) void {
        self.records.deinit(self.allocator);
        self.records = .{};
    }

    /// Get all captured output as strings
    pub fn getOutput(self: *const CapturingHandler) []const LogRecord {
        return self.records.items;
    }

    /// Clear captured records
    pub fn reset(self: *CapturingHandler) void {
        self.records.clearRetainingCapacity();
    }
};

// ============================================================================
// Assert Logs Context
// ============================================================================

/// CPython: class _AssertLogsContext
/// Context manager for assertLogs and assertNoLogs.
pub const AssertLogsContext = struct {
    /// Logger name to monitor
    logger_name: ?[]const u8,
    /// Minimum level to capture
    level: u8 = INFO,
    /// Captured log records
    records: std.ArrayListUnmanaged(LogRecord) = .{},
    /// Captured log output (formatted messages)
    output: std.ArrayListUnmanaged([]const u8) = .{},
    /// The capturing handler
    handler: CapturingHandler,
    /// Whether to assert no logs (for assertNoLogs)
    no_logs: bool = false,
    /// Allocator
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        logger_name: ?[]const u8,
        level: u8,
        no_logs: bool,
    ) AssertLogsContext {
        return .{
            .allocator = allocator,
            .logger_name = logger_name,
            .level = level,
            .no_logs = no_logs,
            .handler = CapturingHandler.init(allocator),
        };
    }

    pub fn deinit(self: *AssertLogsContext) void {
        self.handler.deinit();
        self.records.deinit(self.allocator);
        self.output.deinit(self.allocator);
    }

    /// CPython: def __enter__(self)
    /// Enter the context - start capturing logs
    pub fn __enter__(self: *AssertLogsContext) *AssertLogsContext {
        self.handler.level = self.level;
        // In a real implementation, we'd install the handler on the logger
        // For AOT, logging capture is handled at compile time
        return self;
    }

    /// CPython: def __exit__(self, exc_type, exc_value, tb)
    /// Exit the context - stop capturing and check assertions
    pub fn __exit__(
        self: *AssertLogsContext,
        exc_type: anytype,
        exc_value: anytype,
        tb: anytype,
    ) !bool {
        _ = exc_type;
        _ = exc_value;
        _ = tb;

        // Copy captured records
        for (self.handler.records.items) |record| {
            try self.records.append(self.allocator, record);
            try self.output.append(self.allocator, record.formatted);
        }

        // Check assertions
        if (self.no_logs) {
            if (self.records.items.len > 0) {
                return error.UnexpectedLogsDetected;
            }
        } else {
            if (self.records.items.len == 0) {
                return error.NoLogsDetected;
            }
        }

        return false; // Don't suppress exceptions
    }
};

// ============================================================================
// Helper Functions
// ============================================================================

/// Create a log record
pub fn createLogRecord(
    name: []const u8,
    level: u8,
    message: []const u8,
    allocator: std.mem.Allocator,
) !LogRecord {
    const formatted = try std.fmt.allocPrint(
        allocator,
        "{s}:{s}:{s}",
        .{ getLevelName(level), name, message },
    );
    return LogRecord{
        .name = name,
        .level = level,
        .message = message,
        .formatted = formatted,
        .created = std.time.timestamp(),
    };
}

// ============================================================================
// Tests
// ============================================================================

test "CapturingHandler basic" {
    const allocator = std.testing.allocator;
    var handler = CapturingHandler.init(allocator);
    defer handler.deinit();

    handler.level = INFO;
    try handler.emit(.{
        .name = "test",
        .level = INFO,
        .message = "test message",
        .formatted = "INFO:test:test message",
        .created = 0,
    });

    try std.testing.expectEqual(@as(usize, 1), handler.records.items.len);
}

test "getLevelNum" {
    try std.testing.expectEqual(DEBUG, getLevelNum("DEBUG"));
    try std.testing.expectEqual(INFO, getLevelNum("INFO"));
    try std.testing.expectEqual(WARNING, getLevelNum("WARNING"));
    try std.testing.expectEqual(ERROR, getLevelNum("ERROR"));
    try std.testing.expectEqual(CRITICAL, getLevelNum("CRITICAL"));
}

test "getLevelName" {
    try std.testing.expectEqualStrings("DEBUG", getLevelName(DEBUG));
    try std.testing.expectEqualStrings("INFO", getLevelName(INFO));
    try std.testing.expectEqualStrings("WARNING", getLevelName(WARNING));
}

test "AssertLogsContext init" {
    const allocator = std.testing.allocator;
    var ctx = AssertLogsContext.init(allocator, "test.logger", INFO, false);
    defer ctx.deinit();

    try std.testing.expectEqual(INFO, ctx.level);
    try std.testing.expect(!ctx.no_logs);
}
