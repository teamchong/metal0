//! email.mime.application - MIME application message class
//! Reference: cpython/Lib/email/mime/application.py
//!
//! CPython __all__: MIMEApplication
//!
//! Class for generating application/* MIME documents.

const std = @import("std");
const mime = @import("../mime.zig");

// Re-export from parent (DRY)
pub const MIMEApplication = mime.MIMEApplication;

// ============================================================================
// Tests
// ============================================================================

test "MIMEApplication re-export" {
    _ = MIMEApplication;
}
