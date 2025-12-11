//! IMAP4 client implementation
//!
//! Mirrors: CPython Lib/imaplib.py (IMAP4 class)

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");
const commands = @import("commands.zig");

const ImapError = types.ImapError;
const ImapResponse = types.ImapResponse;
const ResponseType = types.ResponseType;
const State = types.State;
const Commands = commands.Commands;

// ============================================================================
// IMAP4
// ============================================================================

/// IMAP4 client
pub const IMAP4 = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    sock: ?std.posix.socket_t,
    file: ?std.net.Stream,
    welcome: ?[]const u8,
    capabilities: hashmap_helper.StringHashMap(void),
    state: State,
    debugging: u8,
    literal: ?[]const u8,
    tagged_commands: hashmap_helper.StringHashMap([]const u8),
    untagged_responses: hashmap_helper.StringHashMap([][]const u8),
    continuation_response: ?[]const u8,
    tagnum: u32,
    tagpre: []const u8,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: ?u16, timeout: ?f64) !Self {
        _ = timeout;
        var self = Self{
            .allocator = allocator,
            .host = host,
            .port = port orelse types.IMAP4_PORT,
            .sock = null,
            .file = null,
            .welcome = null,
            .capabilities = hashmap_helper.StringHashMap(void).init(allocator),
            .state = .NONAUTH,
            .debugging = 0,
            .literal = null,
            .tagged_commands = hashmap_helper.StringHashMap([]const u8).init(allocator),
            .untagged_responses = hashmap_helper.StringHashMap([][]const u8).init(allocator),
            .continuation_response = null,
            .tagnum = 0,
            .tagpre = "A",
        };

        try self.open();
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.capabilities.deinit();
        self.tagged_commands.deinit();
        self.untagged_responses.deinit();
        self.close();
    }

    /// Open connection to IMAP4 server
    fn open(self: *Self) !void {
        // Create socket
        self.sock = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0);

        // Set socket timeout
        const secs: i64 = 30; // Default 30s timeout
        const tv = std.posix.timeval{ .tv_sec = secs, .tv_usec = 0 };
        const tv_bytes = std.mem.asBytes(&tv);
        std.posix.setsockopt(self.sock.?, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, tv_bytes) catch {};
        std.posix.setsockopt(self.sock.?, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, tv_bytes) catch {};

        // Resolve and connect to server
        const address = std.net.Address.resolveIp4(self.host, self.port) catch return ImapError.ConnectionRefused;
        std.posix.connect(self.sock.?, &address.any, address.getOsSockLen()) catch return ImapError.ConnectionRefused;

        // Read welcome message (untagged)
        var buf: [1024]u8 = undefined;
        var total_len: usize = 0;
        while (total_len < buf.len - 1) {
            const n = std.posix.recv(self.sock.?, buf[total_len..], 0) catch return ImapError.ConnectionRefused;
            if (n == 0) break;
            total_len += n;
            if (total_len >= 2 and buf[total_len - 2] == '\r' and buf[total_len - 1] == '\n') break;
        }
        if (total_len > 2) {
            self.welcome = buf[0 .. total_len - 2]; // Trim CRLF
        }
    }

    /// Send command and get response
    fn sendCommand(self: *Self, cmd: []const u8, args: ?[]const u8) !ImapResponse {
        if (self.sock == null) return ImapError.Error;

        self.tagnum += 1;

        // Build tag
        var tag_buf: [16]u8 = undefined;
        const tag = std.fmt.bufPrint(&tag_buf, "{s}{d}", .{ self.tagpre, self.tagnum }) catch "A0";

        // Build command line
        var buf: [1024]u8 = undefined;
        const line = if (args) |a|
            std.fmt.bufPrint(&buf, "{s} {s} {s}\r\n", .{ tag, cmd, a }) catch ""
        else
            std.fmt.bufPrint(&buf, "{s} {s}\r\n", .{ tag, cmd }) catch "";

        if (self.debugging > 0) {
            std.debug.print("> {s}", .{line});
        }

        // Send command over socket
        _ = std.posix.send(self.sock.?, line, 0) catch return ImapError.Error;

        // Read response
        var resp_buf: [4096]u8 = undefined;
        var total_len: usize = 0;
        while (total_len < resp_buf.len - 1) {
            const n = std.posix.recv(self.sock.?, resp_buf[total_len..], 0) catch return ImapError.Error;
            if (n == 0) break;
            total_len += n;

            // Check for tagged response (our tag followed by OK/NO/BAD)
            if (total_len >= tag.len + 4) {
                if (std.mem.startsWith(u8, resp_buf[0..total_len], tag)) {
                    if (std.mem.indexOf(u8, resp_buf[0..total_len], "\r\n") != null) break;
                }
            }
        }

        // Parse response type
        var typ: ResponseType = .BAD;
        if (std.mem.indexOf(u8, resp_buf[0..total_len], "OK")) |_| {
            typ = .OK;
        } else if (std.mem.indexOf(u8, resp_buf[0..total_len], "NO")) |_| {
            typ = .NO;
        }

        if (self.debugging > 0) {
            std.debug.print("< {s}\n", .{resp_buf[0..total_len]});
        }

        return ImapResponse{
            .typ = typ,
            .data = &[_][]const u8{},
        };
    }

    // ========================================================================
    // IMAP Commands
    // ========================================================================

    /// Get capabilities
    pub fn capability(self: *Self) !ImapResponse {
        return self.sendCommand(Commands.CAPABILITY, null);
    }

    /// Login with username and password
    pub fn login(self: *Self, user: []const u8, password: []const u8) !ImapResponse {
        var buf: [256]u8 = undefined;
        const args = std.fmt.bufPrint(&buf, "\"{s}\" \"{s}\"", .{ user, password }) catch return ImapError.Error;
        const resp = try self.sendCommand(Commands.LOGIN, args);
        if (resp.isOk()) {
            self.state = .AUTH;
        }
        return resp;
    }

    /// Authenticate with SASL mechanism
    pub fn authenticate(self: *Self, mechanism: []const u8, authobject: anytype) !ImapResponse {
        _ = authobject;
        return self.sendCommand(Commands.AUTHENTICATE, mechanism);
    }

    /// Logout
    pub fn logout(self: *Self) !ImapResponse {
        self.state = .LOGOUT;
        return self.sendCommand(Commands.LOGOUT, null);
    }

    /// Select a mailbox
    pub fn selectMailbox(self: *Self, mailbox: []const u8, readonly: bool) !ImapResponse {
        const cmd = if (readonly) Commands.EXAMINE else Commands.SELECT;
        const resp = try self.sendCommand(cmd, mailbox);
        if (resp.isOk()) {
            self.state = .SELECTED;
        }
        return resp;
    }

    /// Examine a mailbox (read-only)
    pub fn examine(self: *Self, mailbox: []const u8) !ImapResponse {
        return self.selectMailbox(mailbox, true);
    }

    /// Create a mailbox
    pub fn create(self: *Self, mailbox: []const u8) !ImapResponse {
        return self.sendCommand(Commands.CREATE, mailbox);
    }

    /// Delete a mailbox
    pub fn delete(self: *Self, mailbox: []const u8) !ImapResponse {
        return self.sendCommand(Commands.DELETE, mailbox);
    }

    /// Rename a mailbox
    pub fn rename(self: *Self, oldmailbox: []const u8, newmailbox: []const u8) !ImapResponse {
        var buf: [256]u8 = undefined;
        const args = std.fmt.bufPrint(&buf, "{s} {s}", .{ oldmailbox, newmailbox }) catch return ImapError.Error;
        return self.sendCommand(Commands.RENAME, args);
    }

    /// Subscribe to mailbox
    pub fn subscribe(self: *Self, mailbox: []const u8) !ImapResponse {
        return self.sendCommand(Commands.SUBSCRIBE, mailbox);
    }

    /// Unsubscribe from mailbox
    pub fn unsubscribe(self: *Self, mailbox: []const u8) !ImapResponse {
        return self.sendCommand(Commands.UNSUBSCRIBE, mailbox);
    }

    /// List mailboxes
    pub fn list(self: *Self, directory: []const u8, pattern: []const u8) !ImapResponse {
        var buf: [256]u8 = undefined;
        const args = std.fmt.bufPrint(&buf, "\"{s}\" \"{s}\"", .{ directory, pattern }) catch return ImapError.Error;
        return self.sendCommand(Commands.LIST, args);
    }

    /// List subscribed mailboxes
    pub fn lsub(self: *Self, directory: []const u8, pattern: []const u8) !ImapResponse {
        var buf: [256]u8 = undefined;
        const args = std.fmt.bufPrint(&buf, "\"{s}\" \"{s}\"", .{ directory, pattern }) catch return ImapError.Error;
        return self.sendCommand(Commands.LSUB, args);
    }

    /// Get mailbox status
    pub fn status(self: *Self, mailbox: []const u8, names: []const u8) !ImapResponse {
        var buf: [256]u8 = undefined;
        const args = std.fmt.bufPrint(&buf, "{s} ({s})", .{ mailbox, names }) catch return ImapError.Error;
        return self.sendCommand(Commands.STATUS, args);
    }

    /// Append message to mailbox
    pub fn append(self: *Self, mailbox: []const u8, flags: ?[]const u8, date_time: ?[]const u8, message: []const u8) !ImapResponse {
        _ = flags;
        _ = date_time;
        var buf: [256]u8 = undefined;
        const args = std.fmt.bufPrint(&buf, "{s} {{{d}}}", .{ mailbox, message.len }) catch return ImapError.Error;
        self.literal = message;
        return self.sendCommand(Commands.APPEND, args);
    }

    /// Check mailbox (request checkpoint)
    pub fn check(self: *Self) !ImapResponse {
        return self.sendCommand(Commands.CHECK, null);
    }

    /// Close selected mailbox
    pub fn closeMailbox(self: *Self) !ImapResponse {
        const resp = try self.sendCommand(Commands.CLOSE, null);
        self.state = .AUTH;
        return resp;
    }

    /// Expunge deleted messages
    pub fn expunge(self: *Self) !ImapResponse {
        return self.sendCommand(Commands.EXPUNGE, null);
    }

    /// Search messages
    pub fn search(self: *Self, charset: ?[]const u8, criteria: []const u8) !ImapResponse {
        if (charset) |cs| {
            var buf: [512]u8 = undefined;
            const args = std.fmt.bufPrint(&buf, "CHARSET {s} {s}", .{ cs, criteria }) catch return ImapError.Error;
            return self.sendCommand(Commands.SEARCH, args);
        }
        return self.sendCommand(Commands.SEARCH, criteria);
    }

    /// Fetch message data
    pub fn fetch(self: *Self, message_set: []const u8, message_parts: []const u8) !ImapResponse {
        var buf: [256]u8 = undefined;
        const args = std.fmt.bufPrint(&buf, "{s} ({s})", .{ message_set, message_parts }) catch return ImapError.Error;
        return self.sendCommand(Commands.FETCH, args);
    }

    /// Store message flags
    pub fn store(self: *Self, message_set: []const u8, command: []const u8, flags: []const u8) !ImapResponse {
        var buf: [256]u8 = undefined;
        const args = std.fmt.bufPrint(&buf, "{s} {s} {s}", .{ message_set, command, flags }) catch return ImapError.Error;
        return self.sendCommand(Commands.STORE, args);
    }

    /// Copy messages
    pub fn copy(self: *Self, message_set: []const u8, new_mailbox: []const u8) !ImapResponse {
        var buf: [256]u8 = undefined;
        const args = std.fmt.bufPrint(&buf, "{s} {s}", .{ message_set, new_mailbox }) catch return ImapError.Error;
        return self.sendCommand(Commands.COPY, args);
    }

    /// Move messages (RFC 6851)
    pub fn move(self: *Self, message_set: []const u8, new_mailbox: []const u8) !ImapResponse {
        var buf: [256]u8 = undefined;
        const args = std.fmt.bufPrint(&buf, "{s} {s}", .{ message_set, new_mailbox }) catch return ImapError.Error;
        return self.sendCommand(Commands.MOVE, args);
    }

    /// UID command prefix
    pub fn uid(self: *Self, command: []const u8, args: []const u8) !ImapResponse {
        var buf: [256]u8 = undefined;
        const full_args = std.fmt.bufPrint(&buf, "{s} {s}", .{ command, args }) catch return ImapError.Error;
        return self.sendCommand(Commands.UID, full_args);
    }

    /// NOOP command
    pub fn noop(self: *Self) !ImapResponse {
        return self.sendCommand(Commands.NOOP, null);
    }

    /// Start IDLE mode
    pub fn idle(self: *Self) !ImapResponse {
        return self.sendCommand(Commands.IDLE, null);
    }

    /// Get namespace
    pub fn namespace(self: *Self) !ImapResponse {
        return self.sendCommand(Commands.NAMESPACE, null);
    }

    /// Enable extensions
    pub fn enable(self: *Self, capability_name: []const u8) !ImapResponse {
        return self.sendCommand(Commands.ENABLE, capability_name);
    }

    /// Get ID
    pub fn id(self: *Self, parameters: ?[]const u8) !ImapResponse {
        return self.sendCommand(Commands.ID, parameters orelse "NIL");
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
        self.state = .LOGOUT;
    }

    /// Get recent response for an untagged response type
    pub fn recent(self: *Self) ?[]const []const u8 {
        return self.untagged_responses.get("RECENT");
    }

    /// Get response data for a specific response type
    pub fn response(self: *Self, code: []const u8) ?[]const []const u8 {
        return self.untagged_responses.get(code);
    }

    /// Set debugging level
    pub fn setDebugLevel(self: *Self, level: u8) void {
        self.debugging = level;
    }
};
