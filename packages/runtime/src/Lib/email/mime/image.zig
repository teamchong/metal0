//! email.mime.image - MIME image message class
//! Reference: cpython/Lib/email/mime/image.py
//!
//! CPython __all__: MIMEImage
//!
//! Class for generating image/* MIME documents.

const std = @import("std");
const mime = @import("../mime.zig");

// Re-export from parent (DRY)
pub const MIMEImage = mime.MIMEImage;

// ============================================================================
// Tests
// ============================================================================

test "MIMEImage re-export" {
    _ = MIMEImage;
}
