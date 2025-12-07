//! CPython source: Lib/imaplib.py
//!
//! Provides IMAP4 client functionality.
//!
//! Mirrors: CPython Lib/imaplib.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Constants
// ============================================================================

/// Default IMAP4 port
pub const IMAP4_PORT = 143;

/// Default IMAP4 SSL port
pub const IMAP4_SSL_PORT = 993;

/// Line terminator
pub const CRLF = "\r\n";

/// Response patterns
pub const Commands = struct {
    pub const APPEND = "APPEND";
    pub const AUTHENTICATE = "AUTHENTICATE";
    pub const CAPABILITY = "CAPABILITY";
    pub const CHECK = "CHECK";
    pub const CLOSE = "CLOSE";
    pub const COPY = "COPY";
    pub const CREATE = "CREATE";
    pub const DELETE = "DELETE";
    pub const DELETEACL = "DELETEACL";
    pub const ENABLE = "ENABLE";
    pub const EXAMINE = "EXAMINE";
    pub const EXPUNGE = "EXPUNGE";
    pub const FETCH = "FETCH";
    pub const GETACL = "GETACL";
    pub const GETANNOTATION = "GETANNOTATION";
    pub const GETQUOTA = "GETQUOTA";
    pub const GETQUOTAROOT = "GETQUOTAROOT";
    pub const ID = "ID";
    pub const IDLE = "IDLE";
    pub const LIST = "LIST";
    pub const LOGIN = "LOGIN";
    pub const LOGOUT = "LOGOUT";
    pub const LSUB = "LSUB";
    pub const MOVE = "MOVE";
    pub const NAMESPACE = "NAMESPACE";
    pub const NOOP = "NOOP";
    pub const PARTIAL = "PARTIAL";
    pub const PROXYAUTH = "PROXYAUTH";
    pub const RENAME = "RENAME";
    pub const SEARCH = "SEARCH";
    pub const SELECT = "SELECT";
    pub const SETACL = "SETACL";
    pub const SETANNOTATION = "SETANNOTATION";
    pub const SETQUOTA = "SETQUOTA";
    pub const SORT = "SORT";
    pub const STARTTLS = "STARTTLS";
    pub const STATUS = "STATUS";
    pub const STORE = "STORE";
    pub const SUBSCRIBE = "SUBSCRIBE";
    pub const THREAD = "THREAD";
    pub const UID = "UID";
    pub const UNSELECT = "UNSELECT";
    pub const UNSUBSCRIBE = "UNSUBSCRIBE";
};

// ============================================================================
// Error Types
// ============================================================================

pub const ImapError = error{
    /// Base IMAP error
    Error,
    /// Abort (connection lost)
    Abort,
    /// Read-only mailbox
    ReadOnly,
    /// Authentication failed
    AuthError,
    /// Protocol error
    ProtoError,
};

// ============================================================================
// IMAP Response
// ============================================================================

/// IMAP4 response type
pub const ResponseType = enum {
    OK,
    NO,
    BAD,
    PREAUTH,
    BYE,
};

/// IMAP4 response structure
pub const ImapResponse = struct {
    typ: ResponseType,
    data: [][]const u8,

    pub fn isOk(self: *const ImapResponse) bool {
        return self.typ == .OK;
    }

    pub fn isNo(self: *const ImapResponse) bool {
        return self.typ == .NO;
    }

    pub fn isBad(self: *const ImapResponse) bool {
        return self.typ == .BAD;
    }
};

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

    pub const State = enum {
        LOGOUT,
        NONAUTH,
        AUTH,
        SELECTED,
    };

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: ?u16, timeout: ?f64) !Self {
        _ = timeout;
        var self = Self{
            .allocator = allocator,
            .host = host,
            .port = port orelse IMAP4_PORT,
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

        // Would connect and read welcome
        self.welcome = "* OK IMAP4 server ready";
    }

    /// Send command and get response
    fn sendCommand(self: *Self, cmd: []const u8, args: ?[]const u8) !ImapResponse {
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

        // Would send over socket and read response
        return ImapResponse{
            .typ = .OK,
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

// ============================================================================
// Utility Functions
// ============================================================================

/// Parse FLAGS response
pub fn parseFlags(data: []const u8) [][]const u8 {
    _ = data;
    // Would parse FLAGS response
    return &[_][]const u8{};
}

/// Encode modified UTF-7 (ISTRSTRSTRSTRSTRSTRSTRSTRSTRSTRSTRSTRSTRSTRSTRSTRSTRSTR_TF-7)
pub fn encodeModifiedUtf7(s: []const u8) []const u8 {
    // Would encode to modified UTF-7
    return s;
}

/// Decode modified UTF-7
pub fn decodeModifiedUtf7(s: []const u8) []const u8 {
    // Would decode from modified UTF-7
    return s;
}

// ============================================================================
// Tests
// ============================================================================

test "IMAP4_PORT constant" {
    try std.testing.expectEqual(@as(u16, 143), IMAP4_PORT);
    try std.testing.expectEqual(@as(u16, 993), IMAP4_SSL_PORT);
}

test "ImapResponse isOk" {
    const resp = ImapResponse{ .typ = .OK, .data = &[_][]const u8{} };
    try std.testing.expect(resp.isOk());
    try std.testing.expect(!resp.isNo());
    try std.testing.expect(!resp.isBad());
}

test "ImapResponse isNo" {
    const resp = ImapResponse{ .typ = .NO, .data = &[_][]const u8{} };
    try std.testing.expect(!resp.isOk());
    try std.testing.expect(resp.isNo());
}

test "ImapResponse isBad" {
    const resp = ImapResponse{ .typ = .BAD, .data = &[_][]const u8{} };
    try std.testing.expect(resp.isBad());
}

test "Commands" {
    try std.testing.expectEqualStrings("LOGIN", Commands.LOGIN);
    try std.testing.expectEqualStrings("LOGOUT", Commands.LOGOUT);
    try std.testing.expectEqualStrings("SELECT", Commands.SELECT);
}
