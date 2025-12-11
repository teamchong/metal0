//! CPython source: Lib/imaplib.py
//!
//! Provides IMAP4 client functionality.
//!
//! Mirrors: CPython Lib/imaplib.py

const std = @import("std");

// Re-export submodules
pub const types = @import("imaplib/types.zig");
pub const commands = @import("imaplib/commands.zig");
pub const imap4 = @import("imaplib/imap4.zig");
pub const ssl = @import("imaplib/ssl.zig");
pub const utils = @import("imaplib/utils.zig");

// Re-export common types and constants
pub const IMAP4_PORT = types.IMAP4_PORT;
pub const IMAP4_SSL_PORT = types.IMAP4_SSL_PORT;
pub const CRLF = types.CRLF;
pub const ImapError = types.ImapError;
pub const ResponseType = types.ResponseType;
pub const ImapResponse = types.ImapResponse;
pub const State = types.State;
pub const StandardFlags = types.StandardFlags;

// Re-export commands
pub const Commands = commands.Commands;

// Re-export main classes
pub const IMAP4 = imap4.IMAP4;
pub const IMAP4_SSL = ssl.IMAP4_SSL;
pub const IMAP4_stream = ssl.IMAP4_stream;

// Re-export utility functions
pub const parseFlags = utils.parseFlags;
pub const parseFetchFlags = utils.parseFetchFlags;
pub const hasFlag = utils.hasFlag;
pub const encodeModifiedUtf7 = utils.encodeModifiedUtf7;
pub const decodeModifiedUtf7 = utils.decodeModifiedUtf7;

// ============================================================================
// Tests
// ============================================================================

test "IMAP4_PORT constant" {
    try std.testing.expectEqual(@as(u16, 143), IMAP4_PORT);
    try std.testing.expectEqual(@as(u16, 993), IMAP4_SSL_PORT);
}

test "ImapResponse isOk" {
    const resp = ImapResponse{ .typ = .OK, .data = &[_][]const u8{} };
    try std.testing.expect(resp.isOk());
    try std.testing.expect(!resp.isNo());
    try std.testing.expect(!resp.isBad());
}

test "ImapResponse isNo" {
    const resp = ImapResponse{ .typ = .NO, .data = &[_][]const u8{} };
    try std.testing.expect(!resp.isOk());
    try std.testing.expect(resp.isNo());
}

test "ImapResponse isBad" {
    const resp = ImapResponse{ .typ = .BAD, .data = &[_][]const u8{} };
    try std.testing.expect(resp.isBad());
}

test "Commands" {
    try std.testing.expectEqualStrings("LOGIN", Commands.LOGIN);
    try std.testing.expectEqualStrings("LOGOUT", Commands.LOGOUT);
    try std.testing.expectEqualStrings("SELECT", Commands.SELECT);
}
