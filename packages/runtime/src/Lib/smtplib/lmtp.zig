//! CPython source: Lib/smtplib.py
//!
//! LMTP (Local Mail Transfer Protocol) client implementation.
//!
//! LMTP is a variant of SMTP designed for local mail delivery.

const std = @import("std");
const smtp_mod = @import("smtp.zig");

pub const SMTP = smtp_mod.SMTP;

// ============================================================================
// LMTP
// ============================================================================

/// LMTP client (Local Mail Transfer Protocol)
pub const LMTP = struct {
    const Self = @This();

    smtp: SMTP,
    ehlo_msg: []const u8,

    pub fn init(allocator: std.mem.Allocator, host: ?[]const u8, port: ?u16, local_hostname: ?[]const u8, source_address: ?[]const u8) !Self {
        return .{
            .smtp = try SMTP.init(allocator, host, port, local_hostname, null, source_address),
            .ehlo_msg = "LHLO",
        };
    }

    pub fn deinit(self: *Self) void {
        self.smtp.deinit();
    }
};
