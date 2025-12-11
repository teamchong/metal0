//! FTP types, constants, and error definitions
//!
//! Contains core type definitions for FTP client:
//! - Constants (ports, timeouts, buffer sizes)
//! - Error types
//! - FtpResponse structure

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Default FTP port
pub const FTP_PORT = 21;

/// Default buffer size
pub const MAXLINE = 8192;

/// Timeout for blocking operations
pub const DEFAULT_TIMEOUT: f64 = 30.0;

// ============================================================================
// Error Types
// ============================================================================

pub const FtpError = error{
    /// Base FTP error
    Error,
    /// Reply error (4xx or 5xx)
    ReplyError,
    /// Temporary error (4xx)
    TempError,
    /// Permanent error (5xx)
    PermError,
    /// Protocol error (unexpected reply)
    ProtoError,
    /// Connection refused
    ConnectionRefused,
    /// Socket timeout
    Timeout,
    /// Not logged in
    NotLoggedIn,
};

// ============================================================================
// FTP Response
// ============================================================================

/// FTP response structure
pub const FtpResponse = struct {
    code: u16,
    message: []const u8,

    pub fn isPositive(self: *const FtpResponse) bool {
        return self.code >= 100 and self.code < 400;
    }

    pub fn isComplete(self: *const FtpResponse) bool {
        return self.code >= 200 and self.code < 300;
    }

    pub fn isIntermediate(self: *const FtpResponse) bool {
        return self.code >= 300 and self.code < 400;
    }

    pub fn isNegativeTransient(self: *const FtpResponse) bool {
        return self.code >= 400 and self.code < 500;
    }

    pub fn isNegativePermanent(self: *const FtpResponse) bool {
        return self.code >= 500 and self.code < 600;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "FtpResponse isPositive" {
    const resp = FtpResponse{ .code = 220, .message = "Service ready" };
    try std.testing.expect(resp.isPositive());
    try std.testing.expect(resp.isComplete());
    try std.testing.expect(!resp.isNegativeTransient());
    try std.testing.expect(!resp.isNegativePermanent());
}

test "FtpResponse isNegative" {
    const resp = FtpResponse{ .code = 550, .message = "File not found" };
    try std.testing.expect(!resp.isPositive());
    try std.testing.expect(resp.isNegativePermanent());
}

test "FTP_PORT constant" {
    try std.testing.expectEqual(@as(u16, 21), FTP_PORT);
}
