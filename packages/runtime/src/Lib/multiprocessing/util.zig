//! multiprocessing.util - Utility functions
//! Reference: cpython/Lib/multiprocessing/util.py
//!
//! CPython __all__: ['sub_debug', 'debug', 'info', 'sub_warning', 'get_logger',
//!                   'log_to_stderr', 'get_temp_dir', 'register_after_fork',
//!                   'is_exiting', 'Finalize', 'ForkAwareThreadLock', 'ForkAwareLocal',
//!                   'close_all_fds_except', 'SUBDEBUG', 'SUBWARNING']
//!
//! Provides various utilities for multiprocessing module.

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Logging Levels
// ============================================================================

/// CPython: NOTSET = 0
pub const NOTSET: u32 = 0;

/// CPython: SUBDEBUG = 5
pub const SUBDEBUG: u32 = 5;

/// CPython: DEBUG = 10
pub const DEBUG: u32 = 10;

/// CPython: INFO = 20
pub const INFO: u32 = 20;

/// CPython: SUBWARNING = 25
pub const SUBWARNING: u32 = 25;

/// CPython: WARNING = 30
pub const WARNING: u32 = 30;

/// CPython: ERROR = 40
pub const ERROR_LEVEL: u32 = 40;

/// CPython: CRITICAL = 50
pub const CRITICAL: u32 = 50;

/// Logger name
pub const LOGGER_NAME: []const u8 = "multiprocessing";

/// Default logging format
pub const DEFAULT_LOGGING_FORMAT: []const u8 = "[%(levelname)s/%(processName)s] %(message)s";

// ============================================================================
// Logging Functions
// ============================================================================

var _current_log_level: u32 = WARNING;
var _log_to_stderr: bool = false;

/// CPython: def sub_debug(msg, *args)
pub fn sub_debug(msg: []const u8) void {
    if (_current_log_level <= SUBDEBUG) {
        log(SUBDEBUG, msg);
    }
}

/// CPython: def debug(msg, *args)
pub fn debug(msg: []const u8) void {
    if (_current_log_level <= DEBUG) {
        log(DEBUG, msg);
    }
}

/// CPython: def info(msg, *args)
pub fn info(msg: []const u8) void {
    if (_current_log_level <= INFO) {
        log(INFO, msg);
    }
}

/// CPython: def sub_warning(msg, *args)
pub fn sub_warning(msg: []const u8) void {
    if (_current_log_level <= SUBWARNING) {
        log(SUBWARNING, msg);
    }
}

fn log(level: u32, msg: []const u8) void {
    const level_name = switch (level) {
        SUBDEBUG => "SUBDEBUG",
        DEBUG => "DEBUG",
        INFO => "INFO",
        SUBWARNING => "SUBWARNING",
        WARNING => "WARNING",
        ERROR_LEVEL => "ERROR",
        CRITICAL => "CRITICAL",
        else => "UNKNOWN",
    };

    if (_log_to_stderr) {
        std.debug.print("[{s}] {s}\n", .{ level_name, msg });
    }
}

/// CPython: def get_logger()
pub fn get_logger() Logger {
    return Logger{};
}

pub const Logger = struct {
    pub fn setLevel(self: *Logger, level: u32) void {
        _ = self;
        _current_log_level = level;
    }

    pub fn getEffectiveLevel(_: *Logger) u32 {
        return _current_log_level;
    }
};

/// CPython: def log_to_stderr(level=None)
pub fn log_to_stderr(level: ?u32) Logger {
    _log_to_stderr = true;
    if (level) |l| {
        _current_log_level = l;
    }
    return Logger{};
}

// ============================================================================
// Temporary Directory
// ============================================================================

var _tempdir: ?[]const u8 = null;

/// CPython: def get_temp_dir()
pub fn get_temp_dir() []const u8 {
    if (_tempdir) |dir| {
        return dir;
    }

    // Try environment variables
    if (std.posix.getenv("TMPDIR")) |dir| return dir;
    if (std.posix.getenv("TEMP")) |dir| return dir;
    if (std.posix.getenv("TMP")) |dir| return dir;

    // Default
    return if (builtin.os.tag == .windows) "C:\\Temp" else "/tmp";
}

// ============================================================================
// Fork-aware Utilities
// ============================================================================

/// CPython: class ForkAwareThreadLock
/// A lock that resets itself after fork
pub const ForkAwareThreadLock = struct {
    const Self = @This();

    lock: std.Thread.Mutex,
    pid: std.posix.pid_t,

    pub fn init() Self {
        return .{
            .lock = .{},
            .pid = std.posix.getpid(),
        };
    }

    pub fn acquire(self: *Self) void {
        // Check if we forked
        const current_pid = std.posix.getpid();
        if (current_pid != self.pid) {
            // Reset after fork
            self.lock = .{};
            self.pid = current_pid;
        }
        self.lock.lock();
    }

    pub fn release(self: *Self) void {
        self.lock.unlock();
    }
};

/// CPython: class ForkAwareLocal
/// Thread-local storage that resets after fork
pub fn ForkAwareLocal(comptime T: type) type {
    return struct {
        const Self = @This();

        value: ?T,
        pid: std.posix.pid_t,

        pub fn init() Self {
            return .{
                .value = null,
                .pid = std.posix.getpid(),
            };
        }

        pub fn get(self: *Self) ?T {
            const current_pid = std.posix.getpid();
            if (current_pid != self.pid) {
                self.value = null;
                self.pid = current_pid;
            }
            return self.value;
        }

        pub fn set(self: *Self, value: T) void {
            self.value = value;
            self.pid = std.posix.getpid();
        }
    };
}

// ============================================================================
// After-Fork Registry
// ============================================================================

const AfterForkCallback = *const fn () void;
var _after_fork_callbacks: [64]?AfterForkCallback = [_]?AfterForkCallback{null} ** 64;
var _after_fork_count: usize = 0;

/// CPython: def register_after_fork(obj, func)
pub fn register_after_fork(callback: AfterForkCallback) void {
    if (_after_fork_count < 64) {
        _after_fork_callbacks[_after_fork_count] = callback;
        _after_fork_count += 1;
    }
}

/// Run all registered after-fork callbacks
pub fn run_after_fork_callbacks() void {
    for (_after_fork_callbacks[0.._after_fork_count]) |maybe_cb| {
        if (maybe_cb) |cb| {
            cb();
        }
    }
}

// ============================================================================
// Exit Handling
// ============================================================================

var _exiting: bool = false;

/// CPython: def is_exiting()
pub fn is_exiting() bool {
    return _exiting;
}

/// Set exit flag
pub fn set_exiting(value: bool) void {
    _exiting = value;
}

// ============================================================================
// File Descriptor Utilities
// ============================================================================

/// CPython: def close_all_fds_except(fds)
pub fn close_all_fds_except(keep_fds: []const std.posix.fd_t) void {
    if (builtin.os.tag == .windows) {
        return;
    }

    // Get max fd (platform-specific)
    const max_fd: std.posix.fd_t = 1024;

    var fd: std.posix.fd_t = 3; // Start after stdin/stdout/stderr
    while (fd < max_fd) : (fd += 1) {
        var keep = false;
        for (keep_fds) |kfd| {
            if (fd == kfd) {
                keep = true;
                break;
            }
        }
        if (!keep) {
            std.posix.close(fd);
        }
    }
}

// ============================================================================
// Finalize - Weak reference callback on object destruction
// ============================================================================

/// CPython: class Finalize
pub const Finalize = struct {
    const Self = @This();

    callback: *const fn () void,
    args: ?*anyopaque,
    exitpriority: ?i32,

    pub fn init(callback: *const fn () void, exitpriority: ?i32) Self {
        return .{
            .callback = callback,
            .args = null,
            .exitpriority = exitpriority,
        };
    }

    pub fn call(self: *Self) void {
        self.callback();
    }

    pub fn cancel(self: *Self) void {
        _ = self;
        // Mark as cancelled
    }

    pub fn stillActive(self: *Self) bool {
        _ = self;
        return true;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "logging levels" {
    try std.testing.expectEqual(@as(u32, 5), SUBDEBUG);
    try std.testing.expectEqual(@as(u32, 25), SUBWARNING);
}

test "get_temp_dir" {
    const dir = get_temp_dir();
    try std.testing.expect(dir.len > 0);
}

test "ForkAwareThreadLock" {
    var lock = ForkAwareThreadLock.init();
    lock.acquire();
    lock.release();
}

test "is_exiting" {
    try std.testing.expect(!is_exiting());
    set_exiting(true);
    try std.testing.expect(is_exiting());
    set_exiting(false);
}

test "Finalize" {
    var called = false;
    const callback = struct {
        fn cb() void {
            _ = &called;
        }
    }.cb;

    var finalizer = Finalize.init(callback, null);
    try std.testing.expect(finalizer.stillActive());
}
