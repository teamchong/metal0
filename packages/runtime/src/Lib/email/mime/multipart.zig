//! email.mime.multipart - MIME multipart message class
//! Reference: cpython/Lib/email/mime/multipart.py
//!
//! CPython __all__: MIMEMultipart
//!
//! Class for generating multipart/* MIME documents.

const std = @import("std");
const mime = @import("../mime.zig");

// Re-export from parent (DRY)
pub const MIMEMultipart = mime.MIMEMultipart;

// ============================================================================
// Tests
// ============================================================================

test "MIMEMultipart re-export" {
    _ = MIMEMultipart;
}
