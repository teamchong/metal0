//! logging.handlers - Additional handlers for logging
//! Reference: cpython/Lib/logging/handlers.py
//!
//! CPython __all__: BaseRotatingHandler, RotatingFileHandler, TimedRotatingFileHandler,
//!                  WatchedFileHandler, SocketHandler, DatagramHandler, SysLogHandler,
//!                  NTEventLogHandler, SMTPHandler, MemoryHandler, HTTPHandler,
//!                  QueueHandler, QueueListener
//!
//! Additional handlers for the logging module.

const std = @import("std");
const logging = @import("../logging.zig");

/// Default TCP logging port
pub const DEFAULT_TCP_LOGGING_PORT: u16 = 9020;

/// Default UDP logging port
pub const DEFAULT_UDP_LOGGING_PORT: u16 = 9021;

/// Default HTTP logging port
pub const DEFAULT_HTTP_LOGGING_PORT: u16 = 9022;

/// Default SOAP logging port
pub const DEFAULT_SOAP_LOGGING_PORT: u16 = 9023;

/// Syslog facility codes
pub const SysLogFacility = enum(u8) {
    LOG_KERN = 0,
    LOG_USER = 1,
    LOG_MAIL = 2,
    LOG_DAEMON = 3,
    LOG_AUTH = 4,
    LOG_SYSLOG = 5,
    LOG_LPR = 6,
    LOG_NEWS = 7,
    LOG_UUCP = 8,
    LOG_CRON = 9,
    LOG_AUTHPRIV = 10,
    LOG_FTP = 11,
    LOG_LOCAL0 = 16,
    LOG_LOCAL1 = 17,
    LOG_LOCAL2 = 18,
    LOG_LOCAL3 = 19,
    LOG_LOCAL4 = 20,
    LOG_LOCAL5 = 21,
    LOG_LOCAL6 = 22,
    LOG_LOCAL7 = 23,
};

/// Base class for rotating handlers
pub const BaseRotatingHandler = struct {
    const Self = @This();

    handler: logging.Handler,
    filename: []const u8,
    mode: []const u8,
    encoding: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, filename: []const u8) Self {
        return .{
            .handler = logging.Handler.init(allocator),
            .filename = filename,
            .mode = "a",
            .encoding = null,
        };
    }

    /// Determine if rollover should occur
    pub fn shouldRollover(self: *Self, record: *logging.LogRecord) bool {
        _ = self;
        _ = record;
        return false;
    }

    /// Perform rollover
    pub fn doRollover(self: *Self) !void {
        _ = self;
    }
};

/// Handler for logging to a file with size-based rotation
pub const RotatingFileHandler = struct {
    const Self = @This();

    base: BaseRotatingHandler,
    max_bytes: usize,
    backup_count: usize,

    pub fn init(allocator: std.mem.Allocator, filename: []const u8, max_bytes: usize, backup_count: usize) Self {
        return .{
            .base = BaseRotatingHandler.init(allocator, filename),
            .max_bytes = max_bytes,
            .backup_count = backup_count,
        };
    }

    pub fn shouldRollover(self: *Self, record: *logging.LogRecord) bool {
        if (self.max_bytes == 0) return false;

        // Check if adding this record would exceed max_bytes
        const msg_len = record.message.len;
        const file = std.fs.cwd().openFile(self.base.filename, .{}) catch return false;
        defer file.close();

        const stat = file.stat() catch return false;
        return stat.size + msg_len >= self.max_bytes;
    }

    pub fn doRollover(self: *Self) !void {
        const allocator = self.base.handler.allocator;

        // Rotate backup files
        if (self.backup_count > 0) {
            var i: usize = self.backup_count;
            while (i > 0) : (i -= 1) {
                const sfn = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ self.base.filename, i });
                defer allocator.free(sfn);
                const dfn = try std.fmt.allocPrint(allocator, "{s}.{d}", .{ self.base.filename, i + 1 });
                defer allocator.free(dfn);

                std.fs.cwd().rename(sfn, dfn) catch {};
            }

            const dfn = try std.fmt.allocPrint(allocator, "{s}.1", .{self.base.filename});
            defer allocator.free(dfn);
            std.fs.cwd().rename(self.base.filename, dfn) catch {};
        }
    }
};

/// Handler for logging to a file with time-based rotation
pub const TimedRotatingFileHandler = struct {
    const Self = @This();

    base: BaseRotatingHandler,
    when: []const u8, // 'S', 'M', 'H', 'D', 'W0'-'W6', 'midnight'
    interval: usize,
    backup_count: usize,
    utc: bool,
    at_time: ?i64,
    rollover_at: i64,

    pub fn init(
        allocator: std.mem.Allocator,
        filename: []const u8,
        when: []const u8,
        interval: usize,
        backup_count: usize,
    ) Self {
        return .{
            .base = BaseRotatingHandler.init(allocator, filename),
            .when = when,
            .interval = interval,
            .backup_count = backup_count,
            .utc = false,
            .at_time = null,
            .rollover_at = 0,
        };
    }

    /// Compute the next rollover time
    pub fn computeRollover(self: *Self, current_time: i64) i64 {
        const interval_seconds: i64 = switch (self.when[0]) {
            'S' => @intCast(self.interval),
            'M' => @intCast(self.interval * 60),
            'H' => @intCast(self.interval * 3600),
            'D' => @intCast(self.interval * 86400),
            else => @intCast(self.interval),
        };
        return current_time + interval_seconds;
    }

    pub fn shouldRollover(self: *Self, record: *logging.LogRecord) bool {
        _ = record;
        const now = std.time.timestamp();
        return now >= self.rollover_at;
    }

    pub fn doRollover(self: *Self) !void {
        const now = std.time.timestamp();
        self.rollover_at = self.computeRollover(now);
        // Implementation would rename current log with timestamp suffix
    }
};

/// Handler that watches a file and reopens if it changes
pub const WatchedFileHandler = struct {
    const Self = @This();

    handler: logging.FileHandler,
    dev: u64,
    ino: u64,

    pub fn init(allocator: std.mem.Allocator, filename: []const u8) !Self {
        var h = logging.FileHandler.init(allocator, filename);
        _ = try h.open();

        return .{
            .handler = h,
            .dev = 0,
            .ino = 0,
        };
    }

    /// Check if file has been moved/deleted and reopen if necessary
    pub fn reopenIfNeeded(self: *Self) !void {
        const stat = std.fs.cwd().statFile(self.handler.filename) catch {
            // File was deleted, reopen
            _ = try self.handler.open();
            return;
        };

        // Check if inode/device changed
        if (stat.inode != self.ino or stat.dev != self.dev) {
            _ = try self.handler.open();
            self.ino = stat.inode;
            self.dev = stat.dev;
        }
    }
};

/// Handler that sends records over TCP
pub const SocketHandler = struct {
    const Self = @This();

    handler: logging.Handler,
    host: []const u8,
    port: u16,
    sock: ?std.posix.socket_t,
    close_on_error: bool,
    retry_time: ?i64,
    retry_start: f64,
    retry_max: f64,
    retry_factor: f64,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) Self {
        return .{
            .handler = logging.Handler.init(allocator),
            .host = host,
            .port = port,
            .sock = null,
            .close_on_error = false,
            .retry_time = null,
            .retry_start = 1.0,
            .retry_max = 30.0,
            .retry_factor = 2.0,
        };
    }

    /// Create a socket connection
    pub fn makeSocket(self: *Self) !std.posix.socket_t {
        _ = self;
        const sock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0);
        return sock;
    }

    /// Send a pickled record
    pub fn send(self: *Self, data: []const u8) !void {
        if (self.sock) |sock| {
            _ = try std.posix.send(sock, data, 0);
        }
    }

    /// Close the socket
    pub fn close(self: *Self) void {
        if (self.sock) |sock| {
            std.posix.close(sock);
            self.sock = null;
        }
    }
};

/// Handler that sends records over UDP
pub const DatagramHandler = struct {
    const Self = @This();

    handler: logging.Handler,
    host: []const u8,
    port: u16,
    sock: ?std.posix.socket_t,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) Self {
        return .{
            .handler = logging.Handler.init(allocator),
            .host = host,
            .port = port,
            .sock = null,
        };
    }

    pub fn makeSocket(self: *Self) !std.posix.socket_t {
        _ = self;
        return try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, 0);
    }

    pub fn send(self: *Self, data: []const u8) !void {
        if (self.sock) |sock| {
            _ = try std.posix.send(sock, data, 0);
        }
    }
};

/// Handler that sends to Unix syslog
pub const SysLogHandler = struct {
    const Self = @This();

    handler: logging.Handler,
    address: []const u8,
    facility: SysLogFacility,
    sock: ?std.posix.socket_t,
    socktype: std.posix.SOCK,

    /// Priority encoding map (level -> syslog priority)
    pub const priority_map = [_]u8{
        7, // DEBUG -> LOG_DEBUG
        6, // INFO -> LOG_INFO
        4, // WARNING -> LOG_WARNING
        3, // ERROR -> LOG_ERR
        2, // CRITICAL -> LOG_CRIT
    };

    pub fn init(allocator: std.mem.Allocator, address: []const u8, facility: SysLogFacility) Self {
        return .{
            .handler = logging.Handler.init(allocator),
            .address = address,
            .facility = facility,
            .sock = null,
            .socktype = .DGRAM,
        };
    }

    /// Encode the facility and priority into a syslog-style number
    pub fn encodePriority(self: *Self, level: i32) u8 {
        const priority: u8 = if (level >= logging.CRITICAL)
            2
        else if (level >= logging.ERROR)
            3
        else if (level >= logging.WARNING)
            4
        else if (level >= logging.INFO)
            6
        else
            7;

        return (@as(u8, @intFromEnum(self.facility)) << 3) | priority;
    }
};

/// Handler that buffers records in memory
pub const MemoryHandler = struct {
    const Self = @This();

    handler: logging.Handler,
    capacity: usize,
    buffer: std.ArrayList(*logging.LogRecord),
    flush_level: i32,
    target: ?*logging.Handler,
    flush_on_close: bool,

    pub fn init(allocator: std.mem.Allocator, capacity: usize, flush_level: i32) Self {
        return .{
            .handler = logging.Handler.init(allocator),
            .capacity = capacity,
            .buffer = std.ArrayList(*logging.LogRecord).init(allocator),
            .flush_level = flush_level,
            .target = null,
            .flush_on_close = true,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    /// Check if buffer should be flushed
    pub fn shouldFlush(self: *Self, record: *logging.LogRecord) bool {
        return record.level >= self.flush_level;
    }

    /// Set the target handler
    pub fn setTarget(self: *Self, target: *logging.Handler) void {
        self.target = target;
    }

    /// Flush buffer to target
    pub fn flush(self: *Self) void {
        if (self.target) |target| {
            for (self.buffer.items) |record| {
                target.emit(record) catch {};
            }
        }
        self.buffer.clearRetainingCapacity();
    }
};

/// Handler that sends records to an HTTP server
pub const HTTPHandler = struct {
    const Self = @This();

    handler: logging.Handler,
    host: []const u8,
    port: u16,
    url: []const u8,
    method: []const u8,
    secure: bool,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, url: []const u8, method: []const u8) Self {
        return .{
            .handler = logging.Handler.init(allocator),
            .host = host,
            .port = 80,
            .url = url,
            .method = method,
            .secure = false,
        };
    }

    /// Map a LogRecord to a dict for sending
    pub fn mapLogRecord(self: *Self, record: *logging.LogRecord) ![]const u8 {
        _ = self;
        return record.message;
    }
};

/// Handler that puts records on a queue
pub const QueueHandler = struct {
    const Self = @This();

    handler: logging.Handler,
    queue: std.ArrayList(*logging.LogRecord),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .handler = logging.Handler.init(allocator),
            .queue = std.ArrayList(*logging.LogRecord).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.queue.deinit();
    }

    /// Enqueue a record
    pub fn enqueue(self: *Self, record: *logging.LogRecord) !void {
        try self.queue.append(record);
    }
};

/// Listener that monitors a queue for log records
pub const QueueListener = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    queue: *std.ArrayList(*logging.LogRecord),
    handlers: std.ArrayList(*logging.Handler),
    respect_handler_level: bool,
    running: bool,

    pub fn init(allocator: std.mem.Allocator, queue: *std.ArrayList(*logging.LogRecord)) Self {
        return .{
            .allocator = allocator,
            .queue = queue,
            .handlers = std.ArrayList(*logging.Handler).init(allocator),
            .respect_handler_level = false,
            .running = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.handlers.deinit();
    }

    /// Add a handler
    pub fn addHandler(self: *Self, handler: *logging.Handler) !void {
        try self.handlers.append(handler);
    }

    /// Start monitoring the queue
    pub fn start(self: *Self) void {
        self.running = true;
        // In full implementation, would spawn a thread to monitor queue
    }

    /// Stop monitoring the queue
    pub fn stop(self: *Self) void {
        self.running = false;
    }

    /// Handle a record
    pub fn handle(self: *Self, record: *logging.LogRecord) void {
        for (self.handlers.items) |handler| {
            if (!self.respect_handler_level or record.level >= handler.level) {
                handler.emit(record) catch {};
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "RotatingFileHandler" {
    const allocator = std.testing.allocator;
    var handler = RotatingFileHandler.init(allocator, "/tmp/test.log", 1024 * 1024, 5);
    try std.testing.expectEqual(@as(usize, 1024 * 1024), handler.max_bytes);
    try std.testing.expectEqual(@as(usize, 5), handler.backup_count);
}

test "TimedRotatingFileHandler computeRollover" {
    const allocator = std.testing.allocator;
    var handler = TimedRotatingFileHandler.init(allocator, "/tmp/test.log", "H", 1, 5);
    const now: i64 = 1000;
    const next = handler.computeRollover(now);
    try std.testing.expectEqual(@as(i64, 4600), next); // 1000 + 3600
}

test "SysLogHandler encodePriority" {
    const allocator = std.testing.allocator;
    var handler = SysLogHandler.init(allocator, "/dev/log", .LOG_USER);
    // LOG_USER (1) << 3 | priority
    try std.testing.expectEqual(@as(u8, (1 << 3) | 3), handler.encodePriority(logging.ERROR));
}

test "MemoryHandler" {
    const allocator = std.testing.allocator;
    var handler = MemoryHandler.init(allocator, 100, logging.ERROR);
    defer handler.deinit();
    try std.testing.expectEqual(@as(usize, 100), handler.capacity);
}
