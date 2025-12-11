//! CPython source: Lib/ftplib.py
//!
//! Provides FTP client functionality.
//!
//! Mirrors: CPython Lib/ftplib.py
//!
//! This module is now organized as a modular directory structure:
//! - types.zig: Constants, errors, FtpResponse
//! - client.zig: Core FTP client and connection management
//! - commands.zig: FTP command implementations
//! - transfer.zig: File transfer operations
//! - ftp_tls.zig: TLS support

const std = @import("std");

// Re-export from submodules
pub const types = @import("ftplib/types.zig");
pub const client = @import("ftplib/client.zig");
pub const commands = @import("ftplib/commands.zig");
pub const transfer = @import("ftplib/transfer.zig");
pub const ftp_tls = @import("ftplib/ftp_tls.zig");

// Re-export commonly used types and constants
pub const FTP_PORT = types.FTP_PORT;
pub const MAXLINE = types.MAXLINE;
pub const DEFAULT_TIMEOUT = types.DEFAULT_TIMEOUT;
pub const FtpError = types.FtpError;
pub const FtpResponse = types.FtpResponse;
pub const FTP = FTPWithMethods;
pub const FTP_TLS = ftp_tls.FTP_TLS;

// ============================================================================
// FTP with Methods
// ============================================================================

/// Extended FTP client with all command methods
pub const FTPWithMethods = struct {
    const Self = @This();

    base: client.FTP,

    pub fn init(allocator: std.mem.Allocator, host: ?[]const u8, port: ?u16, timeout: ?f64) Self {
        return .{
            .base = client.FTP.init(allocator, host, port, timeout),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    // Connection management
    pub fn connect(self: *Self, host: ?[]const u8, port: ?u16, timeout: ?f64) ![]const u8 {
        return self.base.connect(host, port, timeout);
    }

    pub fn login(self: *Self, user: ?[]const u8, passwd: ?[]const u8, acct: ?[]const u8) !FtpResponse {
        return self.base.login(user, passwd, acct);
    }

    pub fn sendCmd(self: *Self, cmd: []const u8, arg: ?[]const u8) !FtpResponse {
        return self.base.sendCmd(cmd, arg);
    }

    pub fn close(self: *Self) void {
        self.base.close();
    }

    // Passive/Active mode
    pub fn pasv(self: *Self) !struct { host: []const u8, port: u16 } {
        return self.base.pasv();
    }

    pub fn setPassive(self: *Self, val: bool) void {
        self.base.setPassive(val);
    }

    // Debugging
    pub fn setDebugLevel(self: *Self, level: u8) void {
        self.base.setDebugLevel(level);
    }

    // Directory operations
    pub fn cdup(self: *Self) !FtpResponse {
        return commands.cdup(&self.base);
    }

    pub fn pwd(self: *Self) ![]const u8 {
        return commands.pwd(&self.base);
    }

    pub fn cwd(self: *Self, dirname: []const u8) !FtpResponse {
        return commands.cwd(&self.base, dirname);
    }

    pub fn mkd(self: *Self, dirname: []const u8) ![]const u8 {
        return commands.mkd(&self.base, dirname);
    }

    pub fn rmd(self: *Self, dirname: []const u8) !FtpResponse {
        return commands.rmd(&self.base, dirname);
    }

    // File operations
    pub fn size(self: *Self, filename: []const u8) !?u64 {
        return commands.size(&self.base, filename);
    }

    pub fn delete(self: *Self, filename: []const u8) !FtpResponse {
        return commands.delete(&self.base, filename);
    }

    pub fn rename(self: *Self, fromname: []const u8, toname: []const u8) !FtpResponse {
        return commands.rename(&self.base, fromname, toname);
    }

    // Transfer mode
    pub fn setType(self: *Self, typecode: []const u8) !FtpResponse {
        return commands.setType(&self.base, typecode);
    }

    pub fn setAscii(self: *Self) !FtpResponse {
        return commands.setAscii(&self.base);
    }

    pub fn setBinary(self: *Self) !FtpResponse {
        return commands.setBinary(&self.base);
    }

    // Directory listing
    pub fn dir(self: *Self, dirname: ?[]const u8) ![]const u8 {
        return commands.dir(&self.base, dirname);
    }

    pub fn nlst(self: *Self, dirname: ?[]const u8) ![]const u8 {
        return commands.nlst(&self.base, dirname);
    }

    pub fn mlsd(self: *Self, path: ?[]const u8) ![]const u8 {
        return commands.mlsd(&self.base, path);
    }

    // Connection management
    pub fn noop(self: *Self) !FtpResponse {
        return commands.noop(&self.base);
    }

    pub fn quit(self: *Self) !FtpResponse {
        return commands.quit(&self.base);
    }

    // File transfer
    pub fn retrbinary(
        self: *Self,
        cmd: []const u8,
        callback: *const fn ([]const u8) void,
        blocksize: ?usize,
        rest: ?u64,
    ) !FtpResponse {
        return transfer.retrbinary(&self.base, cmd, callback, blocksize, rest);
    }

    pub fn retrlines(
        self: *Self,
        cmd: []const u8,
        callback: ?*const fn ([]const u8) void,
    ) !FtpResponse {
        return transfer.retrlines(&self.base, cmd, callback);
    }

    pub fn storbinary(
        self: *Self,
        cmd: []const u8,
        fp: anytype,
        blocksize: ?usize,
        callback: ?*const fn ([]const u8) void,
        rest: ?u64,
    ) !FtpResponse {
        return transfer.storbinary(&self.base, cmd, fp, blocksize, callback, rest);
    }

    pub fn storlines(
        self: *Self,
        cmd: []const u8,
        fp: anytype,
        callback: ?*const fn ([]const u8) void,
    ) !FtpResponse {
        return transfer.storlines(&self.base, cmd, fp, callback);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ftplib module structure" {
    // Test that all submodules are accessible
    _ = types;
    _ = client;
    _ = commands;
    _ = transfer;
    _ = ftp_tls;
}

test "FTP init" {
    const allocator = std.testing.allocator;
    var ftp = FTP.init(allocator, null, null, null);
    defer ftp.deinit();

    try std.testing.expectEqual(@as(u16, FTP_PORT), ftp.base.port);
    try std.testing.expect(ftp.base.passiveserver);
}
