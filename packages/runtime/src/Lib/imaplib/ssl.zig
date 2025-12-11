//! IMAP4 SSL and stream variants
//!
//! Mirrors: CPython Lib/imaplib.py (IMAP4_SSL, IMAP4_stream)

const std = @import("std");
const types = @import("types.zig");
const imap4 = @import("imap4.zig");

const IMAP4 = imap4.IMAP4;
const IMAP4_SSL_PORT = types.IMAP4_SSL_PORT;

// ============================================================================
// IMAP4_SSL
// ============================================================================

/// IMAP4 client with SSL support
pub const IMAP4_SSL = struct {
    const Self = @This();

    imap: IMAP4,
    ssl_context: ?*anyopaque,
    keyfile: ?[]const u8,
    certfile: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: ?u16, keyfile: ?[]const u8, certfile: ?[]const u8, ssl_context: ?*anyopaque, timeout: ?f64) !Self {
        return .{
            .imap = try IMAP4.init(allocator, host, port orelse IMAP4_SSL_PORT, timeout),
            .ssl_context = ssl_context,
            .keyfile = keyfile,
            .certfile = certfile,
        };
    }

    pub fn deinit(self: *Self) void {
        self.imap.deinit();
    }
};

// ============================================================================
// IMAP4_stream
// ============================================================================

/// IMAP4 client over subprocess
pub const IMAP4_stream = struct {
    const Self = @This();

    imap: IMAP4,
    command: []const u8,

    pub fn init(allocator: std.mem.Allocator, command: []const u8) !Self {
        return .{
            .imap = try IMAP4.init(allocator, "", 0, null),
            .command = command,
        };
    }

    pub fn deinit(self: *Self) void {
        self.imap.deinit();
    }
};
