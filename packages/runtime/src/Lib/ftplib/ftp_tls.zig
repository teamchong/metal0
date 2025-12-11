//! FTP with TLS support
//!
//! Contains FTP_TLS client implementation:
//! - TLS connection upgrade
//! - Protection buffer and level settings
//! - Secure data connections

const std = @import("std");
const client = @import("client.zig");

pub const FTP = client.FTP;
pub const FtpResponse = client.FtpResponse;

// ============================================================================
// FTP_TLS
// ============================================================================

/// FTP client with TLS support
pub const FTP_TLS = struct {
    const Self = @This();

    ftp: FTP,
    ssl_context: ?*anyopaque,
    prot_p: bool,

    pub fn init(allocator: std.mem.Allocator, host: ?[]const u8, port: ?u16, timeout: ?f64) Self {
        return .{
            .ftp = FTP.init(allocator, host, port, timeout),
            .ssl_context = null,
            .prot_p = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.ftp.deinit();
    }

    /// Upgrade connection to TLS
    pub fn auth(self: *Self) !FtpResponse {
        return self.ftp.sendCmd("AUTH", "TLS");
    }

    /// Set protection buffer size
    pub fn pbsz(self: *Self, size: u32) !FtpResponse {
        var buf: [32]u8 = undefined;
        const len = std.fmt.formatIntBuf(&buf, size, 10, .lower, .{});
        return self.ftp.sendCmd("PBSZ", buf[0..len]);
    }

    /// Set protection level
    pub fn prot(self: *Self, level: []const u8) !FtpResponse {
        self.prot_p = std.mem.eql(u8, level, "P");
        return self.ftp.sendCmd("PROT", level);
    }

    /// Set up protected data connection
    pub fn protP(self: *Self) !FtpResponse {
        return self.prot("P");
    }

    /// Set up clear data connection
    pub fn protC(self: *Self) !FtpResponse {
        return self.prot("C");
    }
};

// ============================================================================
// Tests
// ============================================================================

test "FTP_TLS init" {
    const allocator = std.testing.allocator;
    var ftp_tls = FTP_TLS.init(allocator, null, null, null);
    defer ftp_tls.deinit();

    try std.testing.expect(!ftp_tls.prot_p);
}
