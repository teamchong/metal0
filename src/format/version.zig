//! Lance format version handling.
//!
//! Lance has multiple format versions with different capabilities:
//! - V2_0 (major=0, minor=3): Legacy format with per-field columns
//! - V2_1 (major=2, minor=1): Structural encoding, mini-blocks

const std = @import("std");

/// Lance file format version.
pub const Version = enum {
    /// Lance V2.0 format (major=0, minor=3)
    /// - Each structural field gets its own column
    /// - Uses basic encodings: value, dictionary, RLE, bitpacked
    v2_0,

    /// Lance V2.1 format (major=2, minor=1)
    /// - Only leaf fields are columnar (structs/lists don't need columns)
    /// - RepDef system for nested structures
    /// - Mini-block chunking (~4KB) for random access
    /// - Multiple compression schemes per column
    v2_1,

    /// Unrecognized format version
    unknown,

    /// Convert major/minor version pair to Version enum.
    pub fn fromPair(maj: u16, min: u16) Version {
        if (maj == 0 and min == 3) return .v2_0;
        if (maj == 2 and min == 1) return .v2_1;
        return .unknown;
    }

    /// Get the major version number.
    pub fn major(self: Version) ?u16 {
        return switch (self) {
            .v2_0 => 0,
            .v2_1 => 2,
            .unknown => null,
        };
    }

    /// Get the minor version number.
    pub fn minor(self: Version) ?u16 {
        return switch (self) {
            .v2_0 => 3,
            .v2_1 => 1,
            .unknown => null,
        };
    }

    /// Get a human-readable version string.
    pub fn toString(self: Version) []const u8 {
        return switch (self) {
            .v2_0 => "2.0",
            .v2_1 => "2.1",
            .unknown => "unknown",
        };
    }
};

test "version from pair" {
    try std.testing.expectEqual(Version.v2_0, Version.fromPair(0, 3));
    try std.testing.expectEqual(Version.v2_1, Version.fromPair(2, 1));
    try std.testing.expectEqual(Version.unknown, Version.fromPair(0, 0));
    try std.testing.expectEqual(Version.unknown, Version.fromPair(99, 99));
}

test "version to string" {
    try std.testing.expectEqualStrings("2.0", Version.v2_0.toString());
    try std.testing.expectEqualStrings("2.1", Version.v2_1.toString());
    try std.testing.expectEqualStrings("unknown", Version.unknown.toString());
}

test "version major minor" {
    try std.testing.expectEqual(@as(?u16, 0), Version.v2_0.major());
    try std.testing.expectEqual(@as(?u16, 3), Version.v2_0.minor());
    try std.testing.expectEqual(@as(?u16, 2), Version.v2_1.major());
    try std.testing.expectEqual(@as(?u16, 1), Version.v2_1.minor());
    try std.testing.expectEqual(@as(?u16, null), Version.unknown.major());
}
