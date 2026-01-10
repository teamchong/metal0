//! asyncio.log - Logging for asyncio
//! Reference: cpython/Lib/asyncio/log.py

const std = @import("std");

/// Logger level
pub const LogLevel = enum(u8) {
    DEBUG = 10,
    INFO = 20,
    WARNING = 30,
    ERROR = 40,
    CRITICAL = 50,
};

/// Logger for asyncio module
/// CPython: logger = logging.getLogger('asyncio')
pub const Logger = struct {
    level: LogLevel,
    name: []const u8,

    pub fn init(name: []const u8) Logger {
        return .{
            .level = .WARNING,
            .name = name,
        };
    }

    pub fn setLevel(self: *Logger, level: LogLevel) void {
        self.level = level;
    }

    pub fn debug(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.DEBUG)) {
            self.log("DEBUG", fmt, args);
        }
    }

    pub fn info(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.INFO)) {
            self.log("INFO", fmt, args);
        }
    }

    pub fn warning(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.WARNING)) {
            self.log("WARNING", fmt, args);
        }
    }

    pub fn err(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.ERROR)) {
            self.log("ERROR", fmt, args);
        }
    }

    pub fn critical(self: *Logger, comptime fmt: []const u8, args: anytype) void {
        self.log("CRITICAL", fmt, args);
    }

    fn log(self: *Logger, level: []const u8, comptime fmt: []const u8, args: anytype) void {
        std.debug.print("[{s}] {s}: " ++ fmt ++ "\n", .{ level, self.name } ++ args);
    }
};

/// Global asyncio logger
pub var logger = Logger.init("asyncio");

// Tests
test "Logger creation" {
    var log = Logger.init("test");
    try std.testing.expectEqual(LogLevel.WARNING, log.level);

    log.setLevel(.DEBUG);
    try std.testing.expectEqual(LogLevel.DEBUG, log.level);
}
