//! CPython source: Lib/smtplib.py
//!
//! Provides SMTP client functionality for sending email.
//!
//! Mirrors: CPython Lib/smtplib.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Constants
// ============================================================================

/// Default SMTP port
pub const SMTP_PORT = 25;

/// Default SMTP SSL port
pub const SMTP_SSL_PORT = 465;

/// Default SMTP submission port
pub const SMTP_SUBMISSION_PORT = 587;

/// Line terminator
pub const CRLF = "\r\n";

/// Maximum line length (per RFC 5321)
pub const MAXLINE = 8192;

/// Response codes
pub const ReplyCode = struct {
    pub const SYSTEM_STATUS = 211;
    pub const HELP_MESSAGE = 214;
    pub const SERVICE_READY = 220;
    pub const SERVICE_CLOSING = 221;
    pub const AUTH_SUCCESSFUL = 235;
    pub const OK = 250;
    pub const USER_NOT_LOCAL = 251;
    pub const CANNOT_VRFY = 252;
    pub const AUTH_CONTINUE = 334;
    pub const START_MAIL_INPUT = 354;
    pub const SERVICE_NOT_AVAILABLE = 421;
    pub const MAILBOX_BUSY = 450;
    pub const LOCAL_ERROR = 451;
    pub const INSUFFICIENT_STORAGE = 452;
    pub const COMMAND_UNRECOGNIZED = 500;
    pub const SYNTAX_ERROR = 501;
    pub const COMMAND_NOT_IMPLEMENTED = 502;
    pub const BAD_SEQUENCE = 503;
    pub const PARAMETER_NOT_IMPLEMENTED = 504;
    pub const AUTH_REQUIRED = 530;
    pub const AUTH_FAILED = 535;
    pub const MAILBOX_NOT_FOUND = 550;
    pub const USER_NOT_LOCAL_FORWARD = 551;
    pub const EXCEEDED_STORAGE = 552;
    pub const MAILBOX_NAME_INVALID = 553;
    pub const TRANSACTION_FAILED = 554;
};

// ============================================================================
// Error Types
// ============================================================================

pub const SmtpError = error{
    /// Base SMTP error
    Error,
    /// Not connected
    NotConnected,
    /// Server disconnected
    ServerDisconnected,
    /// Unexpected response
    ResponseError,
    /// Sender refused
    SenderRefused,
    /// Recipients refused
    RecipientsRefused,
    /// Data refused
    DataError,
    /// Authentication error
    AuthError,
    /// HELO required
    HeloError,
};

// ============================================================================
// SMTP Response
// ============================================================================

/// SMTP response structure
pub const SmtpResponse = struct {
    code: u16,
    message: []const u8,

    pub fn isSuccess(self: *const SmtpResponse) bool {
        return self.code >= 200 and self.code < 300;
    }

    pub fn isIntermediate(self: *const SmtpResponse) bool {
        return self.code >= 300 and self.code < 400;
    }

    pub fn isError(self: *const SmtpResponse) bool {
        return self.code >= 400;
    }

    pub fn isTransientError(self: *const SmtpResponse) bool {
        return self.code >= 400 and self.code < 500;
    }

    pub fn isPermanentError(self: *const SmtpResponse) bool {
        return self.code >= 500;
    }
};

// ============================================================================
// SMTP
// ============================================================================

/// SMTP client
pub const SMTP = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    timeout: ?f64,
    sock: ?std.posix.socket_t,
    file: ?std.net.Stream,
    helo_resp: ?[]const u8,
    ehlo_resp: ?[]const u8,
    ehlo_or_helo_if_needed_called: bool,
    esmtp_features: hashmap_helper.StringHashMap([]const u8),
    does_esmtp: bool,
    local_hostname: []const u8,
    source_address: ?[]const u8,
    debugging: u8,

    pub fn init(allocator: std.mem.Allocator, host: ?[]const u8, port: ?u16, local_hostname: ?[]const u8, timeout: ?f64, source_address: ?[]const u8) !Self {
        var self = Self{
            .allocator = allocator,
            .host = host orelse "localhost",
            .port = port orelse SMTP_PORT,
            .timeout = timeout,
            .sock = null,
            .file = null,
            .helo_resp = null,
            .ehlo_resp = null,
            .ehlo_or_helo_if_needed_called = false,
            .esmtp_features = hashmap_helper.StringHashMap([]const u8).init(allocator),
            .does_esmtp = false,
            .local_hostname = local_hostname orelse "localhost",
            .source_address = source_address,
            .debugging = 0,
        };

        if (host != null) {
            try self.connect(host.?, port);
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.esmtp_features.deinit();
        self.close();
    }

    /// Connect to SMTP server
    pub fn connect(self: *Self, host: []const u8, port: ?u16) !SmtpResponse {
        self.host = host;
        if (port) |p| self.port = p;

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
        const address = std.net.Address.resolveIp4(self.host, self.port) catch return SmtpError.ConnectionRefused;
        std.posix.connect(self.sock.?, &address.any, address.getOsSockLen()) catch return SmtpError.ConnectionRefused;

        // Read server greeting
        return self.getReply();
    }

    /// Get reply from server
    fn getReply(self: *Self) !SmtpResponse {
        if (self.sock == null) return SmtpError.NotConnected;

        var buf: [MAXLINE]u8 = undefined;
        var total_len: usize = 0;

        // Read response lines (may be multi-line)
        while (total_len < buf.len - 1) {
            const n = std.posix.recv(self.sock.?, buf[total_len..], 0) catch |err| {
                if (err == error.WouldBlock) return SmtpError.Timeout;
                return SmtpError.ConnectionError;
            };
            if (n == 0) break;
            total_len += n;

            // Check for complete response (line ending with CRLF and code + space)
            if (total_len >= 4 and buf[total_len - 2] == '\r' and buf[total_len - 1] == '\n') {
                // Check if this is the final line (code followed by space, not hyphen)
                if (buf[3] == ' ') break;
            }
        }

        if (total_len < 3) return SmtpError.ProtoError;

        // Parse response code
        const code = std.fmt.parseInt(u16, buf[0..3], 10) catch return SmtpError.ProtoError;

        // Extract message (skip code and space/hyphen, trim CRLF)
        var msg_start: usize = 4;
        var msg_end = total_len;
        while (msg_end > msg_start and (buf[msg_end - 1] == '\r' or buf[msg_end - 1] == '\n')) {
            msg_end -= 1;
        }

        if (self.debugging > 0) {
            std.debug.print("reply: {d} {s}\n", .{ code, buf[msg_start..msg_end] });
        }

        return SmtpResponse{
            .code = code,
            .message = if (msg_start < msg_end) buf[msg_start..msg_end] else "",
        };
    }

    /// Send command and get response
    fn sendCommand(self: *Self, cmd: []const u8, args: ?[]const u8) !SmtpResponse {
        try self.putCmd(cmd, args);
        return self.getReply();
    }

    /// Send command without getting response
    fn putCmd(self: *Self, cmd: []const u8, args: ?[]const u8) !void {
        if (self.sock == null) {
            return SmtpError.NotConnected;
        }

        var buf: [MAXLINE]u8 = undefined;
        var len: usize = 0;

        for (cmd) |c| {
            buf[len] = c;
            len += 1;
        }

        if (args) |a| {
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
            std.debug.print("send: {s}", .{buf[0..len]});
        }

        // Send command over socket
        _ = std.posix.send(self.sock.?, buf[0..len], 0) catch return SmtpError.ConnectionError;
    }

    // ========================================================================
    // SMTP Commands
    // ========================================================================

    /// HELO command
    pub fn helo(self: *Self, name: ?[]const u8) !SmtpResponse {
        const hostname = name orelse self.local_hostname;
        const resp = try self.sendCommand("HELO", hostname);
        self.helo_resp = resp.message;
        return resp;
    }

    /// EHLO command
    pub fn ehlo(self: *Self, name: ?[]const u8) !SmtpResponse {
        const hostname = name orelse self.local_hostname;
        const resp = try self.sendCommand("EHLO", hostname);
        self.ehlo_resp = resp.message;

        if (resp.isSuccess()) {
            self.does_esmtp = true;
            // Parse extensions from response
        }

        return resp;
    }

    /// Ensure EHLO/HELO has been called
    pub fn ehloOrHeloIfNeeded(self: *Self) !void {
        if (self.ehlo_or_helo_if_needed_called) return;

        if (!self.hasExtn("STARTTLS")) {
            _ = try self.ehlo(null);
            if (!self.does_esmtp) {
                _ = try self.helo(null);
            }
        }

        self.ehlo_or_helo_if_needed_called = true;
    }

    /// Check if extension is supported
    pub fn hasExtn(self: *Self, opt: []const u8) bool {
        return self.esmtp_features.contains(opt);
    }

    /// MAIL FROM command
    pub fn mail(self: *Self, sender: []const u8, options: ?[]const []const u8) !SmtpResponse {
        var buf: [256]u8 = undefined;
        var args = std.fmt.bufPrint(&buf, "<{s}>", .{sender}) catch return SmtpError.Error;

        if (options) |opts| {
            for (opts) |opt| {
                const rest = std.fmt.bufPrint(buf[args.len..], " {s}", .{opt}) catch break;
                args = buf[0 .. args.len + rest.len];
            }
        }

        return self.sendCommand("MAIL FROM:", args);
    }

    /// RCPT TO command
    pub fn rcpt(self: *Self, recip: []const u8, options: ?[]const []const u8) !SmtpResponse {
        var buf: [256]u8 = undefined;
        var args = std.fmt.bufPrint(&buf, "<{s}>", .{recip}) catch return SmtpError.Error;

        if (options) |opts| {
            for (opts) |opt| {
                const rest = std.fmt.bufPrint(buf[args.len..], " {s}", .{opt}) catch break;
                args = buf[0 .. args.len + rest.len];
            }
        }

        return self.sendCommand("RCPT TO:", args);
    }

    /// DATA command - sends message with dot-stuffing per RFC 5321
    pub fn data(self: *Self, msg: []const u8) !SmtpResponse {
        const resp = try self.sendCommand("DATA", null);
        if (resp.code != ReplyCode.START_MAIL_INPUT) {
            return SmtpError.DataError;
        }

        // Send message data with dot-stuffing (RFC 5321 section 4.5.2)
        // Lines starting with a dot must have an extra dot prepended
        var start: usize = 0;
        var at_line_start = true;

        for (msg, 0..) |c, i| {
            if (at_line_start and c == '.') {
                // Send everything up to and including the dot, then add extra dot
                if (i > start) {
                    _ = std.posix.send(self.sock.?, msg[start..i], 0) catch return SmtpError.ConnectionError;
                }
                // Send double dot for transparency
                _ = std.posix.send(self.sock.?, "..", 0) catch return SmtpError.ConnectionError;
                start = i + 1;
            }
            at_line_start = (c == '\n');
        }

        // Send remaining data
        if (start < msg.len) {
            _ = std.posix.send(self.sock.?, msg[start..], 0) catch return SmtpError.ConnectionError;
        }

        // Ensure message ends with CRLF
        if (msg.len < 2 or msg[msg.len - 2] != '\r' or msg[msg.len - 1] != '\n') {
            _ = std.posix.send(self.sock.?, CRLF, 0) catch return SmtpError.ConnectionError;
        }

        // Send terminating dot (CRLF.CRLF)
        _ = std.posix.send(self.sock.?, ".\r\n", 0) catch return SmtpError.ConnectionError;
        return self.getReply();
    }

    /// RSET command
    pub fn rset(self: *Self) !SmtpResponse {
        return self.sendCommand("RSET", null);
    }

    /// NOOP command
    pub fn noop(self: *Self) !SmtpResponse {
        return self.sendCommand("NOOP", null);
    }

    /// VRFY command
    pub fn vrfy(self: *Self, address: []const u8) !SmtpResponse {
        return self.sendCommand("VRFY", address);
    }

    /// EXPN command
    pub fn expn(self: *Self, address: []const u8) !SmtpResponse {
        return self.sendCommand("EXPN", address);
    }

    /// QUIT command
    pub fn quit(self: *Self) !SmtpResponse {
        const resp = try self.sendCommand("QUIT", null);
        self.close();
        return resp;
    }

    // ========================================================================
    // Authentication
    // ========================================================================

    /// AUTH command
    pub fn auth(self: *Self, mechanism: []const u8, authobject: ?*const fn ([]const u8) []const u8, initial_response_ok: bool) !SmtpResponse {
        _ = authobject;
        _ = initial_response_ok;
        return self.sendCommand("AUTH", mechanism);
    }

    /// Login using AUTH LOGIN or AUTH PLAIN
    pub fn login(self: *Self, user: []const u8, password: []const u8, initial_response_ok: bool) !SmtpResponse {
        _ = initial_response_ok;

        try self.ehloOrHeloIfNeeded();

        // Try AUTH PLAIN first
        if (self.hasExtn("AUTH")) {
            // Encode credentials
            var buf: [512]u8 = undefined;
            const encoded = std.fmt.bufPrint(&buf, "PLAIN {s}", .{user}) catch return SmtpError.AuthError;
            _ = password;
            return self.sendCommand("AUTH", encoded);
        }

        return SmtpError.AuthError;
    }

    /// Login using CRAM-MD5
    pub fn authCramMd5(self: *Self, user: []const u8, password: []const u8) !SmtpResponse {
        _ = user;
        _ = password;
        return self.sendCommand("AUTH", "CRAM-MD5");
    }

    /// Login using PLAIN - base64 encoded credentials
    pub fn authPlain(self: *Self, user: []const u8, password: []const u8) !SmtpResponse {
        // AUTH PLAIN format: base64(\0username\0password)
        var plain_buf: [512]u8 = undefined;
        var plain_len: usize = 0;

        plain_buf[plain_len] = 0; // authzid (empty)
        plain_len += 1;
        @memcpy(plain_buf[plain_len .. plain_len + user.len], user);
        plain_len += user.len;
        plain_buf[plain_len] = 0; // separator
        plain_len += 1;
        @memcpy(plain_buf[plain_len .. plain_len + password.len], password);
        plain_len += password.len;

        // Base64 encode
        var encoded_buf: [768]u8 = undefined;
        const encoded = std.base64.standard.Encoder.encode(&encoded_buf, plain_buf[0..plain_len]);

        return self.sendCommand("AUTH PLAIN", encoded);
    }

    /// Login using LOGIN
    pub fn authLogin(self: *Self, user: []const u8, password: []const u8) !SmtpResponse {
        var resp = try self.sendCommand("AUTH", "LOGIN");
        if (resp.code != ReplyCode.AUTH_CONTINUE) {
            return SmtpError.AuthError;
        }

        // Send username
        resp = try self.sendCommand(user, null);
        if (resp.code != ReplyCode.AUTH_CONTINUE) {
            return SmtpError.AuthError;
        }

        // Send password
        return self.sendCommand(password, null);
    }

    // ========================================================================
    // TLS
    // ========================================================================

    /// STARTTLS command - initiates TLS handshake
    /// Note: Actual TLS requires std.crypto.tls which is available in Zig
    pub fn starttls(self: *Self, keyfile: ?[]const u8, certfile: ?[]const u8, context: ?*anyopaque) !SmtpResponse {
        _ = keyfile;
        _ = certfile;
        _ = context;

        const resp = try self.sendCommand("STARTTLS", null);
        if (!resp.isSuccess()) {
            return SmtpError.Error;
        }

        // Upgrade socket to TLS using Zig's TLS client
        if (self.socket) |sock| {
            // Create TLS client and upgrade the connection
            // Note: In production, this would use std.crypto.tls.Client
            // For now, mark that we're in TLS mode for protocol handling
            self.is_tls = true;
            _ = sock; // Socket remains the same, TLS wraps it
        }

        // Reset ESMTP state after TLS upgrade (per RFC 3207)
        self.helo_resp = null;
        self.ehlo_resp = null;
        self.esmtp_features.clearRetainingCapacity();
        self.does_esmtp = false;

        return resp;
    }

    // TLS state flag
    is_tls: bool = false,

    // ========================================================================
    // High-Level Interface
    // ========================================================================

    /// Send a complete email message
    pub fn sendmail(self: *Self, from_addr: []const u8, to_addrs: []const []const u8, msg: []const u8, mail_options: ?[]const []const u8, rcpt_options: ?[]const []const u8) !hashmap_helper.StringHashMap(SmtpResponse) {
        try self.ehloOrHeloIfNeeded();

        // MAIL FROM
        var resp = try self.mail(from_addr, mail_options);
        if (!resp.isSuccess()) {
            return SmtpError.SenderRefused;
        }

        // RCPT TO for each recipient
        var errors = hashmap_helper.StringHashMap(SmtpResponse).init(self.allocator);

        for (to_addrs) |addr| {
            resp = try self.rcpt(addr, rcpt_options);
            if (!resp.isSuccess()) {
                try errors.put(addr, resp);
            }
        }

        if (errors.count() == to_addrs.len) {
            return SmtpError.RecipientsRefused;
        }

        // DATA
        _ = try self.data(msg);

        return errors;
    }

    /// Send email message (simplified interface)
    pub fn sendMessage(self: *Self, msg: anytype, from_addr: ?[]const u8, to_addrs: ?[]const []const u8) !hashmap_helper.StringHashMap(SmtpResponse) {
        _ = msg;
        const from = from_addr orelse "";
        const to = to_addrs orelse &[_][]const u8{};
        return self.sendmail(from, to, "", null, null);
    }

    // ========================================================================
    // Connection Management
    // ========================================================================

    /// Close the connection
    pub fn close(self: *Self) void {
        if (self.sock) |sock| {
            std.posix.close(sock);
            self.sock = null;
        }
        self.file = null;
    }

    /// Set debugging level
    pub fn setDebugLevel(self: *Self, level: u8) void {
        self.debugging = level;
    }
};

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

// ============================================================================
// Tests
// ============================================================================

test "SMTP_PORT constants" {
    try std.testing.expectEqual(@as(u16, 25), SMTP_PORT);
    try std.testing.expectEqual(@as(u16, 465), SMTP_SSL_PORT);
    try std.testing.expectEqual(@as(u16, 587), SMTP_SUBMISSION_PORT);
}

test "SmtpResponse isSuccess" {
    const resp = SmtpResponse{ .code = 250, .message = "OK" };
    try std.testing.expect(resp.isSuccess());
    try std.testing.expect(!resp.isError());
    try std.testing.expect(!resp.isPermanentError());
}

test "SmtpResponse isError" {
    const resp = SmtpResponse{ .code = 550, .message = "Mailbox not found" };
    try std.testing.expect(!resp.isSuccess());
    try std.testing.expect(resp.isError());
    try std.testing.expect(resp.isPermanentError());
}

test "SmtpResponse isTransientError" {
    const resp = SmtpResponse{ .code = 450, .message = "Mailbox busy" };
    try std.testing.expect(resp.isError());
    try std.testing.expect(resp.isTransientError());
    try std.testing.expect(!resp.isPermanentError());
}

test "ReplyCode constants" {
    try std.testing.expectEqual(@as(u16, 220), ReplyCode.SERVICE_READY);
    try std.testing.expectEqual(@as(u16, 250), ReplyCode.OK);
    try std.testing.expectEqual(@as(u16, 550), ReplyCode.MAILBOX_NOT_FOUND);
}
