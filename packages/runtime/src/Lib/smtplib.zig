//! CPython source: Lib/smtplib.py
//!
//! Provides SMTP client functionality for sending email.
//!
//! Mirrors: CPython Lib/smtplib.py
//!
//! This is the main entry point for the smtplib module. It re-exports all
//! public APIs from the modular submodules:
//! - types.zig: Constants, error types, response structures
//! - smtp.zig: Main SMTP client
//! - smtp_ssl.zig: SMTP_SSL client for secure connections
//! - lmtp.zig: LMTP client for local mail delivery

// Re-export types and constants
pub const types = @import("smtplib/types.zig");
pub const SMTP_PORT = types.SMTP_PORT;
pub const SMTP_SSL_PORT = types.SMTP_SSL_PORT;
pub const SMTP_SUBMISSION_PORT = types.SMTP_SUBMISSION_PORT;
pub const CRLF = types.CRLF;
pub const MAXLINE = types.MAXLINE;
pub const ReplyCode = types.ReplyCode;
pub const SmtpError = types.SmtpError;
pub const SmtpResponse = types.SmtpResponse;

// Re-export SMTP client
pub const smtp = @import("smtplib/smtp.zig");
pub const SMTP = smtp.SMTP;

// Re-export SMTP_SSL client
pub const smtp_ssl = @import("smtplib/smtp_ssl.zig");
pub const SMTP_SSL = smtp_ssl.SMTP_SSL;

// Re-export LMTP client
pub const lmtp = @import("smtplib/lmtp.zig");
pub const LMTP = lmtp.LMTP;

// Re-export tests
test {
    @import("std").testing.refAllDecls(@This());
    @import("std").testing.refAllDecls(types);
}
