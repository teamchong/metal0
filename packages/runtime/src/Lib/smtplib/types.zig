//! CPython source: Lib/smtplib.py
//!
//! SMTP types, constants, error codes, and response structures.
//!
//! This module provides the core types and constants used throughout the SMTP implementation:
//! - Port constants (SMTP_PORT, SMTP_SSL_PORT, SMTP_SUBMISSION_PORT)
//! - Protocol constants (CRLF, MAXLINE)
//! - Reply codes (ReplyCode.OK, ReplyCode.SERVICE_READY, etc.)
//! - Error types (SmtpError)
//! - Response structure (SmtpResponse)

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Default SMTP port
pub const SMTP_PORT = 25;

/// Default SMTP SSL port
pub const SMTP_SSL_PORT = 465;

/// Default SMTP submission port
pub const SMTP_SUBMISSION_PORT = 587;

/// Line terminator
pub const CRLF = "\r\n";

/// Maximum line length (per RFC 5321)
pub const MAXLINE = 8192;

/// Response codes
pub const ReplyCode = struct {
    pub const SYSTEM_STATUS = 211;
    pub const HELP_MESSAGE = 214;
    pub const SERVICE_READY = 220;
    pub const SERVICE_CLOSING = 221;
    pub const AUTH_SUCCESSFUL = 235;
    pub const OK = 250;
    pub const USER_NOT_LOCAL = 251;
    pub const CANNOT_VRFY = 252;
    pub const AUTH_CONTINUE = 334;
    pub const START_MAIL_INPUT = 354;
    pub const SERVICE_NOT_AVAILABLE = 421;
    pub const MAILBOX_BUSY = 450;
    pub const LOCAL_ERROR = 451;
    pub const INSUFFICIENT_STORAGE = 452;
    pub const COMMAND_UNRECOGNIZED = 500;
    pub const SYNTAX_ERROR = 501;
    pub const COMMAND_NOT_IMPLEMENTED = 502;
    pub const BAD_SEQUENCE = 503;
    pub const PARAMETER_NOT_IMPLEMENTED = 504;
    pub const AUTH_REQUIRED = 530;
    pub const AUTH_FAILED = 535;
    pub const MAILBOX_NOT_FOUND = 550;
    pub const USER_NOT_LOCAL_FORWARD = 551;
    pub const EXCEEDED_STORAGE = 552;
    pub const MAILBOX_NAME_INVALID = 553;
    pub const TRANSACTION_FAILED = 554;
};

// ============================================================================
// Error Types
// ============================================================================

pub const SmtpError = error{
    /// Base SMTP error
    Error,
    /// Not connected
    NotConnected,
    /// Server disconnected
    ServerDisconnected,
    /// Unexpected response
    ResponseError,
    /// Sender refused
    SenderRefused,
    /// Recipients refused
    RecipientsRefused,
    /// Data refused
    DataError,
    /// Authentication error
    AuthError,
    /// HELO required
    HeloError,
    /// Protocol error
    ProtoError,
    /// Connection error
    ConnectionError,
    /// Connection refused
    ConnectionRefused,
    /// Timeout
    Timeout,
};

// ============================================================================
// SMTP Response
// ============================================================================

/// SMTP response structure
pub const SmtpResponse = struct {
    code: u16,
    message: []const u8,

    pub fn isSuccess(self: *const SmtpResponse) bool {
        return self.code >= 200 and self.code < 300;
    }

    pub fn isIntermediate(self: *const SmtpResponse) bool {
        return self.code >= 300 and self.code < 400;
    }

    pub fn isError(self: *const SmtpResponse) bool {
        return self.code >= 400;
    }

    pub fn isTransientError(self: *const SmtpResponse) bool {
        return self.code >= 400 and self.code < 500;
    }

    pub fn isPermanentError(self: *const SmtpResponse) bool {
        return self.code >= 500;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "SMTP_PORT constants" {
    try std.testing.expectEqual(@as(u16, 25), SMTP_PORT);
    try std.testing.expectEqual(@as(u16, 465), SMTP_SSL_PORT);
    try std.testing.expectEqual(@as(u16, 587), SMTP_SUBMISSION_PORT);
}

test "SmtpResponse isSuccess" {
    const resp = SmtpResponse{ .code = 250, .message = "OK" };
    try std.testing.expect(resp.isSuccess());
    try std.testing.expect(!resp.isError());
    try std.testing.expect(!resp.isPermanentError());
}

test "SmtpResponse isError" {
    const resp = SmtpResponse{ .code = 550, .message = "Mailbox not found" };
    try std.testing.expect(!resp.isSuccess());
    try std.testing.expect(resp.isError());
    try std.testing.expect(resp.isPermanentError());
}

test "SmtpResponse isTransientError" {
    const resp = SmtpResponse{ .code = 450, .message = "Mailbox busy" };
    try std.testing.expect(resp.isError());
    try std.testing.expect(resp.isTransientError());
    try std.testing.expect(!resp.isPermanentError());
}

test "ReplyCode constants" {
    try std.testing.expectEqual(@as(u16, 220), ReplyCode.SERVICE_READY);
    try std.testing.expectEqual(@as(u16, 250), ReplyCode.OK);
    try std.testing.expectEqual(@as(u16, 550), ReplyCode.MAILBOX_NOT_FOUND);
}
