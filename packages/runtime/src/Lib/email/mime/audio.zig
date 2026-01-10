//! email.mime.audio - MIME audio message class
//! Reference: cpython/Lib/email/mime/audio.py
//!
//! CPython __all__: MIMEAudio
//!
//! Class for generating audio/* MIME documents.

const std = @import("std");
const mime = @import("../mime.zig");

// Re-export from parent (DRY)
pub const MIMEAudio = mime.MIMEAudio;

// ============================================================================
// Tests
// ============================================================================

test "MIMEAudio re-export" {
    _ = MIMEAudio;
}
