//! Logger and Manager implementations
//!
//! Logger represents a single logging channel with configurable level,
//! handlers, and hierarchy support. Manager maintains the logger hierarchy.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");
const handler_mod = @import("handler.zig");

const LogRecord = types.LogRecord;
const StreamHandler = handler_mod.StreamHandler;
const FileHandler = handler_mod.FileHandler;
const NOTSET = types.NOTSET;
const WARNING = types.WARNING;
const DEBUG = types.DEBUG;
const INFO = types.INFO;
const ERROR = types.ERROR;
const CRITICAL = types.CRITICAL;

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
            .handlers = .{},
            .file_handlers = .{},
            .propagate = true,
            .disabled = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.handlers.deinit(self.allocator);
        self.file_handlers.deinit(self.allocator);
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
    pub fn addHandler(self: *Self, h: *StreamHandler) !void {
        try self.handlers.append(self.allocator, h);
    }

    /// Add a file handler
    pub fn addFileHandler(self: *Self, h: *FileHandler) !void {
        try self.file_handlers.append(self.allocator, h);
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
        for (self.handlers.items) |h| {
            try h.emit(record);
        }
        for (self.file_handlers.items) |h| {
            try h.emit(record);
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
    loggers: hashmap_helper.StringHashMap(*Logger),

    pub fn init(allocator: std.mem.Allocator, root: *Logger) Self {
        return .{
            .allocator = allocator,
            .root = root,
            .loggers = hashmap_helper.StringHashMap(*Logger).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.loggers.deinit();
    }

    /// Get or create a logger
    pub fn getLogger(self: *Self, name: []const u8) !*Logger {
        if (self.loggers.get(name)) |l| {
            return l;
        }

        const l = try self.allocator.create(Logger);
        l.* = Logger.init(self.allocator, name, NOTSET);
        l.parent = self.root;

        try self.loggers.put(name, l);
        return l;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Logger levels" {
    const allocator = std.testing.allocator;

    var logger = Logger.init(allocator, "test", INFO);
    defer logger.deinit();

    try std.testing.expect(logger.isEnabledFor(INFO));
    try std.testing.expect(logger.isEnabledFor(WARNING));
    try std.testing.expect(!logger.isEnabledFor(DEBUG));
}
