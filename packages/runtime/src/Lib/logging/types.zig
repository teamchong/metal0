//! Log levels and LogRecord type
//!
//! Defines the log level constants and the LogRecord struct that represents
//! a logging event with metadata.

const std = @import("std");

// ============================================================================
// Log Levels
// ============================================================================

pub const CRITICAL = 50;
pub const FATAL = CRITICAL;
pub const ERROR = 40;
pub const WARNING = 30;
pub const WARN = WARNING;
pub const INFO = 20;
pub const DEBUG = 10;
pub const NOTSET = 0;

/// Get level name from number
pub fn getLevelName(level: i32) []const u8 {
    return switch (level) {
        CRITICAL => "CRITICAL",
        ERROR => "ERROR",
        WARNING => "WARNING",
        INFO => "INFO",
        DEBUG => "DEBUG",
        NOTSET => "NOTSET",
        else => "UNKNOWN",
    };
}

/// Get level number from name
pub fn getLevelFromName(name: []const u8) i32 {
    if (std.mem.eql(u8, name, "CRITICAL") or std.mem.eql(u8, name, "FATAL")) return CRITICAL;
    if (std.mem.eql(u8, name, "ERROR")) return ERROR;
    if (std.mem.eql(u8, name, "WARNING") or std.mem.eql(u8, name, "WARN")) return WARNING;
    if (std.mem.eql(u8, name, "INFO")) return INFO;
    if (std.mem.eql(u8, name, "DEBUG")) return DEBUG;
    if (std.mem.eql(u8, name, "NOTSET")) return NOTSET;
    return NOTSET;
}

// ============================================================================
// LogRecord - Represents a logging event
// ============================================================================

/// Information about a logging event
pub const LogRecord = struct {
    const Self = @This();

    name: []const u8,
    level: i32,
    levelname: []const u8,
    msg: []const u8,
    pathname: []const u8 = "",
    filename: []const u8 = "",
    module_name: []const u8 = "",
    lineno: i32 = 0,
    funcname: []const u8 = "",
    created: i64,
    thread: ?std.Thread.Id = null,
    process: i32 = 0,
    exc_info: ?[]const u8 = null,
    exc_text: ?[]const u8 = null,
    stack_info: ?[]const u8 = null,

    pub fn init(name: []const u8, level: i32, msg: []const u8) Self {
        return .{
            .name = name,
            .level = level,
            .levelname = getLevelName(level),
            .msg = msg,
            .created = std.time.timestamp(),
        };
    }

    /// Get formatted message
    pub fn getMessage(self: Self) []const u8 {
        return self.msg;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "LogRecord" {
    const record = LogRecord.init("test", INFO, "Hello, World!");

    try std.testing.expectEqualStrings("test", record.name);
    try std.testing.expectEqual(INFO, record.level);
    try std.testing.expectEqualStrings("INFO", record.levelname);
    try std.testing.expectEqualStrings("Hello, World!", record.getMessage());
}

test "getLevelName" {
    try std.testing.expectEqualStrings("DEBUG", getLevelName(DEBUG));
    try std.testing.expectEqualStrings("INFO", getLevelName(INFO));
    try std.testing.expectEqualStrings("WARNING", getLevelName(WARNING));
    try std.testing.expectEqualStrings("ERROR", getLevelName(ERROR));
    try std.testing.expectEqualStrings("CRITICAL", getLevelName(CRITICAL));
}

test "getLevelFromName" {
    try std.testing.expectEqual(DEBUG, getLevelFromName("DEBUG"));
    try std.testing.expectEqual(INFO, getLevelFromName("INFO"));
    try std.testing.expectEqual(WARNING, getLevelFromName("WARNING"));
    try std.testing.expectEqual(ERROR, getLevelFromName("ERROR"));
    try std.testing.expectEqual(CRITICAL, getLevelFromName("CRITICAL"));
}

test "constants" {
    try std.testing.expectEqual(@as(i32, 50), CRITICAL);
    try std.testing.expectEqual(@as(i32, 40), ERROR);
    try std.testing.expectEqual(@as(i32, 30), WARNING);
    try std.testing.expectEqual(@as(i32, 20), INFO);
    try std.testing.expectEqual(@as(i32, 10), DEBUG);
    try std.testing.expectEqual(@as(i32, 0), NOTSET);
}
