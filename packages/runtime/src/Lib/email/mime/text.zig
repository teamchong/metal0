//! email.mime.text - MIME text message class
//! Reference: cpython/Lib/email/mime/text.py
//!
//! CPython __all__: MIMEText
//!
//! Class for generating text/* MIME documents.

const std = @import("std");
const mime = @import("../mime.zig");

// Re-export from parent (DRY)
pub const MIMEText = mime.MIMEText;

// ============================================================================
// Tests
// ============================================================================

test "MIMEText re-export" {
    _ = MIMEText;
}
