//! email.headerregistry - Header classes for structured headers
//! Reference: cpython/Lib/email/headerregistry.py
//!
//! CPython __all__: ['Address', 'AddressHeader', 'BaseHeader', 'ContentDispositionHeader',
//!                   'ContentTransferEncodingHeader', 'ContentTypeHeader', 'DateHeader',
//!                   'Group', 'HeaderRegistry', 'MIMEVersionHeader', 'ParameterizedMIMEHeader',
//!                   'SingleAddressHeader', 'UnstructuredHeader', 'UniqueAddressHeader',
//!                   'UniqueContentDispositionHeader', 'UniqueContentTransferEncodingHeader',
//!                   'UniqueContentTypeHeader', 'UniqueDateHeader', 'UniqueMIMEVersionHeader',
//!                   'UniqueParameterizedMIMEHeader', 'UniqueSingleAddressHeader',
//!                   'UniqueUnstructuredHeader']

const std = @import("std");
const utils = @import("utils.zig");

// ============================================================================
// Address and Group
// ============================================================================

/// Email address
/// CPython: class Address
pub const Address = struct {
    display_name: []const u8,
    username: []const u8,
    domain: []const u8,

    pub fn init(display_name: []const u8, username: []const u8, domain: []const u8) Address {
        return .{
            .display_name = display_name,
            .username = username,
            .domain = domain,
        };
    }

    /// Get full email address spec (username@domain)
    pub fn addrSpec(self: *const Address) []const u8 {
        // In AOT, we'd need allocator; return username for now
        return self.username;
    }

    /// Format as string
    pub fn format(self: *const Address, allocator: std.mem.Allocator) ![]u8 {
        if (self.display_name.len > 0) {
            return std.fmt.allocPrint(allocator, "\"{s}\" <{s}@{s}>", .{
                self.display_name, self.username, self.domain,
            });
        } else {
            return std.fmt.allocPrint(allocator, "{s}@{s}", .{
                self.username, self.domain,
            });
        }
    }
};

/// Address group
/// CPython: class Group
pub const Group = struct {
    display_name: ?[]const u8,
    addresses: []const Address,

    pub fn init(display_name: ?[]const u8, addresses: []const Address) Group {
        return .{
            .display_name = display_name,
            .addresses = addresses,
        };
    }
};

// ============================================================================
// Base Header Classes
// ============================================================================

/// Base header class
/// CPython: class BaseHeader
pub const BaseHeader = struct {
    name: []const u8,
    defects: std.ArrayList([]const u8),

    pub fn init(name: []const u8, allocator: std.mem.Allocator) BaseHeader {
        _ = allocator;
        return .{
            .name = name,
            .defects = .{},
        };
    }
};

/// Unstructured header (plain text)
/// CPython: class UnstructuredHeader(BaseHeader)
pub const UnstructuredHeader = struct {
    name: []const u8,
    value: []const u8,

    pub fn parse(name: []const u8, value: []const u8) UnstructuredHeader {
        return .{ .name = name, .value = value };
    }
};

/// Unique unstructured header
/// CPython: class UniqueUnstructuredHeader(UnstructuredHeader)
pub const UniqueUnstructuredHeader = UnstructuredHeader;

// ============================================================================
// Date Header
// ============================================================================

/// Date header
/// CPython: class DateHeader(BaseHeader)
pub const DateHeader = struct {
    name: []const u8,
    value: []const u8,
    datetime: ?i64, // Unix timestamp

    pub fn parse(name: []const u8, value: []const u8) DateHeader {
        // Parse RFC 2822 date - simplified
        return .{
            .name = name,
            .value = value,
            .datetime = utils.parsedate_tz(value),
        };
    }
};

/// Unique date header
/// CPython: class UniqueDateHeader(DateHeader)
pub const UniqueDateHeader = DateHeader;

// ============================================================================
// Address Headers
// ============================================================================

/// Address header (multiple addresses)
/// CPython: class AddressHeader(BaseHeader)
pub const AddressHeader = struct {
    name: []const u8,
    value: []const u8,
    groups: std.ArrayList(Group),
    addresses: std.ArrayList(Address),

    pub fn parse(allocator: std.mem.Allocator, name: []const u8, value: []const u8) !AddressHeader {
        var result = AddressHeader{
            .name = name,
            .value = value,
            .groups = .{},
            .addresses = .{},
        };

        // Parse addresses from value - simplified
        var parts = std.mem.splitScalar(u8, value, ',');
        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");
            if (trimmed.len > 0) {
                // Parse "Name <email>" or just "email"
                if (std.mem.indexOf(u8, trimmed, "<")) |start| {
                    if (std.mem.indexOf(u8, trimmed, ">")) |end| {
                        const display_name = std.mem.trim(u8, trimmed[0..start], " \t\"");
                        const addr_spec = trimmed[start + 1 .. end];
                        if (std.mem.indexOf(u8, addr_spec, "@")) |at| {
                            try result.addresses.append(allocator, Address.init(
                                display_name,
                                addr_spec[0..at],
                                addr_spec[at + 1 ..],
                            ));
                        }
                    }
                } else if (std.mem.indexOf(u8, trimmed, "@")) |at| {
                    try result.addresses.append(allocator, Address.init(
                        "",
                        trimmed[0..at],
                        trimmed[at + 1 ..],
                    ));
                }
            }
        }

        return result;
    }

    pub fn deinit(self: *AddressHeader, allocator: std.mem.Allocator) void {
        self.groups.deinit(allocator);
        self.addresses.deinit(allocator);
    }
};

/// Single address header
/// CPython: class SingleAddressHeader(AddressHeader)
pub const SingleAddressHeader = AddressHeader;

/// Unique address header
/// CPython: class UniqueAddressHeader(AddressHeader)
pub const UniqueAddressHeader = AddressHeader;

/// Unique single address header
/// CPython: class UniqueSingleAddressHeader(SingleAddressHeader)
pub const UniqueSingleAddressHeader = AddressHeader;

// ============================================================================
// MIME Headers
// ============================================================================

/// Parameterized MIME header
/// CPython: class ParameterizedMIMEHeader(BaseHeader)
pub const ParameterizedMIMEHeader = struct {
    name: []const u8,
    value: []const u8,
    params: std.ArrayList(Param),

    pub const Param = struct {
        name: []const u8,
        value: []const u8,
    };

    pub fn parse(allocator: std.mem.Allocator, name: []const u8, value: []const u8) !ParameterizedMIMEHeader {
        var result = ParameterizedMIMEHeader{
            .name = name,
            .value = value,
            .params = .{},
        };

        // Parse parameters
        var parts = std.mem.splitScalar(u8, value, ';');
        _ = parts.next(); // Skip main value

        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");
            if (std.mem.indexOf(u8, trimmed, "=")) |eq| {
                const param_name = std.mem.trim(u8, trimmed[0..eq], " \t");
                var param_value = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
                // Remove quotes
                if (param_value.len >= 2 and param_value[0] == '"' and param_value[param_value.len - 1] == '"') {
                    param_value = param_value[1 .. param_value.len - 1];
                }
                try result.params.append(allocator, .{ .name = param_name, .value = param_value });
            }
        }

        return result;
    }

    pub fn deinit(self: *ParameterizedMIMEHeader, allocator: std.mem.Allocator) void {
        self.params.deinit(allocator);
    }
};

/// Unique parameterized MIME header
/// CPython: class UniqueParameterizedMIMEHeader(ParameterizedMIMEHeader)
pub const UniqueParameterizedMIMEHeader = ParameterizedMIMEHeader;

/// Content-Type header
/// CPython: class ContentTypeHeader(ParameterizedMIMEHeader)
pub const ContentTypeHeader = struct {
    name: []const u8,
    value: []const u8,
    content_type: []const u8,
    maintype: []const u8,
    subtype: []const u8,
    params: std.ArrayList(ParameterizedMIMEHeader.Param),

    pub fn parse(allocator: std.mem.Allocator, value: []const u8) !ContentTypeHeader {
        var result = ContentTypeHeader{
            .name = "Content-Type",
            .value = value,
            .content_type = "",
            .maintype = "",
            .subtype = "",
            .params = .{},
        };

        // Parse content type
        var parts = std.mem.splitScalar(u8, value, ';');
        if (parts.next()) |ct| {
            result.content_type = std.mem.trim(u8, ct, " \t");
            if (std.mem.indexOf(u8, result.content_type, "/")) |slash| {
                result.maintype = result.content_type[0..slash];
                result.subtype = result.content_type[slash + 1 ..];
            }
        }

        // Parse parameters
        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");
            if (std.mem.indexOf(u8, trimmed, "=")) |eq| {
                const param_name = std.mem.trim(u8, trimmed[0..eq], " \t");
                var param_value = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
                if (param_value.len >= 2 and param_value[0] == '"' and param_value[param_value.len - 1] == '"') {
                    param_value = param_value[1 .. param_value.len - 1];
                }
                try result.params.append(allocator, .{ .name = param_name, .value = param_value });
            }
        }

        return result;
    }

    pub fn deinit(self: *ContentTypeHeader, allocator: std.mem.Allocator) void {
        self.params.deinit(allocator);
    }
};

/// Unique Content-Type header
/// CPython: class UniqueContentTypeHeader(ContentTypeHeader)
pub const UniqueContentTypeHeader = ContentTypeHeader;

/// Content-Disposition header
/// CPython: class ContentDispositionHeader(ParameterizedMIMEHeader)
pub const ContentDispositionHeader = ParameterizedMIMEHeader;

/// Unique Content-Disposition header
/// CPython: class UniqueContentDispositionHeader(ContentDispositionHeader)
pub const UniqueContentDispositionHeader = ContentDispositionHeader;

/// Content-Transfer-Encoding header
/// CPython: class ContentTransferEncodingHeader(BaseHeader)
pub const ContentTransferEncodingHeader = struct {
    name: []const u8,
    value: []const u8,
    cte: []const u8,

    pub fn parse(value: []const u8) ContentTransferEncodingHeader {
        return .{
            .name = "Content-Transfer-Encoding",
            .value = value,
            .cte = std.mem.trim(u8, value, " \t"),
        };
    }
};

/// Unique Content-Transfer-Encoding header
/// CPython: class UniqueContentTransferEncodingHeader(ContentTransferEncodingHeader)
pub const UniqueContentTransferEncodingHeader = ContentTransferEncodingHeader;

/// MIME-Version header
/// CPython: class MIMEVersionHeader(BaseHeader)
pub const MIMEVersionHeader = struct {
    name: []const u8,
    value: []const u8,
    major: ?u8,
    minor: ?u8,

    pub fn parse(value: []const u8) MIMEVersionHeader {
        var result = MIMEVersionHeader{
            .name = "MIME-Version",
            .value = value,
            .major = null,
            .minor = null,
        };

        const trimmed = std.mem.trim(u8, value, " \t");
        if (std.mem.indexOf(u8, trimmed, ".")) |dot| {
            result.major = std.fmt.parseInt(u8, trimmed[0..dot], 10) catch null;
            result.minor = std.fmt.parseInt(u8, trimmed[dot + 1 ..], 10) catch null;
        }

        return result;
    }
};

/// Unique MIME-Version header
/// CPython: class UniqueMIMEVersionHeader(MIMEVersionHeader)
pub const UniqueMIMEVersionHeader = MIMEVersionHeader;

// ============================================================================
// Header Registry
// ============================================================================

/// Header registry for creating structured headers
/// CPython: class HeaderRegistry
pub const HeaderRegistry = struct {
    const Self = @This();
    const HeaderFactory = *const fn ([]const u8, []const u8) anyerror!BaseHeader;

    base_class: type = BaseHeader,
    default_class: type = UnstructuredHeader,
    use_default_map: bool = true,

    /// Get header class for a header name
    pub fn getHeaderClass(name: []const u8) type {
        const lower = std.ascii.lowerString(256, name) catch name;
        if (std.mem.eql(u8, lower, "date")) return DateHeader;
        if (std.mem.eql(u8, lower, "from")) return AddressHeader;
        if (std.mem.eql(u8, lower, "to")) return AddressHeader;
        if (std.mem.eql(u8, lower, "cc")) return AddressHeader;
        if (std.mem.eql(u8, lower, "bcc")) return AddressHeader;
        if (std.mem.eql(u8, lower, "reply-to")) return AddressHeader;
        if (std.mem.eql(u8, lower, "sender")) return SingleAddressHeader;
        if (std.mem.eql(u8, lower, "resent-from")) return AddressHeader;
        if (std.mem.eql(u8, lower, "resent-to")) return AddressHeader;
        if (std.mem.eql(u8, lower, "content-type")) return ContentTypeHeader;
        if (std.mem.eql(u8, lower, "content-disposition")) return ContentDispositionHeader;
        if (std.mem.eql(u8, lower, "content-transfer-encoding")) return ContentTransferEncodingHeader;
        if (std.mem.eql(u8, lower, "mime-version")) return MIMEVersionHeader;
        return UnstructuredHeader;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Address" {
    const addr = Address.init("John Doe", "john", "example.com");
    try std.testing.expectEqualStrings("John Doe", addr.display_name);
    try std.testing.expectEqualStrings("john", addr.username);
    try std.testing.expectEqualStrings("example.com", addr.domain);
}

test "Address format" {
    const allocator = std.testing.allocator;
    const addr = Address.init("John Doe", "john", "example.com");
    const formatted = try addr.format(allocator);
    defer allocator.free(formatted);
    try std.testing.expectEqualStrings("\"John Doe\" <john@example.com>", formatted);
}

test "ContentTypeHeader parse" {
    const allocator = std.testing.allocator;
    var ct = try ContentTypeHeader.parse(allocator, "text/html; charset=\"utf-8\"");
    defer ct.deinit(allocator);

    try std.testing.expectEqualStrings("text/html", ct.content_type);
    try std.testing.expectEqualStrings("text", ct.maintype);
    try std.testing.expectEqualStrings("html", ct.subtype);
    try std.testing.expectEqual(@as(usize, 1), ct.params.items.len);
    try std.testing.expectEqualStrings("charset", ct.params.items[0].name);
    try std.testing.expectEqualStrings("utf-8", ct.params.items[0].value);
}
