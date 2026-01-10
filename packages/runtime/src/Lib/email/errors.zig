//! email.errors - Email exception classes
//! Reference: cpython/Lib/email/errors.py
//!
//! CPython __all__:
//!   ['MessageError', 'MessageParseError', 'HeaderParseError',
//!    'BoundaryError', 'MultipartConversionError', 'CharsetError',
//!    'MessageDefect', 'NoBoundaryInMultipartDefect', 'StartBoundaryNotFoundDefect',
//!    'CloseBoundaryNotFoundDefect', 'FirstHeaderLineIsContinuationDefect',
//!    'MisplacedEnvelopeHeaderDefect', 'MissingHeaderBodySeparatorDefect',
//!    'MalformedHeaderDefect', 'MultipartInvariantViolationDefect',
//!    'InvalidMultipartContentTransferEncodingDefect', 'UndecodableBytesDefect',
//!    'InvalidBase64PaddingDefect', 'InvalidBase64CharactersDefect',
//!    'InvalidBase64LengthDefect', 'HeaderDefect', 'InvalidHeaderDefect',
//!    'HeaderMissingRequiredValue', 'NonPrintableDefect', 'ObsoleteHeaderDefect',
//!    'NonASCIILocalPartDefect', 'InvalidDateDefect']

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

/// Base error for email package
pub const MessageError = error{
    MessageError,
};

/// Error for parsing messages
pub const MessageParseError = error{
    MessageParseError,
};

/// Error for parsing headers
pub const HeaderParseError = error{
    HeaderParseError,
};

/// Error for boundary issues
pub const BoundaryError = error{
    BoundaryError,
};

/// Error for multipart conversion
pub const MultipartConversionError = error{
    MultipartConversionError,
};

/// Error for charset issues
pub const CharsetError = error{
    CharsetError,
};

// ============================================================================
// Defect Types (Message parsing issues that don't prevent parsing)
// ============================================================================

/// Base defect type
pub const MessageDefect = struct {
    line: ?[]const u8 = null,
    message: []const u8 = "",

    pub fn init(message: []const u8) MessageDefect {
        return .{ .message = message };
    }
};

/// No boundary in multipart message
pub const NoBoundaryInMultipartDefect = struct {
    pub fn init() NoBoundaryInMultipartDefect {
        return .{};
    }
};

/// Start boundary not found
pub const StartBoundaryNotFoundDefect = struct {
    pub fn init() StartBoundaryNotFoundDefect {
        return .{};
    }
};

/// Close boundary not found
pub const CloseBoundaryNotFoundDefect = struct {
    pub fn init() CloseBoundaryNotFoundDefect {
        return .{};
    }
};

/// First header line is a continuation
pub const FirstHeaderLineIsContinuationDefect = struct {
    line: []const u8,

    pub fn init(line: []const u8) FirstHeaderLineIsContinuationDefect {
        return .{ .line = line };
    }
};

/// Envelope header found in wrong location
pub const MisplacedEnvelopeHeaderDefect = struct {
    pub fn init() MisplacedEnvelopeHeaderDefect {
        return .{};
    }
};

/// Missing header/body separator
pub const MissingHeaderBodySeparatorDefect = struct {
    pub fn init() MissingHeaderBodySeparatorDefect {
        return .{};
    }
};

/// Malformed header
pub const MalformedHeaderDefect = struct {
    line: []const u8,

    pub fn init(line: []const u8) MalformedHeaderDefect {
        return .{ .line = line };
    }
};

/// Multipart invariant violated
pub const MultipartInvariantViolationDefect = struct {
    pub fn init() MultipartInvariantViolationDefect {
        return .{};
    }
};

/// Invalid content transfer encoding for multipart
pub const InvalidMultipartContentTransferEncodingDefect = struct {
    pub fn init() InvalidMultipartContentTransferEncodingDefect {
        return .{};
    }
};

/// Undecodable bytes in message
pub const UndecodableBytesDefect = struct {
    pub fn init() UndecodableBytesDefect {
        return .{};
    }
};

/// Invalid base64 padding
pub const InvalidBase64PaddingDefect = struct {
    pub fn init() InvalidBase64PaddingDefect {
        return .{};
    }
};

/// Invalid base64 characters
pub const InvalidBase64CharactersDefect = struct {
    pub fn init() InvalidBase64CharactersDefect {
        return .{};
    }
};

/// Invalid base64 length
pub const InvalidBase64LengthDefect = struct {
    pub fn init() InvalidBase64LengthDefect {
        return .{};
    }
};

/// Header defect
pub const HeaderDefect = struct {
    pub fn init() HeaderDefect {
        return .{};
    }
};

/// Invalid header
pub const InvalidHeaderDefect = struct {
    pub fn init() InvalidHeaderDefect {
        return .{};
    }
};

/// Header missing required value
pub const HeaderMissingRequiredValue = struct {
    pub fn init() HeaderMissingRequiredValue {
        return .{};
    }
};

/// Non-printable characters in header
pub const NonPrintableDefect = struct {
    pub fn init() NonPrintableDefect {
        return .{};
    }
};

/// Obsolete header syntax
pub const ObsoleteHeaderDefect = struct {
    pub fn init() ObsoleteHeaderDefect {
        return .{};
    }
};

/// Non-ASCII characters in local part
pub const NonASCIILocalPartDefect = struct {
    pub fn init() NonASCIILocalPartDefect {
        return .{};
    }
};

/// Invalid date format
pub const InvalidDateDefect = struct {
    pub fn init() InvalidDateDefect {
        return .{};
    }
};

// ============================================================================
// Tests
// ============================================================================

test "MessageDefect" {
    const defect = MessageDefect.init("test error");
    try std.testing.expectEqualStrings("test error", defect.message);
}

test "MalformedHeaderDefect" {
    const defect = MalformedHeaderDefect.init("bad header line");
    try std.testing.expectEqualStrings("bad header line", defect.line);
}
