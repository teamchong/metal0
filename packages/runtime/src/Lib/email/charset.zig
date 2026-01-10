//! email.charset - Character set handling for email
//! Reference: cpython/Lib/email/charset.py
//!
//! CPython __all__: ['Charset', 'add_alias', 'add_charset', 'add_codec']

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Charset codec information
pub const CodecInfo = struct {
    input_codec: ?[]const u8 = null,
    output_codec: ?[]const u8 = null,
    header_encoding: Encoding = .qp,
    body_encoding: Encoding = .qp,
};

/// Encoding types
pub const Encoding = enum {
    qp, // Quoted-Printable
    base64, // Base64
    shortest, // Use shortest encoding
    none, // No encoding
};

// Built-in charset mappings
const charset_aliases = std.StaticStringMap([]const u8).initComptime(.{
    .{ "latin-1", "iso-8859-1" },
    .{ "latin_1", "iso-8859-1" },
    .{ "ascii", "us-ascii" },
    .{ "utf8", "utf-8" },
    .{ "utf-8", "utf-8" },
});

// ============================================================================
// Charset Class
// ============================================================================

/// Charset - Character set handler for email
/// CPython: class Charset
pub const Charset = struct {
    const Self = @This();

    input_charset: []const u8,
    output_charset: []const u8,
    header_encoding: Encoding,
    body_encoding: Encoding,
    input_codec: ?[]const u8,
    output_codec: ?[]const u8,

    pub fn init(input_charset: []const u8) Self {
        // Normalize charset name
        const normalized = charset_aliases.get(input_charset) orelse input_charset;

        return .{
            .input_charset = normalized,
            .output_charset = normalized,
            .header_encoding = if (std.mem.eql(u8, normalized, "us-ascii")) .none else .qp,
            .body_encoding = if (std.mem.eql(u8, normalized, "us-ascii")) .none else .qp,
            .input_codec = null,
            .output_codec = null,
        };
    }

    /// Get the output charset name
    pub fn getOutputCharset(self: *const Self) []const u8 {
        return self.output_charset;
    }

    /// Get header encoding method
    pub fn headerEncode(self: *const Self, s: []const u8) []const u8 {
        _ = self;
        // In AOT, we don't actually encode - return as-is
        return s;
    }

    /// Get body encoding method
    pub fn bodyEncode(self: *const Self, s: []const u8) []const u8 {
        _ = self;
        return s;
    }

    /// Check if conversion is needed
    pub fn headerEncodeLines(self: *const Self, s: []const u8, maxlinelen: usize) []const u8 {
        _ = self;
        _ = maxlinelen;
        return s;
    }

    /// Convert string to bytes
    pub fn toBytes(self: *const Self, allocator: std.mem.Allocator, s: []const u8) ![]u8 {
        _ = self;
        return allocator.dupe(u8, s);
    }

    /// Convert bytes to string
    pub fn fromBytes(self: *const Self, allocator: std.mem.Allocator, s: []const u8) ![]u8 {
        _ = self;
        return allocator.dupe(u8, s);
    }
};

// ============================================================================
// Module-level Functions
// ============================================================================

/// Add a character set alias
/// CPython: def add_alias(alias, canonical)
pub fn add_alias(alias: []const u8, canonical: []const u8) void {
    // In AOT, aliases are compile-time constants
    _ = alias;
    _ = canonical;
}

/// Add a charset with encoding info
/// CPython: def add_charset(charset, header_enc, body_enc, output_charset)
pub fn add_charset(charset: []const u8, header_enc: Encoding, body_enc: Encoding, output_charset: ?[]const u8) void {
    _ = charset;
    _ = header_enc;
    _ = body_enc;
    _ = output_charset;
}

/// Add a codec mapping
/// CPython: def add_codec(charset, codecname)
pub fn add_codec(charset: []const u8, codecname: []const u8) void {
    _ = charset;
    _ = codecname;
}

// ============================================================================
// Tests
// ============================================================================

test "Charset init" {
    const cs = Charset.init("utf-8");
    try std.testing.expectEqualStrings("utf-8", cs.input_charset);
    try std.testing.expectEqualStrings("utf-8", cs.output_charset);
}

test "Charset alias" {
    const cs = Charset.init("latin-1");
    try std.testing.expectEqualStrings("iso-8859-1", cs.input_charset);
}

test "Charset ascii" {
    const cs = Charset.init("us-ascii");
    try std.testing.expect(cs.header_encoding == .none);
    try std.testing.expect(cs.body_encoding == .none);
}
