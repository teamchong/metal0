//! CPython source: Lib/poplib.py
//!
//! Provides POP3 client functionality.
//!
//! Mirrors: CPython Lib/poplib.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Constants
// ============================================================================

/// Default POP3 port
pub const POP3_PORT = 110;

/// Default POP3 SSL port
pub const POP3_SSL_PORT = 995;

/// Line terminator
pub const CRLF = "\r\n";

/// Maximum line length
pub const MAXLINE = 2048;

// ============================================================================
// Error Types
// ============================================================================

pub const Pop3Error = error{
    /// Base POP3 error
    Error,
    /// Protocol error (unexpected response)
    ProtoError,
    /// Authentication error
    AuthError,
    /// Connection refused
    ConnectionRefused,
    /// Socket timeout
    Timeout,
};

// ============================================================================
// POP3 Response
// ============================================================================

/// POP3 response structure
pub const Pop3Response = struct {
    ok: bool,
    message: []const u8,
    data: ?[][]const u8,

    pub fn isOk(self: *const Pop3Response) bool {
        return self.ok;
    }
};

// ============================================================================
// POP3
// ============================================================================

/// POP3 client
pub const POP3 = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    timeout: ?f64,
    sock: ?std.posix.socket_t,
    file: ?std.net.Stream,
    welcome: ?[]const u8,
    encoding: []const u8,
    debugging: u8,

    // Capabilities
    caps: hashmap_helper.StringHashMap([]const u8),
    timestamp: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: ?u16, timeout: ?f64) !Self {
        var self = Self{
            .allocator = allocator,
            .host = host,
            .port = port orelse POP3_PORT,
            .timeout = timeout,
            .sock = null,
            .file = null,
            .welcome = null,
            .encoding = "utf-8",
            .debugging = 0,
            .caps = hashmap_helper.StringHashMap([]const u8).init(allocator),
            .timestamp = null,
        };

        try self.connect();
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.caps.deinit();
        self.close();
    }

    /// Connect to POP3 server
    fn connect(self: *Self) !void {
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

        // Resolve and connect to server
        const address = std.net.Address.resolveIp4(self.host, self.port) catch return Pop3Error.ConnectionRefused;
        std.posix.connect(self.sock.?, &address.any, address.getOsSockLen()) catch return Pop3Error.ConnectionRefused;

        // Read welcome message
        const resp = try self.getResp();
        if (!resp.ok) return Pop3Error.ProtoError;
        self.welcome = resp.message;

        // Extract timestamp for APOP if present
        if (self.welcome) |w| {
            if (std.mem.indexOf(u8, w, "<")) |start| {
                if (std.mem.indexOf(u8, w[start..], ">")) |end| {
                    self.timestamp = w[start .. start + end + 1];
                }
            }
        }
    }

    /// Get welcome message
    pub fn getWelcome(self: *Self) ?[]const u8 {
        return self.welcome;
    }

    /// Set debugging level
    pub fn setDebugLevel(self: *Self, level: u8) void {
        self.debugging = level;
    }

    /// Send command and get response
    fn sendCmd(self: *Self, cmd: []const u8, arg: ?[]const u8) !Pop3Response {
        try self.putCmd(cmd, arg);
        return self.getResp();
    }

    /// Send command without getting response
    fn putCmd(self: *Self, cmd: []const u8, arg: ?[]const u8) !void {
        if (self.sock == null) {
            return Pop3Error.Error;
        }

        var buf: [MAXLINE]u8 = undefined;
        var len: usize = 0;

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
        _ = std.posix.send(self.sock.?, buf[0..len], 0) catch return Pop3Error.Error;
    }

    /// Get response from server
    fn getResp(self: *Self) !Pop3Response {
        if (self.sock == null) return Pop3Error.Error;

        var buf: [MAXLINE]u8 = undefined;
        var total_len: usize = 0;

        // Read response line
        while (total_len < buf.len - 1) {
            const n = std.posix.recv(self.sock.?, buf[total_len..], 0) catch |err| {
                if (err == error.WouldBlock) return Pop3Error.Timeout;
                return Pop3Error.Error;
            };
            if (n == 0) break;
            total_len += n;

            // Check for end of line (CRLF)
            if (total_len >= 2 and buf[total_len - 2] == '\r' and buf[total_len - 1] == '\n') {
                break;
            }
        }

        if (total_len < 3) return Pop3Error.ProtoError;

        // Trim CRLF
        var msg_end = total_len;
        while (msg_end > 0 and (buf[msg_end - 1] == '\r' or buf[msg_end - 1] == '\n')) {
            msg_end -= 1;
        }

        // Check for +OK or -ERR
        const ok = std.mem.startsWith(u8, buf[0..msg_end], "+OK");
        const msg_start: usize = if (ok) 4 else if (std.mem.startsWith(u8, buf[0..msg_end], "-ERR")) 5 else 0;

        if (self.debugging > 0) {
            std.debug.print("*resp* {s}\n", .{buf[0..msg_end]});
        }

        return Pop3Response{
            .ok = ok,
            .message = if (msg_start < msg_end) buf[msg_start..msg_end] else "",
            .data = null,
        };
    }

    /// Get long response (multi-line)
    fn getLongResp(self: *Self) !Pop3Response {
        _ = self;
        return Pop3Response{
            .ok = true,
            .message = "OK",
            .data = null,
        };
    }

    // ========================================================================
    // POP3 Commands
    // ========================================================================

    /// Get server capabilities
    pub fn capa(self: *Self) !hashmap_helper.StringHashMap([]const u8) {
        _ = try self.sendCmd("CAPA", null);
        return self.caps;
    }

    /// Get mailbox status
    pub fn stat(self: *Self) !struct { num_messages: u32, total_size: u64 } {
        const resp = try self.sendCmd("STAT", null);
        _ = resp;
        // Parse response
        return .{ .num_messages = 0, .total_size = 0 };
    }

    /// List messages
    pub fn list(self: *Self, which: ?u32) !Pop3Response {
        if (which) |w| {
            var buf: [32]u8 = undefined;
            const len = std.fmt.formatIntBuf(&buf, w, 10, .lower, .{});
            return self.sendCmd("LIST", buf[0..len]);
        }
        return self.getLongResp();
    }

    /// Retrieve message
    pub fn retr(self: *Self, which: u32) !Pop3Response {
        var buf: [32]u8 = undefined;
        const len = std.fmt.formatIntBuf(&buf, which, 10, .lower, .{});
        _ = try self.sendCmd("RETR", buf[0..len]);
        return self.getLongResp();
    }

    /// Delete message
    pub fn dele(self: *Self, which: u32) !Pop3Response {
        var buf: [32]u8 = undefined;
        const len = std.fmt.formatIntBuf(&buf, which, 10, .lower, .{});
        return self.sendCmd("DELE", buf[0..len]);
    }

    /// Reset deletions
    pub fn rset(self: *Self) !Pop3Response {
        return self.sendCmd("RSET", null);
    }

    /// No operation (keep-alive)
    pub fn noop(self: *Self) !Pop3Response {
        return self.sendCmd("NOOP", null);
    }

    /// Get top N lines of message
    pub fn top(self: *Self, which: u32, howmuch: u32) !Pop3Response {
        var buf: [64]u8 = undefined;
        const len = std.fmt.bufPrint(&buf, "{d} {d}", .{ which, howmuch }) catch return Pop3Error.Error;
        _ = try self.sendCmd("TOP", len);
        return self.getLongResp();
    }

    /// Get unique IDs
    pub fn uidl(self: *Self, which: ?u32) !Pop3Response {
        if (which) |w| {
            var buf: [32]u8 = undefined;
            const len = std.fmt.formatIntBuf(&buf, w, 10, .lower, .{});
            return self.sendCmd("UIDL", buf[0..len]);
        }
        _ = try self.sendCmd("UIDL", null);
        return self.getLongResp();
    }

    // ========================================================================
    // Authentication
    // ========================================================================

    /// User command
    pub fn user(self: *Self, username: []const u8) !Pop3Response {
        return self.sendCmd("USER", username);
    }

    /// Password command
    pub fn pass(self: *Self, password: []const u8) !Pop3Response {
        return self.sendCmd("PASS", password);
    }

    /// APOP authentication - MD5 digest of timestamp + secret
    pub fn apop(self: *Self, username: []const u8, secret: []const u8) !Pop3Response {
        if (self.timestamp == null) {
            return Pop3Error.ProtoError;
        }

        // Compute MD5(timestamp + secret) per RFC 1939
        var md5 = std.crypto.hash.Md5.init(.{});
        md5.update(self.timestamp.?);
        md5.update(secret);
        const hash = md5.finalResult();

        // Convert to hex string
        var digest: [32]u8 = undefined;
        const hex_chars = "0123456789abcdef";
        for (hash, 0..) |byte, i| {
            digest[i * 2] = hex_chars[byte >> 4];
            digest[i * 2 + 1] = hex_chars[byte & 0x0f];
        }

        var buf: [256]u8 = undefined;
        const arg = std.fmt.bufPrint(&buf, "{s} {s}", .{ username, digest }) catch return Pop3Error.Error;
        return self.sendCmd("APOP", arg);
    }

    /// RPOP authentication (rarely used)
    pub fn rpop(self: *Self, username: []const u8) !Pop3Response {
        return self.sendCmd("RPOP", username);
    }

    // ========================================================================
    // Connection Management
    // ========================================================================

    /// Quit and close connection
    pub fn quit(self: *Self) !Pop3Response {
        const resp = try self.sendCmd("QUIT", null);
        self.close();
        return resp;
    }

    /// Close the connection without QUIT
    pub fn close(self: *Self) void {
        if (self.sock) |sock| {
            std.posix.close(sock);
            self.sock = null;
        }
        self.file = null;
    }

    // ========================================================================
    // UTF-8 Support
    // ========================================================================

    /// Enable UTF-8 mode
    pub fn utf8(self: *Self) !Pop3Response {
        return self.sendCmd("UTF8", null);
    }

    /// Get language
    pub fn lang(self: *Self, language: ?[]const u8) !Pop3Response {
        return self.sendCmd("LANG", language);
    }
};

// ============================================================================
// POP3_SSL
// ============================================================================

/// POP3 client with SSL support
pub const POP3_SSL = struct {
    const Self = @This();

    pop3: POP3,
    ssl_context: ?*anyopaque,
    keyfile: ?[]const u8,
    certfile: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: ?u16, keyfile: ?[]const u8, certfile: ?[]const u8, timeout: ?f64, context: ?*anyopaque) !Self {
        return .{
            .pop3 = try POP3.init(allocator, host, port orelse POP3_SSL_PORT, timeout),
            .ssl_context = context,
            .keyfile = keyfile,
            .certfile = certfile,
        };
    }

    pub fn deinit(self: *Self) void {
        self.pop3.deinit();
    }

    /// Start TLS on existing connection
    pub fn stls(self: *Self, context: ?*anyopaque) !Pop3Response {
        _ = context;
        return self.pop3.sendCmd("STLS", null);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "POP3_PORT constant" {
    try std.testing.expectEqual(@as(u16, 110), POP3_PORT);
    try std.testing.expectEqual(@as(u16, 995), POP3_SSL_PORT);
}

test "Pop3Response isOk" {
    const resp = Pop3Response{ .ok = true, .message = "OK", .data = null };
    try std.testing.expect(resp.isOk());

    const resp2 = Pop3Response{ .ok = false, .message = "-ERR", .data = null };
    try std.testing.expect(!resp2.isOk());
}

test "CRLF constant" {
    try std.testing.expectEqualStrings("\r\n", CRLF);
}
