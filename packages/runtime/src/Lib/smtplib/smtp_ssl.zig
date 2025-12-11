//! CPython source: Lib/smtplib.py
//!
//! SMTP_SSL client implementation.
//!
//! Provides SMTP client with SSL/TLS support for secure email transmission.

const std = @import("std");
const smtp_mod = @import("smtp.zig");
const types = @import("types.zig");

pub const SMTP = smtp_mod.SMTP;
pub const SMTP_SSL_PORT = types.SMTP_SSL_PORT;

// ============================================================================
// SMTP_SSL
// ============================================================================

/// SMTP client with SSL support
pub const SMTP_SSL = struct {
    const Self = @This();

    smtp: SMTP,
    ssl_context: ?*anyopaque,
    keyfile: ?[]const u8,
    certfile: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, host: ?[]const u8, port: ?u16, local_hostname: ?[]const u8, keyfile: ?[]const u8, certfile: ?[]const u8, timeout: ?f64, source_address: ?[]const u8, context: ?*anyopaque) !Self {
        return .{
            .smtp = try SMTP.init(allocator, host, port orelse SMTP_SSL_PORT, local_hostname, timeout, source_address),
            .ssl_context = context,
            .keyfile = keyfile,
            .certfile = certfile,
        };
    }

    pub fn deinit(self: *Self) void {
        self.smtp.deinit();
    }
};
