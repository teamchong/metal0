//! xml.sax._exceptions - SAX exception classes
//! Reference: cpython/Lib/xml/sax/_exceptions.py
//!
//! This module provides SAX exception classes.

const std = @import("std");
const sax = @import("../sax.zig");

// Re-export from parent (DRY)
pub const SAXException = sax.SAXException;
pub const SAXParseException = sax.SAXParseException;

/// SAX not recognized exception
/// CPython: class SAXNotRecognizedException(SAXException)
pub const SAXNotRecognizedException = struct {
    message: []const u8,

    pub fn init(message: []const u8) SAXNotRecognizedException {
        return .{ .message = message };
    }
};

/// SAX not supported exception
/// CPython: class SAXNotSupportedException(SAXException)
pub const SAXNotSupportedException = struct {
    message: []const u8,

    pub fn init(message: []const u8) SAXNotSupportedException {
        return .{ .message = message };
    }
};

/// SAX reader not available exception
/// CPython: class SAXReaderNotAvailable(SAXNotSupportedException)
pub const SAXReaderNotAvailable = struct {
    message: []const u8,

    pub fn init(message: []const u8) SAXReaderNotAvailable {
        return .{ .message = message };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "SAXParseException" {
    const exc = SAXParseException.init("Parse error");
    try std.testing.expectEqualStrings("Parse error", exc.message);
}

test "SAXNotRecognizedException" {
    const exc = SAXNotRecognizedException.init("Feature not recognized");
    try std.testing.expectEqualStrings("Feature not recognized", exc.message);
}
