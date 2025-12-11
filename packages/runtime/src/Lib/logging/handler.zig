//! Log handlers
//!
//! Handlers process log records by formatting and outputting them to
//! various destinations (streams, files, etc.).

const std = @import("std");
const types = @import("types.zig");
const formatter_mod = @import("formatter.zig");
const filter_mod = @import("filter.zig");

const LogRecord = types.LogRecord;
const Formatter = formatter_mod.Formatter;
const Filter = filter_mod.Filter;
const NOTSET = types.NOTSET;

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
    pub fn setFormatter(self: *Self, fmt: *Formatter) void {
        self.formatter = fmt;
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
        if (self.formatter) |fmt| {
            return fmt.format(record);
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
