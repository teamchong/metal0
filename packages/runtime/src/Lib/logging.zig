//! Python 'logging' module - Logging facility for Python
//!
//! Provides a flexible event logging system for applications and libraries.
//!
//! Mirrors: CPython Lib/logging/__init__.py
//!
//! This module has been refactored into a modular directory structure:
//! - types.zig - Log levels and LogRecord
//! - filter.zig - Log record filtering
//! - formatter.zig - Log record formatting
//! - handler.zig - Handler base and concrete handlers
//! - logger.zig - Logger and Manager implementations

const std = @import("std");

// Re-export all submodules
pub const types = @import("logging/types.zig");
pub const filter = @import("logging/filter.zig");
pub const formatter = @import("logging/formatter.zig");
pub const handler = @import("logging/handler.zig");
pub const logger = @import("logging/logger.zig");

// Re-export commonly used types and constants
pub const CRITICAL = types.CRITICAL;
pub const FATAL = types.FATAL;
pub const ERROR = types.ERROR;
pub const WARNING = types.WARNING;
pub const WARN = types.WARN;
pub const INFO = types.INFO;
pub const DEBUG = types.DEBUG;
pub const NOTSET = types.NOTSET;

pub const getLevelName = types.getLevelName;
pub const getLevelFromName = types.getLevelFromName;

pub const LogRecord = types.LogRecord;
pub const Filter = filter.Filter;
pub const Formatter = formatter.Formatter;
pub const Handler = handler.Handler;
pub const StreamHandler = handler.StreamHandler;
pub const FileHandler = handler.FileHandler;
pub const NullHandler = handler.NullHandler;
pub const Logger = logger.Logger;
pub const Manager = logger.Manager;

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

    const h = try allocator.create(StreamHandler);
    h.* = StreamHandler.init(allocator);

    const fmt = try allocator.create(Formatter);
    fmt.* = Formatter.init(allocator, null, null);
    h.handler.setFormatter(fmt);

    try root_logger.?.addHandler(h);
}

/// Log debug message to root logger
pub fn debugLog(allocator: std.mem.Allocator, msg: []const u8) !void {
    const l = try getLogger(allocator, null);
    try l.debug(msg);
}

/// Log info message to root logger
pub fn infoLog(allocator: std.mem.Allocator, msg: []const u8) !void {
    const l = try getLogger(allocator, null);
    try l.info(msg);
}

/// Log warning message to root logger
pub fn warningLog(allocator: std.mem.Allocator, msg: []const u8) !void {
    const l = try getLogger(allocator, null);
    try l.warning(msg);
}

/// Log error message to root logger
pub fn errorLog(allocator: std.mem.Allocator, msg: []const u8) !void {
    const l = try getLogger(allocator, null);
    try l.err(msg);
}

/// Log critical message to root logger
pub fn criticalLog(allocator: std.mem.Allocator, msg: []const u8) !void {
    const l = try getLogger(allocator, null);
    try l.critical(msg);
}
