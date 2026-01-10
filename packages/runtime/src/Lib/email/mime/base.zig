//! email.mime.base - MIME base class
//! Reference: cpython/Lib/email/mime/base.py
//!
//! CPython __all__: MIMEBase
//!
//! Base class for all MIME-specific subclasses.

const std = @import("std");
const mime = @import("../mime.zig");

// Re-export from parent (DRY)
pub const MIMEBase = mime.MIMEBase;

// ============================================================================
// Tests
// ============================================================================

test "MIMEBase re-export" {
    _ = MIMEBase;
}
