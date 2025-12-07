//! Python 'logging' module - Logging facility for Python
//!
//! Provides a flexible event logging system for applications and libraries.
//!
//! Mirrors: CPython Lib/logging/__init__.py

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
// Formatter - Formats LogRecords
// ============================================================================

/// Formats LogRecord instances into text
pub const Formatter = struct {
    const Self = @This();

    format_str: []const u8,
    datefmt: ?[]const u8,
    allocator: std.mem.Allocator,

    /// Default format: "%(levelname)s:%(name)s:%(message)s"
    pub const DEFAULT_FORMAT = "%(levelname)s:%(name)s:%(message)s";

    pub fn init(allocator: std.mem.Allocator, fmt: ?[]const u8, datefmt: ?[]const u8) Self {
        return .{
            .allocator = allocator,
            .format_str = fmt orelse DEFAULT_FORMAT,
            .datefmt = datefmt,
        };
    }

    /// Format the specified record
    pub fn format(self: *Self, record: LogRecord) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        var i: usize = 0;
        const fmt = self.format_str;

        while (i < fmt.len) {
            if (i + 1 < fmt.len and fmt[i] == '%' and fmt[i + 1] == '(') {
                // Find the closing )s
                const start = i + 2;
                var end = start;
                while (end < fmt.len and fmt[end] != ')') : (end += 1) {}

                if (end + 1 < fmt.len and fmt[end] == ')' and fmt[end + 1] == 's') {
                    const field_name = fmt[start..end];
                    const value = self.getField(record, field_name);
                    try result.appendSlice(value);
                    i = end + 2;
                    continue;
                }
            }
            try result.append(fmt[i]);
            i += 1;
        }

        return result.toOwnedSlice();
    }

    fn getField(self: *Self, record: LogRecord, field: []const u8) []const u8 {
        _ = self;
        if (std.mem.eql(u8, field, "name")) return record.name;
        if (std.mem.eql(u8, field, "levelname")) return record.levelname;
        if (std.mem.eql(u8, field, "message")) return record.msg;
        if (std.mem.eql(u8, field, "pathname")) return record.pathname;
        if (std.mem.eql(u8, field, "filename")) return record.filename;
        if (std.mem.eql(u8, field, "module")) return record.module_name;
        if (std.mem.eql(u8, field, "funcName")) return record.funcname;
        return "";
    }

    /// Format the time
    pub fn formatTime(self: *Self, record: LogRecord) ![]u8 {
        _ = record;
        // Simplified time formatting
        var buf: [32]u8 = undefined;
        const now = std.time.timestamp();
        const len = std.fmt.formatIntBuf(&buf, now, 10, .lower, .{});
        return try self.allocator.dupe(u8, buf[0..len]);
    }
};

// ============================================================================
// Filter - Controls which log records are output
// ============================================================================

/// Filters LogRecords based on criteria
pub const Filter = struct {
    const Self = @This();

    name: []const u8,
    nlen: usize,

    pub fn init(name: []const u8) Self {
        return .{
            .name = name,
            .nlen = name.len,
        };
    }

    /// Determine if the record should be logged
    pub fn filter(self: *Self, record: LogRecord) bool {
        if (self.nlen == 0) return true;
        if (std.mem.eql(u8, record.name, self.name)) return true;
        if (std.mem.startsWith(u8, record.name, self.name) and
            record.name.len > self.nlen and record.name[self.nlen] == '.')
        {
            return true;
        }
        return false;
    }
};

// ============================================================================
// Handler - Base class for log handlers
// ============================================================================

/// Handles log records
pub const Handler = struct {
    const Self = @This();

    level: i32,
    formatter: ?*Formatter,
    filters: std.ArrayList(*Filter),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, level: i32) Self {
        return .{
            .allocator = allocator,
            .level = level,
            .formatter = null,
            .filters = std.ArrayList(*Filter).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.filters.deinit();
    }

    /// Set the formatter
    pub fn setFormatter(self: *Self, formatter: *Formatter) void {
        self.formatter = formatter;
    }

    /// Add a filter
    pub fn addFilter(self: *Self, f: *Filter) !void {
        try self.filters.append(f);
    }

    /// Check if this handler should process the record
    pub fn shouldHandle(self: *Self, record: LogRecord) bool {
        if (record.level < self.level) return false;
        for (self.filters.items) |f| {
            if (!f.filter(record)) return false;
        }
        return true;
    }

    /// Format the record
    pub fn formatRecord(self: *Self, record: LogRecord) ![]u8 {
        if (self.formatter) |formatter| {
            return formatter.format(record);
        }
        return try self.allocator.dupe(u8, record.msg);
    }
};

// ============================================================================
// StreamHandler - Logs to a stream (stderr by default)
// ============================================================================

/// Writes log records to a stream
pub const StreamHandler = struct {
    const Self = @This();

    handler: Handler,
    stream: std.fs.File,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .handler = Handler.init(allocator, NOTSET),
            .stream = std.io.getStdErr(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.handler.deinit();
    }

    /// Emit a log record
    pub fn emit(self: *Self, record: LogRecord) !void {
        if (!self.handler.shouldHandle(record)) return;

        const msg = try self.handler.formatRecord(record);
        defer self.handler.allocator.free(msg);

        try self.stream.writeAll(msg);
        try self.stream.writeAll("\n");
    }

    /// Set the log level
    pub fn setLevel(self: *Self, level: i32) void {
        self.handler.level = level;
    }
};

// ============================================================================
// FileHandler - Logs to a file
// ============================================================================

/// Writes log records to a file
pub const FileHandler = struct {
    const Self = @This();

    handler: Handler,
    file: ?std.fs.File,
    filename: []const u8,
    mode: Mode,

    pub const Mode = enum { write, append };

    pub fn init(allocator: std.mem.Allocator, filename: []const u8, mode: Mode) Self {
        return .{
            .handler = Handler.init(allocator, NOTSET),
            .file = null,
            .filename = filename,
            .mode = mode,
        };
    }

    pub fn deinit(self: *Self) void {
        self.close();
        self.handler.deinit();
    }

    /// Open the file
    pub fn open(self: *Self) !void {
        self.file = switch (self.mode) {
            .write => try std.fs.cwd().createFile(self.filename, .{}),
            .append => try std.fs.cwd().openFile(self.filename, .{ .mode = .read_write }) catch
                try std.fs.cwd().createFile(self.filename, .{}),
        };
        if (self.mode == .append and self.file != null) {
            try self.file.?.seekFromEnd(0);
        }
    }

    /// Emit a log record
    pub fn emit(self: *Self, record: LogRecord) !void {
        if (!self.handler.shouldHandle(record)) return;
        if (self.file == null) try self.open();

        const msg = try self.handler.formatRecord(record);
        defer self.handler.allocator.free(msg);

        if (self.file) |f| {
            try f.writeAll(msg);
            try f.writeAll("\n");
        }
    }

    /// Close the file
    pub fn close(self: *Self) void {
        if (self.file) |*f| {
            f.close();
            self.file = null;
        }
    }

    /// Set the log level
    pub fn setLevel(self: *Self, level: i32) void {
        self.handler.level = level;
    }
};

// ============================================================================
// Logger - Main logger class
// ============================================================================

/// Represents a single logging channel
pub const Logger = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: []const u8,
    level: i32,
    parent: ?*Logger,
    handlers: std.ArrayList(*StreamHandler),
    file_handlers: std.ArrayList(*FileHandler),
    propagate: bool,
    disabled: bool,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, level: i32) Self {
        return .{
            .allocator = allocator,
            .name = name,
            .level = level,
            .parent = null,
            .handlers = std.ArrayList(*StreamHandler).init(allocator),
            .file_handlers = std.ArrayList(*FileHandler).init(allocator),
            .propagate = true,
            .disabled = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.handlers.deinit();
        self.file_handlers.deinit();
    }

    /// Set the logging level
    pub fn setLevel(self: *Self, level: i32) void {
        self.level = level;
    }

    /// Get the effective level
    pub fn getEffectiveLevel(self: *Self) i32 {
        var logger: ?*Self = self;
        while (logger) |l| {
            if (l.level != NOTSET) return l.level;
            logger = l.parent;
        }
        return NOTSET;
    }

    /// Check if the logger is enabled for a level
    pub fn isEnabledFor(self: *Self, level: i32) bool {
        if (self.disabled) return false;
        return level >= self.getEffectiveLevel();
    }

    /// Add a handler
    pub fn addHandler(self: *Self, handler: *StreamHandler) !void {
        try self.handlers.append(handler);
    }

    /// Add a file handler
    pub fn addFileHandler(self: *Self, handler: *FileHandler) !void {
        try self.file_handlers.append(handler);
    }

    /// Log at a specified level
    pub fn log(self: *Self, level: i32, msg: []const u8) !void {
        if (!self.isEnabledFor(level)) return;

        const record = LogRecord.init(self.name, level, msg);
        try self.handle(record);
    }

    /// Handle a log record
    fn handle(self: *Self, record: LogRecord) !void {
        // Call handlers
        for (self.handlers.items) |handler| {
            try handler.emit(record);
        }
        for (self.file_handlers.items) |handler| {
            try handler.emit(record);
        }

        // Propagate to parent
        if (self.propagate and self.parent != null) {
            try self.parent.?.handle(record);
        }
    }

    /// Log at DEBUG level
    pub fn debug(self: *Self, msg: []const u8) !void {
        try self.log(DEBUG, msg);
    }

    /// Log at INFO level
    pub fn info(self: *Self, msg: []const u8) !void {
        try self.log(INFO, msg);
    }

    /// Log at WARNING level
    pub fn warning(self: *Self, msg: []const u8) !void {
        try self.log(WARNING, msg);
    }

    /// Log at ERROR level
    pub fn err(self: *Self, msg: []const u8) !void {
        try self.log(ERROR, msg);
    }

    /// Log at CRITICAL level
    pub fn critical(self: *Self, msg: []const u8) !void {
        try self.log(CRITICAL, msg);
    }

    /// Log an exception
    pub fn exception(self: *Self, msg: []const u8) !void {
        try self.log(ERROR, msg);
    }
};

// ============================================================================
// Manager - Logger management
// ============================================================================

/// Manages loggers in a hierarchy
pub const Manager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    root: *Logger,
    loggers: std.StringHashMap(*Logger),

    pub fn init(allocator: std.mem.Allocator, root: *Logger) Self {
        return .{
            .allocator = allocator,
            .root = root,
            .loggers = std.StringHashMap(*Logger).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.loggers.deinit();
    }

    /// Get or create a logger
    pub fn getLogger(self: *Self, name: []const u8) !*Logger {
        if (self.loggers.get(name)) |logger| {
            return logger;
        }

        const logger = try self.allocator.create(Logger);
        logger.* = Logger.init(self.allocator, name, NOTSET);
        logger.parent = self.root;

        try self.loggers.put(name, logger);
        return logger;
    }
};

// ============================================================================
// Module-level state
// ============================================================================

var root_logger: ?*Logger = null;
var manager: ?*Manager = null;
var initialized: bool = false;

/// Initialize the logging system
pub fn init(allocator: std.mem.Allocator) !void {
    if (initialized) return;

    root_logger = try allocator.create(Logger);
    root_logger.?.* = Logger.init(allocator, "root", WARNING);

    manager = try allocator.create(Manager);
    manager.?.* = Manager.init(allocator, root_logger.?);

    initialized = true;
}

/// Get a logger
pub fn getLogger(allocator: std.mem.Allocator, name: ?[]const u8) !*Logger {
    if (!initialized) try init(allocator);

    if (name) |n| {
        return manager.?.getLogger(n);
    }
    return root_logger.?;
}

// ============================================================================
// Convenience Functions
// ============================================================================

/// Configure basic logging
pub fn basicConfig(allocator: std.mem.Allocator, level: i32) !void {
    if (!initialized) try init(allocator);

    root_logger.?.setLevel(level);

    const handler = try allocator.create(StreamHandler);
    handler.* = StreamHandler.init(allocator);

    const formatter = try allocator.create(Formatter);
    formatter.* = Formatter.init(allocator, null, null);
    handler.handler.setFormatter(formatter);

    try root_logger.?.addHandler(handler);
}

/// Log debug message to root logger
pub fn debugLog(allocator: std.mem.Allocator, msg: []const u8) !void {
    const logger = try getLogger(allocator, null);
    try logger.debug(msg);
}

/// Log info message to root logger
pub fn infoLog(allocator: std.mem.Allocator, msg: []const u8) !void {
    const logger = try getLogger(allocator, null);
    try logger.info(msg);
}

/// Log warning message to root logger
pub fn warningLog(allocator: std.mem.Allocator, msg: []const u8) !void {
    const logger = try getLogger(allocator, null);
    try logger.warning(msg);
}

/// Log error message to root logger
pub fn errorLog(allocator: std.mem.Allocator, msg: []const u8) !void {
    const logger = try getLogger(allocator, null);
    try logger.err(msg);
}

/// Log critical message to root logger
pub fn criticalLog(allocator: std.mem.Allocator, msg: []const u8) !void {
    const logger = try getLogger(allocator, null);
    try logger.critical(msg);
}

// ============================================================================
// NullHandler - Does nothing
// ============================================================================

/// A handler that does nothing
pub const NullHandler = struct {
    const Self = @This();

    handler: Handler,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .handler = Handler.init(allocator, NOTSET),
        };
    }

    pub fn emit(self: *Self, record: LogRecord) void {
        _ = self;
        _ = record;
        // Do nothing
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

test "Formatter" {
    const allocator = std.testing.allocator;

    var formatter = Formatter.init(allocator, "%(levelname)s - %(message)s", null);
    const record = LogRecord.init("test", INFO, "test message");

    const formatted = try formatter.format(record);
    defer allocator.free(formatted);

    try std.testing.expectEqualStrings("INFO - test message", formatted);
}

test "Filter" {
    var f = Filter.init("myapp");

    const record1 = LogRecord.init("myapp", INFO, "msg");
    const record2 = LogRecord.init("myapp.sub", INFO, "msg");
    const record3 = LogRecord.init("other", INFO, "msg");

    try std.testing.expect(f.filter(record1));
    try std.testing.expect(f.filter(record2));
    try std.testing.expect(!f.filter(record3));
}

test "Logger levels" {
    const allocator = std.testing.allocator;

    var logger = Logger.init(allocator, "test", INFO);
    defer logger.deinit();

    try std.testing.expect(logger.isEnabledFor(INFO));
    try std.testing.expect(logger.isEnabledFor(WARNING));
    try std.testing.expect(!logger.isEnabledFor(DEBUG));
}

test "constants" {
    try std.testing.expectEqual(@as(i32, 50), CRITICAL);
    try std.testing.expectEqual(@as(i32, 40), ERROR);
    try std.testing.expectEqual(@as(i32, 30), WARNING);
    try std.testing.expectEqual(@as(i32, 20), INFO);
    try std.testing.expectEqual(@as(i32, 10), DEBUG);
    try std.testing.expectEqual(@as(i32, 0), NOTSET);
}
