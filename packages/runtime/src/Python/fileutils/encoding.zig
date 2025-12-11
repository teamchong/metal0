/// encoding - Encoding Detection
/// Mirrors cpython/Python/fileutils.c encoding detection
///
/// This module provides encoding detection for file operations.

const std = @import("std");
const builtin = @import("builtin");
const fd_ops = @import("fd_ops.zig");

// ============================================================================
// Encoding Detection
// ============================================================================

/// Get the device encoding for a file descriptor
pub fn deviceEncoding(file: std.fs.File) []const u8 {
    if (!fd_ops.isatty(file)) {
        return "utf-8"; // Default for non-TTY
    }

    // On most modern systems, terminals use UTF-8
    if (builtin.os.tag == .windows) {
        // Windows console uses system code page
        return "utf-8"; // Simplified
    }

    return "utf-8";
}

/// Get the filesystem encoding
pub fn filesystemEncoding() []const u8 {
    if (builtin.os.tag == .windows) {
        return "utf-8"; // Windows uses UTF-8 with proper APIs
    }
    // Unix systems typically use UTF-8
    return "utf-8";
}

/// Get locale encoding
pub fn localeEncoding() []const u8 {
    // Simplified - in reality would check LC_CTYPE
    return "utf-8";
}
