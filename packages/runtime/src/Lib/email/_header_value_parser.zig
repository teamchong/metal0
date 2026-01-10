//! email._header_value_parser - RFC 5322 header value parser
//! Reference: cpython/Lib/email/_header_value_parser.py
//!
//! This is an internal module for parsing structured email header values.
//! Provides token-based parsing for RFC 5322/5321 compliant headers.

const std = @import("std");

// ============================================================================
// Token Types
// ============================================================================

/// Token types for header value parsing
/// CPython: Terminal classes
pub const TokenType = enum {
    cfws, // Comment or Folding White Space
    word, // A word (atom or quoted-string)
    atom, // An atom (unquoted word)
    quoted_string, // Quoted string
    comment, // Comment in parentheses
    obs_phrase, // Obsolete phrase (for backwards compat)
    phrase, // A phrase
    domain, // Domain part of address
    local_part, // Local part of address
    addr_spec, // Full address spec
    angle_addr, // <addr-spec>
    mailbox, // name + address
    mailbox_list, // List of mailboxes
    group, // Group of addresses
    address, // Address (mailbox or group)
    address_list, // List of addresses
    date_time, // RFC 5322 date-time
    message_id, // Message-ID
    content_type, // Content-Type header
    parameter, // MIME parameter
};

/// A token from header parsing
pub const Token = struct {
    token_type: TokenType,
    value: []const u8,
    defects: std.ArrayList([]const u8),

    pub fn init(token_type: TokenType, value: []const u8) Token {
        return .{
            .token_type = token_type,
            .value = value,
            .defects = .{},
        };
    }

    pub fn deinit(self: *Token, allocator: std.mem.Allocator) void {
        self.defects.deinit(allocator);
    }
};

// ============================================================================
// Special Characters
// ============================================================================

/// RFC 5322 special characters
pub const SPECIALS = "()<>@,;:\\\".[]";

/// Characters allowed in atoms
pub const ATEXT = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-/=?^_`{|}~";

/// Dot-atom text (ATEXT + '.')
pub const DOT_ATEXT = ATEXT ++ ".";

/// Whitespace characters
pub const WSP = " \t";

/// Folding whitespace (includes CRLF)
pub const FWS = WSP ++ "\r\n";

// ============================================================================
// Parser State
// ============================================================================

/// Parser for RFC 5322 header values
pub const HeaderValueParser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    input: []const u8,
    pos: usize,
    defects: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, input: []const u8) Self {
        return .{
            .allocator = allocator,
            .input = input,
            .pos = 0,
            .defects = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.defects.deinit(self.allocator);
    }

    /// Get remaining input
    pub fn remaining(self: *const Self) []const u8 {
        return self.input[self.pos..];
    }

    /// Check if at end
    pub fn atEnd(self: *const Self) bool {
        return self.pos >= self.input.len;
    }

    /// Peek next character
    pub fn peek(self: *const Self) ?u8 {
        if (self.pos >= self.input.len) return null;
        return self.input[self.pos];
    }

    /// Consume next character
    pub fn consume(self: *Self) ?u8 {
        if (self.pos >= self.input.len) return null;
        const c = self.input[self.pos];
        self.pos += 1;
        return c;
    }

    /// Skip whitespace
    pub fn skipWS(self: *Self) void {
        while (self.pos < self.input.len and (self.input[self.pos] == ' ' or self.input[self.pos] == '\t')) {
            self.pos += 1;
        }
    }

    /// Skip CFWS (Comment Folding White Space)
    pub fn skipCFWS(self: *Self) void {
        while (!self.atEnd()) {
            const c = self.peek().?;
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                self.pos += 1;
            } else if (c == '(') {
                _ = self.parseComment() catch break;
            } else {
                break;
            }
        }
    }

    /// Parse a comment
    pub fn parseComment(self: *Self) ![]const u8 {
        if (self.peek() != '(') return error.NotAComment;

        self.pos += 1; // Skip '('
        const start = self.pos;
        var depth: usize = 1;

        while (!self.atEnd() and depth > 0) {
            const c = self.consume().?;
            if (c == '\\' and !self.atEnd()) {
                _ = self.consume(); // Skip escaped char
            } else if (c == '(') {
                depth += 1;
            } else if (c == ')') {
                depth -= 1;
            }
        }

        return self.input[start .. self.pos - 1];
    }

    /// Parse an atom
    pub fn parseAtom(self: *Self) ![]const u8 {
        const start = self.pos;
        while (!self.atEnd()) {
            const c = self.peek().?;
            if (std.mem.indexOfScalar(u8, ATEXT, c) == null) break;
            self.pos += 1;
        }
        if (self.pos == start) return error.NoAtom;
        return self.input[start..self.pos];
    }

    /// Parse a dot-atom
    pub fn parseDotAtom(self: *Self) ![]const u8 {
        const start = self.pos;
        while (!self.atEnd()) {
            const c = self.peek().?;
            if (std.mem.indexOfScalar(u8, DOT_ATEXT, c) == null) break;
            self.pos += 1;
        }
        if (self.pos == start) return error.NoDotAtom;
        return self.input[start..self.pos];
    }

    /// Parse a quoted string
    pub fn parseQuotedString(self: *Self) ![]const u8 {
        if (self.peek() != '"') return error.NotQuotedString;

        self.pos += 1; // Skip opening quote
        const start = self.pos;

        while (!self.atEnd()) {
            const c = self.consume().?;
            if (c == '\\' and !self.atEnd()) {
                _ = self.consume(); // Skip escaped char
            } else if (c == '"') {
                return self.input[start .. self.pos - 1];
            }
        }

        try self.defects.append(self.allocator, "Unterminated quoted string");
        return self.input[start..self.pos];
    }

    /// Parse a word (atom or quoted-string)
    pub fn parseWord(self: *Self) ![]const u8 {
        self.skipCFWS();
        if (self.peek() == '"') {
            return self.parseQuotedString();
        } else {
            return self.parseAtom();
        }
    }

    /// Parse a phrase (one or more words)
    pub fn parsePhrase(self: *Self) ![]const u8 {
        const start = self.pos;
        _ = try self.parseWord();

        while (true) {
            self.skipCFWS();
            if (self.peek() == '"' or std.mem.indexOfScalar(u8, ATEXT, self.peek() orelse 0) != null) {
                _ = self.parseWord() catch break;
            } else {
                break;
            }
        }

        return self.input[start..self.pos];
    }

    /// Parse local-part of address
    pub fn parseLocalPart(self: *Self) ![]const u8 {
        self.skipCFWS();
        if (self.peek() == '"') {
            return self.parseQuotedString();
        } else {
            return self.parseDotAtom();
        }
    }

    /// Parse domain
    pub fn parseDomain(self: *Self) ![]const u8 {
        self.skipCFWS();
        if (self.peek() == '[') {
            // Domain literal
            self.pos += 1;
            const start = self.pos;
            while (!self.atEnd() and self.peek() != ']') {
                self.pos += 1;
            }
            if (self.peek() == ']') self.pos += 1;
            return self.input[start .. self.pos - 1];
        } else {
            return self.parseDotAtom();
        }
    }

    /// Parse addr-spec (local@domain)
    pub fn parseAddrSpec(self: *Self) !AddrSpec {
        const local = try self.parseLocalPart();
        self.skipCFWS();

        if (self.peek() != '@') {
            try self.defects.append(self.allocator, "Missing @ in address");
            return .{ .local_part = local, .domain = "" };
        }
        self.pos += 1;

        const domain = try self.parseDomain();
        return .{ .local_part = local, .domain = domain };
    }

    /// Parse angle-addr (<addr-spec>)
    pub fn parseAngleAddr(self: *Self) !AddrSpec {
        self.skipCFWS();
        if (self.peek() != '<') return error.NotAngleAddr;
        self.pos += 1;

        self.skipCFWS();
        const addr = try self.parseAddrSpec();
        self.skipCFWS();

        if (self.peek() != '>') {
            try self.defects.append(self.allocator, "Missing > in angle-addr");
        } else {
            self.pos += 1;
        }

        return addr;
    }

    /// Parse mailbox (name <addr> or addr)
    pub fn parseMailbox(self: *Self) !Mailbox {
        self.skipCFWS();
        const start = self.pos;

        // Try to parse display name + angle-addr
        if (self.parsePhrase()) |name| {
            self.skipCFWS();
            if (self.peek() == '<') {
                const addr = try self.parseAngleAddr();
                return .{
                    .display_name = name,
                    .local_part = addr.local_part,
                    .domain = addr.domain,
                };
            }
            // Reset if no angle-addr follows
            self.pos = start;
        } else |_| {
            // No phrase, continue
        }

        // Try just angle-addr
        if (self.peek() == '<') {
            const addr = try self.parseAngleAddr();
            return .{
                .display_name = null,
                .local_part = addr.local_part,
                .domain = addr.domain,
            };
        }

        // Just addr-spec
        const addr = try self.parseAddrSpec();
        return .{
            .display_name = null,
            .local_part = addr.local_part,
            .domain = addr.domain,
        };
    }
};

/// Address specification
pub const AddrSpec = struct {
    local_part: []const u8,
    domain: []const u8,
};

/// Mailbox (display name + address)
pub const Mailbox = struct {
    display_name: ?[]const u8,
    local_part: []const u8,
    domain: []const u8,
};

// ============================================================================
// High-level Parsing Functions
// ============================================================================

/// Parse an address list header value
/// CPython: def get_address_list(value)
pub fn getAddressList(allocator: std.mem.Allocator, value: []const u8) !std.ArrayList(Mailbox) {
    var result = std.ArrayList(Mailbox){};
    errdefer result.deinit(allocator);

    var parser = HeaderValueParser.init(allocator, value);
    defer parser.deinit();

    while (!parser.atEnd()) {
        parser.skipCFWS();

        if (parser.parseMailbox()) |mailbox| {
            try result.append(allocator, mailbox);
        } else |_| {
            break;
        }

        parser.skipCFWS();
        if (parser.peek() == ',') {
            parser.pos += 1;
        } else {
            break;
        }
    }

    return result;
}

/// Parse a Content-Type header value
/// CPython: def get_content_type(value)
pub fn getContentType(value: []const u8) ContentTypeValue {
    var result = ContentTypeValue{
        .maintype = "text",
        .subtype = "plain",
    };

    // Find end of type/subtype
    var end: usize = 0;
    while (end < value.len and value[end] != ';' and value[end] != ' ' and value[end] != '\t') {
        end += 1;
    }

    const ct = std.mem.trim(u8, value[0..end], " \t");
    if (std.mem.indexOf(u8, ct, "/")) |slash| {
        result.maintype = ct[0..slash];
        result.subtype = ct[slash + 1 ..];
    }

    return result;
}

/// Content-Type value
pub const ContentTypeValue = struct {
    maintype: []const u8,
    subtype: []const u8,
};

// ============================================================================
// Tests
// ============================================================================

test "parseAtom" {
    const allocator = std.testing.allocator;
    var parser = HeaderValueParser.init(allocator, "hello world");
    defer parser.deinit();

    const atom = try parser.parseAtom();
    try std.testing.expectEqualStrings("hello", atom);
}

test "parseQuotedString" {
    const allocator = std.testing.allocator;
    var parser = HeaderValueParser.init(allocator, "\"hello world\"");
    defer parser.deinit();

    const qs = try parser.parseQuotedString();
    try std.testing.expectEqualStrings("hello world", qs);
}

test "parseAddrSpec" {
    const allocator = std.testing.allocator;
    var parser = HeaderValueParser.init(allocator, "user@example.com");
    defer parser.deinit();

    const addr = try parser.parseAddrSpec();
    try std.testing.expectEqualStrings("user", addr.local_part);
    try std.testing.expectEqualStrings("example.com", addr.domain);
}

test "parseMailbox with display name" {
    const allocator = std.testing.allocator;
    var parser = HeaderValueParser.init(allocator, "\"John Doe\" <john@example.com>");
    defer parser.deinit();

    const mailbox = try parser.parseMailbox();
    try std.testing.expectEqualStrings("John Doe", mailbox.display_name.?);
    try std.testing.expectEqualStrings("john", mailbox.local_part);
    try std.testing.expectEqualStrings("example.com", mailbox.domain);
}

test "getContentType" {
    const ct = getContentType("text/html; charset=utf-8");
    try std.testing.expectEqualStrings("text", ct.maintype);
    try std.testing.expectEqualStrings("html", ct.subtype);
}
