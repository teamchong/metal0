//! asyncio constants - CPython compatible
//! Reference: cpython/Lib/asyncio/constants.py
const std = @import("std");

// After the connection is lost, log warnings after this many write()s.
pub const LOG_THRESHOLD_FOR_CONNLOST_WRITES: i32 = 5;

// Seconds to wait before retrying accept().
pub const ACCEPT_RETRY_DELAY: f64 = 1.0;

// Number of stack entries to capture in debug mode.
// The larger the number, the slower the operation in debug mode.
pub const DEBUG_STACK_DEPTH: i32 = 10;

// Number of seconds to wait for SSL handshake to complete.
// The default timeout matches that of Nginx.
pub const SSL_HANDSHAKE_TIMEOUT: f64 = 60.0;

// Number of seconds to wait for SSL shutdown to complete.
// The default timeout mimics lingering_time.
pub const SSL_SHUTDOWN_TIMEOUT: f64 = 30.0;

// Used in sendfile fallback code. We use fallback for platforms
// that don't support sendfile, or for TLS connections.
pub const SENDFILE_FALLBACK_READBUFFER_SIZE: usize = 1024 * 256;

// Flow control constants (in KiB in CPython, we use bytes)
pub const FLOW_CONTROL_HIGH_WATER_SSL_READ: usize = 256 * 1024; // 256 KiB
pub const FLOW_CONTROL_HIGH_WATER_SSL_WRITE: usize = 512 * 1024; // 512 KiB

// Default timeout for joining the threads in the threadpool
pub const THREAD_JOIN_TIMEOUT: f64 = 300.0;

// The enum breaks circular dependencies between base_events and sslproto
pub const SendfileMode = enum {
    UNSUPPORTED,
    TRY_NATIVE,
    FALLBACK,
};

// Tests
test "constants values" {
    try std.testing.expectEqual(@as(i32, 5), LOG_THRESHOLD_FOR_CONNLOST_WRITES);
    try std.testing.expectEqual(@as(f64, 1.0), ACCEPT_RETRY_DELAY);
    try std.testing.expectEqual(@as(i32, 10), DEBUG_STACK_DEPTH);
    try std.testing.expectEqual(@as(f64, 60.0), SSL_HANDSHAKE_TIMEOUT);
    try std.testing.expectEqual(@as(f64, 30.0), SSL_SHUTDOWN_TIMEOUT);
    try std.testing.expectEqual(@as(usize, 256 * 1024), SENDFILE_FALLBACK_READBUFFER_SIZE);
}

test "SendfileMode enum" {
    const mode1: SendfileMode = .UNSUPPORTED;
    const mode2: SendfileMode = .TRY_NATIVE;
    const mode3: SendfileMode = .FALLBACK;

    try std.testing.expect(mode1 != mode2);
    try std.testing.expect(mode2 != mode3);
}
