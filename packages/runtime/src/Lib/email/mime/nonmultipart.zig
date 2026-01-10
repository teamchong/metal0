//! email.mime.nonmultipart - MIME non-multipart base class
//! Reference: cpython/Lib/email/mime/nonmultipart.py
//!
//! CPython __all__: MIMENonMultipart
//!
//! Base class for MIME types that don't support sub-parts.

const std = @import("std");
const mime = @import("../mime.zig");

/// Base class for non-multipart MIME messages
/// Prevents attach() from being called
pub const MIMENonMultipart = struct {
    const Self = @This();

    base: mime.MIMEBase,

    pub fn init(allocator: std.mem.Allocator, maintype: []const u8, subtype: []const u8) !Self {
        return .{
            .base = try mime.MIMEBase.init(allocator, maintype, subtype),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    /// Raises error - non-multipart messages cannot have attachments
    pub fn attach(self: *Self, payload: anytype) !void {
        _ = self;
        _ = payload;
        return error.MultipartConversionError;
    }
};

/// Error for attempting to attach to non-multipart
pub const MultipartConversionError = error.MultipartConversionError;

// ============================================================================
// Tests
// ============================================================================

test "MIMENonMultipart struct" {
    _ = MIMENonMultipart;
}
