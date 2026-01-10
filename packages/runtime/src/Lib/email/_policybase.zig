//! email._policybase - Base classes for email policies
//! Reference: cpython/Lib/email/_policybase.py
//!
//! This module provides the base policy classes for email handling.
//! Use email.policy for the public API.

const std = @import("std");
const policy = @import("policy.zig");

// Re-export Policy from policy module (DRY)
pub const Policy = policy.Policy;
pub const EmailPolicy = policy.EmailPolicy;

// ============================================================================
// Policy Base Class
// ============================================================================

/// Base class for all email policies
/// CPython: class _PolicyBase
pub const PolicyBase = struct {
    const Self = @This();

    // Policy settings
    max_line_length: usize = 78,
    linesep: []const u8 = "\n",
    cte_type: []const u8 = "8bit",
    raise_on_defect: bool = false,

    /// Create a new policy with modified settings
    pub fn clone(self: *const Self) Self {
        return self.*;
    }

    /// Check for errors based on policy
    pub fn handleDefect(self: *const Self, obj: anytype, defect: []const u8) !void {
        _ = obj;
        if (self.raise_on_defect) {
            return error.EmailDefect;
        }
        // Log defect (in real implementation)
        _ = defect;
    }

    /// Register a defect on an object
    pub fn registerDefect(self: *const Self, obj: *anyopaque, defect: []const u8) void {
        _ = self;
        _ = obj;
        _ = defect;
        // Add to object's defects list
    }
};

// ============================================================================
// Compat32 Policy
// ============================================================================

/// Policy compatible with Python 3.2 email behavior
/// CPython: class Compat32(_PolicyBase)
pub const Compat32 = struct {
    const Self = @This();

    base: PolicyBase = .{
        .max_line_length = 78,
        .linesep = "\n",
        .cte_type = "8bit",
        .raise_on_defect = false,
    },

    /// Parse a header value
    pub fn headerSourceParse(self: *const Self, sourcelines: []const []const u8) []const u8 {
        _ = self;
        if (sourcelines.len == 0) return "";
        return sourcelines[0];
    }

    /// Store a header value
    pub fn headerStoreEncode(self: *const Self, name: []const u8, value: []const u8) struct { []const u8, []const u8 } {
        _ = self;
        return .{ name, value };
    }

    /// Fold a header
    pub fn headerFold(self: *const Self, name: []const u8, value: []const u8, allocator: std.mem.Allocator) ![]u8 {
        const max_len = self.base.max_line_length;
        _ = max_len;
        return std.fmt.allocPrint(allocator, "{s}: {s}{s}", .{ name, value, self.base.linesep });
    }
};

/// Default compat32 policy instance
pub const compat32 = Compat32{};

// ============================================================================
// Email Policy
// ============================================================================

/// Modern email policy
/// CPython: class EmailPolicy(_PolicyBase)
pub const ModernEmailPolicy = struct {
    const Self = @This();

    base: PolicyBase = .{
        .max_line_length = 78,
        .linesep = "\r\n",
        .cte_type = "8bit",
        .raise_on_defect = false,
    },

    utf8: bool = false,
    refold_source: []const u8 = "long",
    header_factory: ?*const fn ([]const u8, []const u8) anyerror!void = null,
    content_manager: ?*anyopaque = null,

    /// Check if header should be refold
    pub fn headerMaxCount(self: *const Self, name: []const u8) ?usize {
        _ = self;
        // These headers should appear only once
        const unique_headers = [_][]const u8{
            "content-type",
            "content-disposition",
            "content-transfer-encoding",
            "mime-version",
            "message-id",
            "date",
            "from",
            "sender",
            "reply-to",
            "to",
            "cc",
            "bcc",
            "subject",
        };

        const lower = std.ascii.lowerString(64, name) catch name;
        for (unique_headers) |h| {
            if (std.mem.eql(u8, lower, h)) return 1;
        }
        return null;
    }

    /// Fold a header for transmission
    pub fn headerFold(self: *const Self, name: []const u8, value: []const u8, allocator: std.mem.Allocator) ![]u8 {
        const max_len = self.base.max_line_length;
        if (name.len + 2 + value.len <= max_len) {
            return std.fmt.allocPrint(allocator, "{s}: {s}{s}", .{ name, value, self.base.linesep });
        }

        // Need to fold
        var result = std.ArrayList(u8){};
        errdefer result.deinit(allocator);

        try result.appendSlice(allocator, name);
        try result.appendSlice(allocator, ": ");

        var line_len = name.len + 2;
        var parts = std.mem.splitScalar(u8, value, ' ');
        var first = true;

        while (parts.next()) |word| {
            if (!first and line_len + 1 + word.len > max_len) {
                // Start new line
                try result.appendSlice(allocator, self.base.linesep);
                try result.append(allocator, '\t');
                line_len = 1;
            } else if (!first) {
                try result.append(allocator, ' ');
                line_len += 1;
            }
            try result.appendSlice(allocator, word);
            line_len += word.len;
            first = false;
        }

        try result.appendSlice(allocator, self.base.linesep);
        return result.toOwnedSlice(allocator);
    }
};

/// Default modern policy instances
pub const default = ModernEmailPolicy{};
pub const smtp = ModernEmailPolicy{ .base = .{ .linesep = "\r\n", .max_line_length = 998 } };
pub const smtputf8 = ModernEmailPolicy{ .base = .{ .linesep = "\r\n", .max_line_length = 998 }, .utf8 = true };
pub const strict = ModernEmailPolicy{ .base = .{ .raise_on_defect = true } };

// ============================================================================
// Tests
// ============================================================================

test "PolicyBase clone" {
    const base = PolicyBase{ .max_line_length = 100 };
    const cloned = base.clone();
    try std.testing.expectEqual(@as(usize, 100), cloned.max_line_length);
}

test "Compat32 headerFold" {
    const allocator = std.testing.allocator;
    const result = try compat32.headerFold("Subject", "Hello World", allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Subject: Hello World\n", result);
}

test "ModernEmailPolicy headerMaxCount" {
    const pol = ModernEmailPolicy{};
    try std.testing.expectEqual(@as(?usize, 1), pol.headerMaxCount("Subject"));
    try std.testing.expectEqual(@as(?usize, null), pol.headerMaxCount("X-Custom"));
}

test "ModernEmailPolicy headerFold short" {
    const allocator = std.testing.allocator;
    const pol = ModernEmailPolicy{};
    const result = try pol.headerFold("Subject", "Hello", allocator);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("Subject: Hello\r\n", result);
}
