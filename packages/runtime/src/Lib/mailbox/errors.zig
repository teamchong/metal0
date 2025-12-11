//! CPython source: Lib/mailbox.py
//!
//! Error types for mailbox operations.
//!
//! Mirrors: CPython Lib/mailbox.py

pub const MailboxError = error{
    /// Base mailbox error
    Error,
    /// Mailbox not found
    NoSuchMailboxError,
    /// Mailbox already exists
    ExternalClashError,
    /// Format error
    FormatError,
    /// Message not found
    NotEmptyError,
};
