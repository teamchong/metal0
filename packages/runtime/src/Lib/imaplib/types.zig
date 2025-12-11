//! IMAP4 core types and constants
//!
//! Mirrors: CPython Lib/imaplib.py (types section)

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Constants
// ============================================================================

/// Default IMAP4 port
pub const IMAP4_PORT = 143;

/// Default IMAP4 SSL port
pub const IMAP4_SSL_PORT = 993;

/// Line terminator
pub const CRLF = "\r\n";

// ============================================================================
// Error Types
// ============================================================================

pub const ImapError = error{
    /// Base IMAP error
    Error,
    /// Abort (connection lost)
    Abort,
    /// Read-only mailbox
    ReadOnly,
    /// Authentication failed
    AuthError,
    /// Protocol error
    ProtoError,
    /// Connection refused
    ConnectionRefused,
};

// ============================================================================
// IMAP Response
// ============================================================================

/// IMAP4 response type
pub const ResponseType = enum {
    OK,
    NO,
    BAD,
    PREAUTH,
    BYE,
};

/// IMAP4 response structure
pub const ImapResponse = struct {
    typ: ResponseType,
    data: [][]const u8,

    pub fn isOk(self: *const ImapResponse) bool {
        return self.typ == .OK;
    }

    pub fn isNo(self: *const ImapResponse) bool {
        return self.typ == .NO;
    }

    pub fn isBad(self: *const ImapResponse) bool {
        return self.typ == .BAD;
    }
};

// ============================================================================
// IMAP4 State
// ============================================================================

/// IMAP4 connection state
pub const State = enum {
    LOGOUT,
    NONAUTH,
    AUTH,
    SELECTED,
};

// ============================================================================
// Standard Flags
// ============================================================================

/// Standard IMAP flags
pub const StandardFlags = struct {
    pub const SEEN = "\\Seen";
    pub const ANSWERED = "\\Answered";
    pub const FLAGGED = "\\Flagged";
    pub const DELETED = "\\Deleted";
    pub const DRAFT = "\\Draft";
    pub const RECENT = "\\Recent";
};
