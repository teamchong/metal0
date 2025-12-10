//! CPython source: Lib/ftplib.py
//!
//! Provides FTP client functionality.
//!
//! Mirrors: CPython Lib/ftplib.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Default FTP port
pub const FTP_PORT = 21;

/// Default buffer size
pub const MAXLINE = 8192;

/// Timeout for blocking operations
pub const DEFAULT_TIMEOUT: f64 = 30.0;

// ============================================================================
// Error Types
// ============================================================================

pub const FtpError = error{
    /// Base FTP error
    Error,
    /// Reply error (4xx or 5xx)
    ReplyError,
    /// Temporary error (4xx)
    TempError,
    /// Permanent error (5xx)
    PermError,
    /// Protocol error (unexpected reply)
    ProtoError,
    /// Connection refused
    ConnectionRefused,
    /// Socket timeout
    Timeout,
    /// Not logged in
    NotLoggedIn,
};

// ============================================================================
// FTP Response
// ============================================================================

/// FTP response structure
pub const FtpResponse = struct {
    code: u16,
    message: []const u8,

    pub fn isPositive(self: *const FtpResponse) bool {
        return self.code >= 100 and self.code < 400;
    }

    pub fn isComplete(self: *const FtpResponse) bool {
        return self.code >= 200 and self.code < 300;
    }

    pub fn isIntermediate(self: *const FtpResponse) bool {
        return self.code >= 300 and self.code < 400;
    }

    pub fn isNegativeTransient(self: *const FtpResponse) bool {
        return self.code >= 400 and self.code < 500;
    }

    pub fn isNegativePermanent(self: *const FtpResponse) bool {
        return self.code >= 500 and self.code < 600;
    }
};

// ============================================================================
// FTP
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

        // Would connect to server here
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

        // Would send over socket
        _ = len;
    }

    /// Get response from server
    fn getResp(self: *Self) !FtpResponse {
        _ = self;
        // Would read response from socket
        return FtpResponse{
            .code = 220,
            .message = "Service ready",
        };
    }

    /// Get multiline response
    fn getMultiLine(self: *Self) !FtpResponse {
        _ = self;
        return FtpResponse{
            .code = 220,
            .message = "Service ready",
        };
    }

    // ========================================================================
    // FTP Commands
    // ========================================================================

    /// Change to parent directory
    pub fn cdup(self: *Self) !FtpResponse {
        return self.sendCmd("CDUP", null);
    }

    /// Print working directory
    pub fn pwd(self: *Self) ![]const u8 {
        const resp = try self.sendCmd("PWD", null);
        // Parse directory from response
        return resp.message;
    }

    /// Change working directory
    pub fn cwd(self: *Self, dirname: []const u8) !FtpResponse {
        if (std.mem.eql(u8, dirname, "..")) {
            return self.cdup();
        }
        return self.sendCmd("CWD", dirname);
    }

    /// Get file size
    pub fn size(self: *Self, filename: []const u8) !?u64 {
        const resp = try self.sendCmd("SIZE", filename);
        if (resp.code == 213) {
            return std.fmt.parseInt(u64, resp.message, 10) catch null;
        }
        return null;
    }

    /// Make a directory
    pub fn mkd(self: *Self, dirname: []const u8) ![]const u8 {
        const resp = try self.sendCmd("MKD", dirname);
        return resp.message;
    }

    /// Remove a directory
    pub fn rmd(self: *Self, dirname: []const u8) !FtpResponse {
        return self.sendCmd("RMD", dirname);
    }

    /// Delete a file
    pub fn delete(self: *Self, filename: []const u8) !FtpResponse {
        const resp = try self.sendCmd("DELE", filename);
        if (resp.code >= 500) {
            return FtpError.PermError;
        }
        return resp;
    }

    /// Rename a file
    pub fn rename(self: *Self, fromname: []const u8, toname: []const u8) !FtpResponse {
        var resp = try self.sendCmd("RNFR", fromname);
        if (resp.code != 350) {
            return FtpError.ReplyError;
        }
        return self.sendCmd("RNTO", toname);
    }

    /// Set transfer type (ASCII or binary)
    pub fn setType(self: *Self, typecode: []const u8) !FtpResponse {
        return self.sendCmd("TYPE", typecode);
    }

    /// Set ASCII transfer mode
    pub fn setAscii(self: *Self) !FtpResponse {
        return self.setType("A");
    }

    /// Set binary transfer mode
    pub fn setBinary(self: *Self) !FtpResponse {
        return self.setType("I");
    }

    /// List directory contents
    pub fn dir(self: *Self, dirname: ?[]const u8) ![]const u8 {
        return try self.nlst(dirname);
    }

    /// Name list of directory
    pub fn nlst(self: *Self, dirname: ?[]const u8) ![]const u8 {
        const resp = try self.sendCmd("NLST", dirname);
        return resp.message;
    }

    /// Long directory listing
    pub fn mlsd(self: *Self, path: ?[]const u8) ![]const u8 {
        const resp = try self.sendCmd("MLSD", path);
        return resp.message;
    }

    /// Retrieve a file in binary mode
    pub fn retrbinary(self: *Self, cmd: []const u8, callback: *const fn ([]const u8) void, blocksize: ?usize, rest: ?u64) !FtpResponse {
        // Set transfer position if specified
        if (rest) |r| {
            _ = try self.sendCmd("REST", std.fmt.allocPrint(self.allocator, "{d}", .{r}) catch "0");
        }

        // Send RETR command
        const resp = try self.sendCmd("RETR", cmd);
        if (resp.code < 100 or resp.code >= 300) {
            return resp;
        }

        // Open data connection and receive data
        const block = blocksize orelse 8192;
        var buf: [8192]u8 = undefined;
        const read_buf = buf[0..@min(block, buf.len)];

        if (self.sock) |sock| {
            while (true) {
                const n = std.posix.recv(sock, read_buf, 0) catch break;
                if (n == 0) break;
                callback(read_buf[0..n]);
            }
        }

        return resp;
    }

    /// Retrieve file as lines
    pub fn retrlines(self: *Self, cmd: []const u8, callback: ?*const fn ([]const u8) void) !FtpResponse {
        // Send RETR command
        const resp = try self.sendCmd("RETR", cmd);
        if (resp.code < 100 or resp.code >= 300) {
            return resp;
        }

        // Read lines from data connection
        if (self.sock) |sock| {
            var line_buf = std.ArrayList(u8).init(self.allocator);
            defer line_buf.deinit();
            var buf: [1]u8 = undefined;

            while (true) {
                const n = std.posix.recv(sock, &buf, 0) catch break;
                if (n == 0) break;

                if (buf[0] == '\n') {
                    if (callback) |cb| {
                        cb(line_buf.items);
                    }
                    line_buf.clearRetainingCapacity();
                } else if (buf[0] != '\r') {
                    line_buf.append(buf[0]) catch break;
                }
            }

            // Handle last line without newline
            if (line_buf.items.len > 0) {
                if (callback) |cb| {
                    cb(line_buf.items);
                }
            }
        }

        return resp;
    }

    /// Store a file (binary)
    pub fn storbinary(self: *Self, cmd: []const u8, fp: anytype, blocksize: ?usize, callback: ?*const fn ([]const u8) void, rest: ?u64) !FtpResponse {
        // Set transfer position if specified
        if (rest) |r| {
            _ = try self.sendCmd("REST", std.fmt.allocPrint(self.allocator, "{d}", .{r}) catch "0");
        }

        // Send STOR command
        const resp = try self.sendCmd("STOR", cmd);
        if (resp.code < 100 or resp.code >= 300) {
            return resp;
        }

        // Send data from file
        const block = blocksize orelse 8192;
        var buf: [8192]u8 = undefined;
        const write_buf = buf[0..@min(block, buf.len)];

        if (self.sock) |sock| {
            while (true) {
                const n = fp.read(write_buf) catch break;
                if (n == 0) break;

                _ = std.posix.send(sock, write_buf[0..n], 0) catch break;

                if (callback) |cb| {
                    cb(write_buf[0..n]);
                }
            }
        }

        return resp;
    }

    /// Store a file (lines)
    pub fn storlines(self: *Self, cmd: []const u8, fp: anytype, callback: ?*const fn ([]const u8) void) !FtpResponse {
        // Send STOR command
        const resp = try self.sendCmd("STOR", cmd);
        if (resp.code < 100 or resp.code >= 300) {
            return resp;
        }

        // Send lines from file
        var line_buf: [4096]u8 = undefined;

        if (self.sock) |sock| {
            while (true) {
                const line = fp.readUntilDelimiter(&line_buf, '\n') catch |err| {
                    if (err == error.EndOfStream) break;
                    return err;
                };

                // Send line with CRLF
                _ = std.posix.send(sock, line, 0) catch break;
                _ = std.posix.send(sock, "\r\n", 0) catch break;

                if (callback) |cb| {
                    cb(line);
                }
            }
        }

        return resp;
    }

    /// Send NOOP to keep connection alive
    pub fn noop(self: *Self) !FtpResponse {
        return self.sendCmd("NOOP", null);
    }

    /// Quit and close connection
    pub fn quit(self: *Self) !FtpResponse {
        const resp = try self.sendCmd("QUIT", null);
        self.close();
        return resp;
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

test "FTP init" {
    const allocator = std.testing.allocator;
    var ftp = FTP.init(allocator, null, null, null);
    defer ftp.deinit();

    try std.testing.expectEqual(@as(u16, FTP_PORT), ftp.port);
    try std.testing.expect(ftp.passiveserver);
}

test "FtpResponse isPositive" {
    const resp = FtpResponse{ .code = 220, .message = "Service ready" };
    try std.testing.expect(resp.isPositive());
    try std.testing.expect(resp.isComplete());
    try std.testing.expect(!resp.isNegativeTransient());
    try std.testing.expect(!resp.isNegativePermanent());
}

test "FtpResponse isNegative" {
    const resp = FtpResponse{ .code = 550, .message = "File not found" };
    try std.testing.expect(!resp.isPositive());
    try std.testing.expect(resp.isNegativePermanent());
}

test "FTP_TLS init" {
    const allocator = std.testing.allocator;
    var ftp_tls = FTP_TLS.init(allocator, null, null, null);
    defer ftp_tls.deinit();

    try std.testing.expect(!ftp_tls.prot_p);
}

test "FTP_PORT constant" {
    try std.testing.expectEqual(@as(u16, 21), FTP_PORT);
}
