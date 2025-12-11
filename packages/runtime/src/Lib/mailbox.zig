//! CPython source: Lib/mailbox.py
//!
//! Provides uniform access to mailboxes in different formats.
//!
//! Mirrors: CPython Lib/mailbox.py

// Re-export all public symbols from submodules
pub const errors = @import("mailbox/errors.zig");
pub const message = @import("mailbox/message.zig");
pub const mailbox_base = @import("mailbox/mailbox_base.zig");
pub const mbox = @import("mailbox/mbox.zig");
pub const maildir = @import("mailbox/maildir.zig");
pub const mh = @import("mailbox/mh.zig");
pub const mmdf = @import("mailbox/mmdf.zig");
pub const babyl = @import("mailbox/babyl.zig");

// Re-export commonly used types at top level for convenience
pub const MailboxError = errors.MailboxError;
pub const Message = message.Message;
pub const Mailbox = mailbox_base.Mailbox;
pub const Mbox = mbox.Mbox;
pub const Maildir = maildir.Maildir;
pub const MaildirMessage = maildir.Maildir.MaildirMessage;
pub const MH = mh.MH;
pub const MHMessage = mh.MH.MHMessage;
pub const MMDF = mmdf.MMDF;
pub const MMDFMessage = mmdf.MMDF.MMDFMessage;
pub const Babyl = babyl.Babyl;
pub const BabylMessage = babyl.Babyl.BabylMessage;
