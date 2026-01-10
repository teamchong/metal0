//! email.mime.message - MIME message message class
//! Reference: cpython/Lib/email/mime/message.py
//!
//! CPython __all__: MIMEMessage
//!
//! Class for generating message/rfc822 MIME documents.

const std = @import("std");
const email_message = @import("../message.zig");

/// MIME message container (message/rfc822)
pub const MIMEMessage = struct {
    const Self = @This();

    message: email_message.Message,

    pub fn init(allocator: std.mem.Allocator, msg: *email_message.Message, subtype: []const u8) !Self {
        var m = email_message.Message.init(allocator);

        var ct_buf: [256]u8 = undefined;
        const ct = try std.fmt.bufPrint(&ct_buf, "message/{s}", .{subtype});
        try m.set("Content-Type", ct);
        try m.set("MIME-Version", "1.0");

        // Attach the message as payload
        try m.attach(msg);

        return .{ .message = m };
    }

    pub fn deinit(self: *Self) void {
        self.message.deinit();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "MIMEMessage struct" {
    _ = MIMEMessage;
}
