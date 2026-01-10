//! test.test_future_stmt.test_unicode - Tests for `from __future__ import unicode_literals`
//!
//! PEP 3112 made all string literals Unicode by default in Python 3.
//! In Python 2, `"string"` was a byte string and `u"string"` was Unicode.
//! With this future import (or Python 3), all string literals are Unicode.
//!
//! This module tests Unicode string handling and encoding/decoding.
//!
//! CPython Reference: https://docs.python.org/3/library/__future__.html
//! PEP 3112: https://peps.python.org/pep-3112/

const std = @import("std");
const testing = std.testing;
const unicode = std.unicode;

// ============================================================================
// Unicode String Types
// ============================================================================

/// Represents a Unicode string (Python str in Python 3)
pub const UnicodeString = struct {
    /// The underlying UTF-8 encoded bytes
    data: []const u8,
    /// Cached codepoint count (lazy evaluated)
    codepoint_count: ?usize = null,

    const Self = @This();

    /// Create a new Unicode string from UTF-8 bytes
    pub fn init(data: []const u8) Self {
        return .{ .data = data };
    }

    /// Get the length in bytes
    pub fn byteLen(self: Self) usize {
        return self.data.len;
    }

    /// Get the length in Unicode codepoints
    pub fn len(self: *Self) usize {
        if (self.codepoint_count) |cached| {
            return cached;
        }
        var cnt: usize = 0;
        var view = unicode.Utf8View.initUnchecked(self.data);
        var it = view.iterator();
        while (it.nextCodepoint()) |_| {
            cnt += 1;
        }
        self.codepoint_count = cnt;
        return cnt;
    }

    /// Check if the string is empty
    pub fn isEmpty(self: Self) bool {
        return self.data.len == 0;
    }

    /// Check if the string is ASCII-only
    pub fn isAscii(self: Self) bool {
        for (self.data) |byte| {
            if (byte > 127) return false;
        }
        return true;
    }

    /// Get a specific codepoint by index
    pub fn at(self: Self, index: usize) ?u21 {
        var view = unicode.Utf8View.initUnchecked(self.data);
        var it = view.iterator();
        var i: usize = 0;
        while (it.nextCodepoint()) |cp| : (i += 1) {
            if (i == index) return cp;
        }
        return null;
    }

    /// Check if string starts with prefix
    pub fn startsWith(self: Self, prefix: []const u8) bool {
        return std.mem.startsWith(u8, self.data, prefix);
    }

    /// Check if string ends with suffix
    pub fn endsWith(self: Self, suffix: []const u8) bool {
        return std.mem.endsWith(u8, self.data, suffix);
    }

    /// Get string representation
    pub fn str(self: Self) []const u8 {
        return self.data;
    }
};

/// Represents a byte string (Python bytes in Python 3, str in Python 2)
pub const ByteString = struct {
    data: []const u8,

    const Self = @This();

    pub fn init(data: []const u8) Self {
        return .{ .data = data };
    }

    pub fn len(self: Self) usize {
        return self.data.len;
    }

    pub fn at(self: Self, index: usize) ?u8 {
        if (index >= self.data.len) return null;
        return self.data[index];
    }

    /// Decode bytes to Unicode string with given encoding
    pub fn decode(self: Self, encoding: Encoding) !UnicodeString {
        // For UTF-8, the data is already valid
        if (encoding == .utf8) {
            // Validate UTF-8
            if (!unicode.utf8ValidateSlice(self.data)) {
                return error.InvalidUtf8;
            }
            return UnicodeString.init(self.data);
        }
        // Other encodings would need conversion
        return error.UnsupportedEncoding;
    }
};

// ============================================================================
// Encoding Types
// ============================================================================

/// Supported text encodings
pub const Encoding = enum {
    utf8,
    ascii,
    latin1,
    utf16_le,
    utf16_be,
    utf32_le,
    utf32_be,

    /// Get the canonical name of the encoding
    pub fn name(self: Encoding) []const u8 {
        return switch (self) {
            .utf8 => "utf-8",
            .ascii => "ascii",
            .latin1 => "latin-1",
            .utf16_le => "utf-16-le",
            .utf16_be => "utf-16-be",
            .utf32_le => "utf-32-le",
            .utf32_be => "utf-32-be",
        };
    }

    /// Check if encoding is variable-width
    pub fn isVariableWidth(self: Encoding) bool {
        return switch (self) {
            .utf8, .utf16_le, .utf16_be => true,
            else => false,
        };
    }

    /// Parse encoding name to enum
    pub fn fromName(encoding_name: []const u8) ?Encoding {
        // Simple matching for common names (case-sensitive for simplicity)
        if (std.mem.eql(u8, encoding_name, "utf-8") or std.mem.eql(u8, encoding_name, "utf8")) {
            return .utf8;
        } else if (std.mem.eql(u8, encoding_name, "ascii")) {
            return .ascii;
        } else if (std.mem.eql(u8, encoding_name, "latin-1") or std.mem.eql(u8, encoding_name, "latin1")) {
            return .latin1;
        }
        return null;
    }
};

// ============================================================================
// Unicode Normalization
// ============================================================================

/// Unicode normalization forms (NFC, NFD, NFKC, NFKD)
pub const NormalizationForm = enum {
    NFC, // Canonical Decomposition, followed by Canonical Composition
    NFD, // Canonical Decomposition
    NFKC, // Compatibility Decomposition, followed by Canonical Composition
    NFKD, // Compatibility Decomposition

    pub fn name(self: NormalizationForm) []const u8 {
        return switch (self) {
            .NFC => "NFC",
            .NFD => "NFD",
            .NFKC => "NFKC",
            .NFKD => "NFKD",
        };
    }
};

/// Check if a string is in a given normalization form
/// (Simplified - actual implementation would need Unicode tables)
pub fn isNormalized(_: NormalizationForm, _: []const u8) bool {
    // Simplified: assume already normalized
    return true;
}

// ============================================================================
// Unicode Categories
// ============================================================================

/// Unicode general category
pub const Category = enum {
    Lu, // Letter, uppercase
    Ll, // Letter, lowercase
    Lt, // Letter, titlecase
    Lm, // Letter, modifier
    Lo, // Letter, other
    Mn, // Mark, nonspacing
    Mc, // Mark, spacing combining
    Me, // Mark, enclosing
    Nd, // Number, decimal digit
    Nl, // Number, letter
    No, // Number, other
    Pc, // Punctuation, connector
    Pd, // Punctuation, dash
    Ps, // Punctuation, open
    Pe, // Punctuation, close
    Pi, // Punctuation, initial quote
    Pf, // Punctuation, final quote
    Po, // Punctuation, other
    Sm, // Symbol, math
    Sc, // Symbol, currency
    Sk, // Symbol, modifier
    So, // Symbol, other
    Zs, // Separator, space
    Zl, // Separator, line
    Zp, // Separator, paragraph
    Cc, // Other, control
    Cf, // Other, format
    Cs, // Other, surrogate
    Co, // Other, private use
    Cn, // Other, not assigned

    pub fn isLetter(self: Category) bool {
        return switch (self) {
            .Lu, .Ll, .Lt, .Lm, .Lo => true,
            else => false,
        };
    }

    pub fn isNumber(self: Category) bool {
        return switch (self) {
            .Nd, .Nl, .No => true,
            else => false,
        };
    }

    pub fn isPunctuation(self: Category) bool {
        return switch (self) {
            .Pc, .Pd, .Ps, .Pe, .Pi, .Pf, .Po => true,
            else => false,
        };
    }
};

/// Get the category of a codepoint (simplified)
pub fn getCategory(codepoint: u21) Category {
    if (codepoint <= 0x1F or (codepoint >= 0x7F and codepoint <= 0x9F)) {
        return .Cc; // Control
    }
    if (codepoint >= '0' and codepoint <= '9') {
        return .Nd; // Decimal digit
    }
    if (codepoint >= 'A' and codepoint <= 'Z') {
        return .Lu; // Uppercase letter
    }
    if (codepoint >= 'a' and codepoint <= 'z') {
        return .Ll; // Lowercase letter
    }
    if (codepoint == ' ') {
        return .Zs; // Space separator
    }
    return .Lo; // Letter, other (default for unknown)
}

// ============================================================================
// String Encoding/Decoding
// ============================================================================

/// Encode a Unicode string to bytes
pub fn encode(allocator: std.mem.Allocator, str: UnicodeString, encoding: Encoding) ![]u8 {
    switch (encoding) {
        .utf8 => {
            // Already UTF-8, just copy
            return try allocator.dupe(u8, str.data);
        },
        .ascii => {
            // Check all bytes are ASCII
            for (str.data) |byte| {
                if (byte > 127) return error.UnicodeEncodeError;
            }
            return try allocator.dupe(u8, str.data);
        },
        .latin1 => {
            // Latin-1 can represent codepoints 0-255
            var result: std.ArrayListUnmanaged(u8) = .{};
            var view = unicode.Utf8View.initUnchecked(str.data);
            var it = view.iterator();
            while (it.nextCodepoint()) |cp| {
                if (cp > 255) return error.UnicodeEncodeError;
                try result.append(allocator, @intCast(cp));
            }
            return try result.toOwnedSlice(allocator);
        },
        else => return error.UnsupportedEncoding,
    }
}

/// Decode bytes to a Unicode string
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8, encoding: Encoding) ![]u8 {
    switch (encoding) {
        .utf8 => {
            if (!unicode.utf8ValidateSlice(bytes)) {
                return error.UnicodeDecodeError;
            }
            return try allocator.dupe(u8, bytes);
        },
        .ascii => {
            for (bytes) |byte| {
                if (byte > 127) return error.UnicodeDecodeError;
            }
            return try allocator.dupe(u8, bytes);
        },
        .latin1 => {
            // Latin-1 bytes map directly to codepoints
            var result: std.ArrayListUnmanaged(u8) = .{};
            for (bytes) |byte| {
                if (byte < 128) {
                    try result.append(allocator, byte);
                } else {
                    // Encode as UTF-8 (2 bytes for 128-255)
                    try result.append(allocator, 0xC0 | (byte >> 6));
                    try result.append(allocator, 0x80 | (byte & 0x3F));
                }
            }
            return try result.toOwnedSlice(allocator);
        },
        else => return error.UnsupportedEncoding,
    }
}

// ============================================================================
// Unicode Escape Handling
// ============================================================================

/// Parse a Unicode escape sequence (e.g., \u0041, \U00000041)
pub fn parseUnicodeEscape(escape: []const u8) !u21 {
    if (escape.len < 2) return error.InvalidEscape;

    if (escape[0] != '\\') return error.InvalidEscape;

    switch (escape[1]) {
        'u' => {
            // \uXXXX - 4 hex digits
            if (escape.len < 6) return error.InvalidEscape;
            const value = std.fmt.parseInt(u21, escape[2..6], 16) catch return error.InvalidEscape;
            return value;
        },
        'U' => {
            // \UXXXXXXXX - 8 hex digits
            if (escape.len < 10) return error.InvalidEscape;
            const value = std.fmt.parseInt(u21, escape[2..10], 16) catch return error.InvalidEscape;
            if (value > 0x10FFFF) return error.InvalidCodepoint;
            return value;
        },
        'x' => {
            // \xXX - 2 hex digits
            if (escape.len < 4) return error.InvalidEscape;
            const value = std.fmt.parseInt(u21, escape[2..4], 16) catch return error.InvalidEscape;
            return value;
        },
        'N' => {
            // \N{name} - Named character (not implemented)
            return error.UnsupportedEscape;
        },
        else => return error.InvalidEscape,
    }
}

/// Format a codepoint as a Unicode escape
pub fn formatUnicodeEscape(allocator: std.mem.Allocator, codepoint: u21) ![]u8 {
    if (codepoint <= 0xFFFF) {
        return try std.fmt.allocPrint(allocator, "\\u{X:0>4}", .{codepoint});
    } else {
        return try std.fmt.allocPrint(allocator, "\\U{X:0>8}", .{codepoint});
    }
}

// ============================================================================
// String Case Operations
// ============================================================================

/// Convert ASCII to uppercase
pub fn toUpper(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    var result = try allocator.alloc(u8, str.len);
    for (str, 0..) |c, i| {
        result[i] = std.ascii.toUpper(c);
    }
    return result;
}

/// Convert ASCII to lowercase
pub fn toLower(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    var result = try allocator.alloc(u8, str.len);
    for (str, 0..) |c, i| {
        result[i] = std.ascii.toLower(c);
    }
    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "unicode_string_basic" {
    var ustr = UnicodeString.init("hello");
    try testing.expectEqual(@as(usize, 5), ustr.byteLen());
    try testing.expectEqual(@as(usize, 5), ustr.len());
}

test "unicode_string_multibyte" {
    // "caf\u00e9" - café in UTF-8
    var ustr = UnicodeString.init("caf\xc3\xa9");
    try testing.expectEqual(@as(usize, 5), ustr.byteLen());
    try testing.expectEqual(@as(usize, 4), ustr.len());
}

test "unicode_string_is_ascii" {
    const ascii = UnicodeString.init("hello");
    const non_ascii = UnicodeString.init("caf\xc3\xa9");

    try testing.expect(ascii.isAscii());
    try testing.expect(!non_ascii.isAscii());
}

test "unicode_string_at" {
    const ustr = UnicodeString.init("abc");
    try testing.expectEqual(@as(u21, 'a'), ustr.at(0).?);
    try testing.expectEqual(@as(u21, 'b'), ustr.at(1).?);
    try testing.expectEqual(@as(u21, 'c'), ustr.at(2).?);
    try testing.expect(ustr.at(3) == null);
}

test "unicode_string_starts_ends_with" {
    const ustr = UnicodeString.init("hello world");
    try testing.expect(ustr.startsWith("hello"));
    try testing.expect(!ustr.startsWith("world"));
    try testing.expect(ustr.endsWith("world"));
    try testing.expect(!ustr.endsWith("hello"));
}

test "byte_string_basic" {
    const bstr = ByteString.init("hello");
    try testing.expectEqual(@as(usize, 5), bstr.len());
    try testing.expectEqual(@as(u8, 'h'), bstr.at(0).?);
}

test "byte_string_decode_utf8" {
    const bstr = ByteString.init("hello");
    const ustr = try bstr.decode(.utf8);
    try testing.expectEqualStrings("hello", ustr.data);
}

test "encoding_names" {
    try testing.expectEqualStrings("utf-8", Encoding.utf8.name());
    try testing.expectEqualStrings("ascii", Encoding.ascii.name());
    try testing.expectEqualStrings("latin-1", Encoding.latin1.name());
}

test "encoding_from_name" {
    try testing.expectEqual(Encoding.utf8, Encoding.fromName("utf-8").?);
    try testing.expectEqual(Encoding.utf8, Encoding.fromName("utf8").?);
    try testing.expectEqual(Encoding.ascii, Encoding.fromName("ascii").?);
    try testing.expect(Encoding.fromName("unknown") == null);
}

test "encoding_variable_width" {
    try testing.expect(Encoding.utf8.isVariableWidth());
    try testing.expect(Encoding.utf16_le.isVariableWidth());
    try testing.expect(!Encoding.ascii.isVariableWidth());
    try testing.expect(!Encoding.latin1.isVariableWidth());
}

test "category_classification" {
    try testing.expect(getCategory('A') == .Lu);
    try testing.expect(getCategory('a') == .Ll);
    try testing.expect(getCategory('5') == .Nd);
    try testing.expect(getCategory(' ') == .Zs);
    try testing.expect(getCategory(0x00) == .Cc);
}

test "category_is_letter" {
    try testing.expect(Category.Lu.isLetter());
    try testing.expect(Category.Ll.isLetter());
    try testing.expect(!Category.Nd.isLetter());
}

test "category_is_number" {
    try testing.expect(Category.Nd.isNumber());
    try testing.expect(!Category.Lu.isNumber());
}

test "encode_utf8" {
    const ustr = UnicodeString.init("hello");
    const encoded = try encode(testing.allocator, ustr, .utf8);
    defer testing.allocator.free(encoded);
    try testing.expectEqualStrings("hello", encoded);
}

test "encode_ascii_error" {
    const ustr = UnicodeString.init("caf\xc3\xa9"); // café
    try testing.expectError(error.UnicodeEncodeError, encode(testing.allocator, ustr, .ascii));
}

test "parse_unicode_escape_u" {
    const result = try parseUnicodeEscape("\\u0041");
    try testing.expectEqual(@as(u21, 'A'), result);
}

test "parse_unicode_escape_U" {
    const result = try parseUnicodeEscape("\\U00000041");
    try testing.expectEqual(@as(u21, 'A'), result);
}

test "parse_unicode_escape_x" {
    const result = try parseUnicodeEscape("\\x41");
    try testing.expectEqual(@as(u21, 'A'), result);
}

test "format_unicode_escape" {
    const result = try formatUnicodeEscape(testing.allocator, 'A');
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("\\u0041", result);
}

test "format_unicode_escape_supplementary" {
    const result = try formatUnicodeEscape(testing.allocator, 0x1F600); // Emoji
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("\\U0001F600", result);
}

test "to_upper" {
    const result = try toUpper(testing.allocator, "hello");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("HELLO", result);
}

test "to_lower" {
    const result = try toLower(testing.allocator, "HELLO");
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("hello", result);
}

test "normalization_form_names" {
    try testing.expectEqualStrings("NFC", NormalizationForm.NFC.name());
    try testing.expectEqualStrings("NFD", NormalizationForm.NFD.name());
    try testing.expectEqualStrings("NFKC", NormalizationForm.NFKC.name());
    try testing.expectEqualStrings("NFKD", NormalizationForm.NFKD.name());
}

test "unicode_string_empty" {
    var ustr = UnicodeString.init("");
    try testing.expect(ustr.isEmpty());
    try testing.expectEqual(@as(usize, 0), ustr.len());
}
