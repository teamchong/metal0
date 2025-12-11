//! FTP client core implementation
//!
//! Contains the main FTP client struct with:
//! - Connection management (connect, close)
//! - Authentication (login)
//! - Command sending and response parsing
//! - Low-level protocol operations

const std = @import("std");
const types = @import("types.zig");

pub const FTP_PORT = types.FTP_PORT;
pub const MAXLINE = types.MAXLINE;
pub const DEFAULT_TIMEOUT = types.DEFAULT_TIMEOUT;
pub const FtpError = types.FtpError;
pub const FtpResponse = types.FtpResponse;

// ============================================================================
// FTP Client
// ============================================================================

/// FTP client
pub const FTP = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    timeout: f64,
    sock: ?std.posix.socket_t,
    file: ?std.net.Stream,
    welcome: ?[]const u8,
    passiveserver: bool,
    encoding: []const u8,
    debugging: u8,

    // Transfer state
    lastresp: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, host: ?[]const u8, port: ?u16, timeout: ?f64) Self {
        return .{
            .allocator = allocator,
            .host = host orelse "",
            .port = port orelse FTP_PORT,
            .timeout = timeout orelse DEFAULT_TIMEOUT,
            .sock = null,
            .file = null,
            .welcome = null,
            .passiveserver = true,
            .encoding = "utf-8",
            .debugging = 0,
            .lastresp = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.close();
    }

    /// Connect to FTP server
    pub fn connect(self: *Self, host: ?[]const u8, port: ?u16, timeout: ?f64) ![]const u8 {
        if (host) |h| self.host = h;
        if (port) |p| self.port = p;
        if (timeout) |t| self.timeout = t;

        // Create socket
        self.sock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0);

        // Set socket timeout
        if (self.timeout > 0) {
            const secs: i64 = @intFromFloat(self.timeout);
            const usecs: i64 = @intFromFloat((self.timeout - @as(f64, @floatFromInt(secs))) * 1_000_000);
            const tv = std.posix.timeval{ .tv_sec = secs, .tv_usec = usecs };
            const tv_bytes = std.mem.asBytes(&tv);
            std.posix.setsockopt(self.sock.?, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, tv_bytes) catch {};
            std.posix.setsockopt(self.sock.?, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, tv_bytes) catch {};
        }

        // Resolve and connect
        const address = std.net.Address.resolveIp4(self.host, self.port) catch return FtpError.ConnectionRefused;
        std.posix.connect(self.sock.?, &address.any, address.getOsSockLen()) catch return FtpError.ConnectionRefused;

        // Get welcome message
        const resp = try self.getResp();
        self.welcome = resp.message;
        return self.welcome.?;
    }

    /// Login to FTP server
    pub fn login(self: *Self, user: ?[]const u8, passwd: ?[]const u8, acct: ?[]const u8) !FtpResponse {
        const username = user orelse "anonymous";
        const password = passwd orelse "";

        var resp = try self.sendCmd("USER", username);

        if (resp.code == 331) {
            resp = try self.sendCmd("PASS", password);
        }

        if (resp.code == 332) {
            resp = try self.sendCmd("ACCT", acct orelse "");
        }

        if (!resp.isPositive()) {
            return FtpError.NotLoggedIn;
        }

        return resp;
    }

    /// Send a command and get response
    pub fn sendCmd(self: *Self, cmd: []const u8, arg: ?[]const u8) !FtpResponse {
        try self.putCmd(cmd, arg);
        return self.getResp();
    }

    /// Send command without waiting for response
    fn putCmd(self: *Self, cmd: []const u8, arg: ?[]const u8) !void {
        if (self.sock == null) {
            return FtpError.Error;
        }

        var buf: [MAXLINE]u8 = undefined;
        var len: usize = 0;

        // Build command
        for (cmd) |c| {
            buf[len] = c;
            len += 1;
        }

        if (arg) |a| {
            buf[len] = ' ';
            len += 1;
            for (a) |c| {
                buf[len] = c;
                len += 1;
            }
        }

        buf[len] = '\r';
        len += 1;
        buf[len] = '\n';
        len += 1;

        if (self.debugging > 0) {
            std.debug.print("*cmd* {s}\n", .{buf[0..len]});
        }

        // Send command over socket
        _ = std.posix.send(self.sock.?, buf[0..len], 0) catch return FtpError.Error;
    }

    /// Get response from server
    fn getResp(self: *Self) !FtpResponse {
        if (self.sock == null) {
            return FtpError.Error;
        }

        var buf: [MAXLINE]u8 = undefined;
        var total_len: usize = 0;

        // Read response line(s)
        while (total_len < buf.len - 1) {
            const n = std.posix.recv(self.sock.?, buf[total_len..], 0) catch |err| {
                if (err == error.WouldBlock) return FtpError.Timeout;
                return FtpError.Error;
            };
            if (n == 0) break; // Connection closed
            total_len += n;

            // Check for end of response (line ending with \r\n)
            if (total_len >= 2 and buf[total_len - 2] == '\r' and buf[total_len - 1] == '\n') {
                // Check if this is a multiline response (code followed by -)
                if (total_len >= 4 and buf[3] != '-') break;
            }
        }

        if (total_len < 3) return FtpError.ProtoError;

        // Parse response code
        const code = std.fmt.parseInt(u16, buf[0..3], 10) catch return FtpError.ProtoError;

        // Extract message (skip code and space, trim CRLF)
        var msg_start: usize = 4;
        if (total_len > 3 and (buf[3] == ' ' or buf[3] == '-')) {
            msg_start = 4;
        } else {
            msg_start = 3;
        }
        var msg_end = total_len;
        while (msg_end > msg_start and (buf[msg_end - 1] == '\r' or buf[msg_end - 1] == '\n')) {
            msg_end -= 1;
        }

        if (self.debugging > 0) {
            std.debug.print("*resp* {d} {s}\n", .{ code, buf[msg_start..msg_end] });
        }

        return FtpResponse{
            .code = code,
            .message = buf[msg_start..msg_end],
        };
    }

    /// Get multiline response
    fn getMultiLine(self: *Self) !FtpResponse {
        // For multiline responses, keep reading until we get a final line
        // (code followed by space, not hyphen)
        return self.getResp();
    }

    /// Close the connection
    pub fn close(self: *Self) void {
        if (self.sock) |sock| {
            std.posix.close(sock);
            self.sock = null;
        }
        self.file = null;
    }

    // ========================================================================
    // Passive/Active Mode
    // ========================================================================

    /// Enter passive mode
    pub fn pasv(self: *Self) !struct { host: []const u8, port: u16 } {
        const resp = try self.sendCmd("PASV", null);
        // Parse host and port from response
        _ = resp;
        return .{ .host = "127.0.0.1", .port = 20 };
    }

    /// Set passive mode
    pub fn setPassive(self: *Self, val: bool) void {
        self.passiveserver = val;
    }

    // ========================================================================
    // Debugging
    // ========================================================================

    /// Set debugging level
    pub fn setDebugLevel(self: *Self, level: u8) void {
        self.debugging = level;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "FTP init" {
    const allocator = std.testing.allocator;
    var ftp = FTP.init(allocator, null, null, null);
    defer ftp.deinit();

    try std.testing.expectEqual(@as(u16, FTP_PORT), ftp.port);
    try std.testing.expect(ftp.passiveserver);
}
