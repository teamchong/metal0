/// codecs/encodings - Known Encodings and Canonical Names
/// Lists of known encodings and alias resolution

const std = @import("std");
const normalization = @import("normalization.zig");

// ============================================================================
// Known Encodings
// ============================================================================

/// Check if an encoding is a known text encoding
pub fn isKnownTextEncoding(encoding: []const u8) bool {
    var buf: [256]u8 = undefined;
    const normalized = normalization.normalizeEncoding(&buf, encoding);

    const known = [_][]const u8{
        "utf-8",
        "utf-16",
        "utf-16-le",
        "utf-16-be",
        "utf-32",
        "utf-32-le",
        "utf-32-be",
        "ascii",
        "latin-1",
        "iso-8859-1",
        "cp1252",
        "utf-7",
    };

    for (known) |enc| {
        if (std.mem.eql(u8, normalized, enc)) {
            return true;
        }
    }
    return false;
}

/// Get the canonical name for an encoding alias
pub fn getCanonicalName(encoding: []const u8) []const u8 {
    var buf: [256]u8 = undefined;
    const normalized = normalization.normalizeEncoding(&buf, encoding);

    // Common aliases
    if (std.mem.eql(u8, normalized, "utf8") or
        std.mem.eql(u8, normalized, "utf-8"))
    {
        return "utf-8";
    }

    if (std.mem.eql(u8, normalized, "latin1") or
        std.mem.eql(u8, normalized, "latin-1") or
        std.mem.eql(u8, normalized, "iso-8859-1") or
        std.mem.eql(u8, normalized, "iso8859-1"))
    {
        return "iso-8859-1";
    }

    if (std.mem.eql(u8, normalized, "ascii") or
        std.mem.eql(u8, normalized, "us-ascii"))
    {
        return "ascii";
    }

    return encoding;
}

// ============================================================================
// Tests
// ============================================================================

test "known encodings" {
    try std.testing.expect(isKnownTextEncoding("utf-8"));
    try std.testing.expect(isKnownTextEncoding("UTF-8"));
    try std.testing.expect(isKnownTextEncoding("ascii"));
    try std.testing.expect(!isKnownTextEncoding("unknown-encoding"));
}

test "canonical names" {
    try std.testing.expectEqualStrings("utf-8", getCanonicalName("utf8"));
    try std.testing.expectEqualStrings("utf-8", getCanonicalName("UTF-8"));
    try std.testing.expectEqualStrings("iso-8859-1", getCanonicalName("latin1"));
    try std.testing.expectEqualStrings("ascii", getCanonicalName("us-ascii"));
}
