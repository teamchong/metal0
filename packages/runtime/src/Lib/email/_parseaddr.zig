//! email._parseaddr - Address parsing utilities
//! Reference: cpython/Lib/email/_parseaddr.py
//!
//! This module provides legacy address parsing functions.
//! For new code, use email.headerregistry instead.
//!
//! CPython __all__: ['parseaddr', 'formataddr', 'quote', 'AddressList',
//!                   'mktime_tz', 'parsedate', 'parsedate_tz']

const std = @import("std");
const utils = @import("utils.zig");

// Re-export from utils (DRY)
pub const parsedate = utils.parsedate;
pub const parsedate_tz = utils.parsedate_tz;
pub const formatdate = utils.formatdate;
pub const mktime_tz = utils.mktime_tz;

// ============================================================================
// Address Parsing
// ============================================================================

/// Parse an address string into (name, email) tuple
/// CPython: def parseaddr(addr)
pub fn parseaddr(addr: []const u8) struct { name: []const u8, email: []const u8 } {
    const trimmed = std.mem.trim(u8, addr, " \t\r\n");
    if (trimmed.len == 0) {
        return .{ .name = "", .email = "" };
    }

    // Check for "Name <email>" format
    if (std.mem.indexOf(u8, trimmed, "<")) |start| {
        if (std.mem.indexOf(u8, trimmed, ">")) |end| {
            if (end > start) {
                var name = std.mem.trim(u8, trimmed[0..start], " \t\"");
                const email = trimmed[start + 1 .. end];
                return .{ .name = name, .email = email };
            }
        }
    }

    // Check for "email (Name)" format
    if (std.mem.indexOf(u8, trimmed, "(")) |start| {
        if (std.mem.indexOf(u8, trimmed, ")")) |end| {
            if (end > start) {
                const email = std.mem.trim(u8, trimmed[0..start], " \t");
                const name = trimmed[start + 1 .. end];
                return .{ .name = name, .email = email };
            }
        }
    }

    // Just an email address
    return .{ .name = "", .email = trimmed };
}

/// Format a (name, email) pair into a properly formatted address string
/// CPython: def formataddr(pair, charset='utf-8')
pub fn formataddr(allocator: std.mem.Allocator, name: []const u8, email: []const u8) ![]u8 {
    if (name.len == 0) {
        return allocator.dupe(u8, email);
    }

    // Check if name needs quoting
    var needs_quoting = false;
    for (name) |c| {
        if (c == '"' or c == '\\' or c == '(' or c == ')' or c == '<' or c == '>') {
            needs_quoting = true;
            break;
        }
    }

    if (needs_quoting) {
        // Quote the name
        var result = std.ArrayList(u8){};
        errdefer result.deinit(allocator);

        try result.append(allocator, '"');
        for (name) |c| {
            if (c == '"' or c == '\\') {
                try result.append(allocator, '\\');
            }
            try result.append(allocator, c);
        }
        try result.append(allocator, '"');
        try result.appendSlice(allocator, " <");
        try result.appendSlice(allocator, email);
        try result.append(allocator, '>');
        return result.toOwnedSlice(allocator);
    } else {
        return std.fmt.allocPrint(allocator, "{s} <{s}>", .{ name, email });
    }
}

/// Quote a string for use in email headers
/// CPython: def quote(s)
pub fn quote(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    for (s) |c| {
        if (c == '\\' or c == '"') {
            try result.append(allocator, '\\');
        }
        try result.append(allocator, c);
    }

    return result.toOwnedSlice(allocator);
}

// ============================================================================
// AddressList
// ============================================================================

/// Parse a comma-separated list of addresses
/// CPython: class AddressList
pub const AddressList = struct {
    const Self = @This();

    addresses: std.ArrayList(Address),
    allocator: std.mem.Allocator,

    pub const Address = struct {
        name: []const u8,
        email: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator, addr_string: []const u8) !Self {
        var result = Self{
            .addresses = .{},
            .allocator = allocator,
        };

        // Split by comma and parse each address
        var parts = std.mem.splitScalar(u8, addr_string, ',');
        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t\r\n");
            if (trimmed.len > 0) {
                const parsed = parseaddr(trimmed);
                try result.addresses.append(allocator, .{
                    .name = parsed.name,
                    .email = parsed.email,
                });
            }
        }

        return result;
    }

    pub fn deinit(self: *Self) void {
        self.addresses.deinit(self.allocator);
    }

    /// Get number of addresses
    pub fn len(self: *const Self) usize {
        return self.addresses.items.len;
    }

    /// Get address at index
    pub fn get(self: *const Self, index: usize) ?Address {
        if (index >= self.addresses.items.len) return null;
        return self.addresses.items[index];
    }

    /// Concatenate with another AddressList
    pub fn add(self: *Self, other: *const Self) !void {
        for (other.addresses.items) |addr| {
            try self.addresses.append(self.allocator, addr);
        }
    }

    /// Subtract addresses in other from self
    pub fn sub(self: *Self, other: *const Self) void {
        var i: usize = 0;
        while (i < self.addresses.items.len) {
            var found = false;
            for (other.addresses.items) |other_addr| {
                if (std.ascii.eqlIgnoreCase(self.addresses.items[i].email, other_addr.email)) {
                    found = true;
                    break;
                }
            }
            if (found) {
                _ = self.addresses.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }
};

// ============================================================================
// Special Characters
// ============================================================================

/// RFC 5322 special characters
pub const SPECIALS = "()<>@,;:\\\".[]";

/// Characters that can appear in atoms
pub const ATOMCHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-/=?^_`{|}~";

// ============================================================================
// Tests
// ============================================================================

test "parseaddr simple email" {
    const result = parseaddr("user@example.com");
    try std.testing.expectEqualStrings("", result.name);
    try std.testing.expectEqualStrings("user@example.com", result.email);
}

test "parseaddr with display name" {
    const result = parseaddr("John Doe <john@example.com>");
    try std.testing.expectEqualStrings("John Doe", result.name);
    try std.testing.expectEqualStrings("john@example.com", result.email);
}

test "parseaddr quoted name" {
    const result = parseaddr("\"John Doe\" <john@example.com>");
    try std.testing.expectEqualStrings("John Doe", result.name);
    try std.testing.expectEqualStrings("john@example.com", result.email);
}

test "formataddr" {
    const allocator = std.testing.allocator;
    const result = try formataddr(allocator, "John Doe", "john@example.com");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("John Doe <john@example.com>", result);
}

test "formataddr empty name" {
    const allocator = std.testing.allocator;
    const result = try formataddr(allocator, "", "john@example.com");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("john@example.com", result);
}

test "AddressList" {
    const allocator = std.testing.allocator;
    var list = try AddressList.init(allocator, "John <john@example.com>, Jane <jane@example.com>");
    defer list.deinit();

    try std.testing.expectEqual(@as(usize, 2), list.len());
    try std.testing.expectEqualStrings("john@example.com", list.get(0).?.email);
    try std.testing.expectEqualStrings("jane@example.com", list.get(1).?.email);
}
