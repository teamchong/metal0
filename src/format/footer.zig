//! Lance file footer parsing.
//!
//! The footer is a fixed 40-byte structure at the end of every Lance file.
//! It contains offsets to all metadata sections and format version information.
//!
//! ## Footer Layout (Little Endian)
//! | Offset | Size | Field                      |
//! |--------|------|----------------------------|
//! | 0      | 8    | column_meta_start          |
//! | 8      | 8    | column_meta_offsets_start  |
//! | 16     | 8    | global_buff_offsets_start  |
//! | 24     | 4    | num_global_buffers         |
//! | 28     | 4    | num_columns                |
//! | 32     | 2    | major_version              |
//! | 34     | 2    | minor_version              |
//! | 36     | 4    | magic ("LANC")             |

const std = @import("std");
const version_mod = @import("version.zig");

pub const Version = version_mod.Version;

/// Magic bytes identifying a Lance file
pub const LANCE_MAGIC = "LANC";

/// Size of the footer in bytes
pub const FOOTER_SIZE: usize = 40;

/// Errors that can occur when parsing a Lance footer
pub const FooterError = error{
    /// The magic bytes at the end of the footer are not "LANC"
    InvalidMagic,
    /// The buffer provided is smaller than FOOTER_SIZE
    BufferTooSmall,
    /// The file is smaller than the footer size
    FileTooSmall,
};

/// Lance file footer containing metadata offsets and version information.
pub const Footer = struct {
    /// Byte offset to the start of column metadata section
    column_meta_start: u64,
    /// Byte offset to the column metadata offset table
    column_meta_offsets_start: u64,
    /// Byte offset to the global buffers offset table
    global_buff_offsets_start: u64,
    /// Number of global buffers in the file
    num_global_buffers: u32,
    /// Number of columns in the file
    num_columns: u32,
    /// Format major version number
    major_version: u16,
    /// Format minor version number
    minor_version: u16,

    /// Parse a footer from a 40-byte buffer.
    ///
    /// The buffer must be exactly FOOTER_SIZE (40) bytes and contain valid
    /// Lance footer data including the "LANC" magic bytes at the end.
    pub fn parse(data: *const [FOOTER_SIZE]u8) FooterError!Footer {
        // Verify magic bytes at end (bytes 36-39)
        if (!std.mem.eql(u8, data[36..40], LANCE_MAGIC)) {
            return FooterError.InvalidMagic;
        }

        return Footer{
            .column_meta_start = std.mem.readInt(u64, data[0..8], .little),
            .column_meta_offsets_start = std.mem.readInt(u64, data[8..16], .little),
            .global_buff_offsets_start = std.mem.readInt(u64, data[16..24], .little),
            .num_global_buffers = std.mem.readInt(u32, data[24..28], .little),
            .num_columns = std.mem.readInt(u32, data[28..32], .little),
            .major_version = std.mem.readInt(u16, data[32..34], .little),
            .minor_version = std.mem.readInt(u16, data[34..36], .little),
        };
    }

    /// Parse a footer from a slice (must be at least FOOTER_SIZE bytes).
    pub fn parseSlice(data: []const u8) FooterError!Footer {
        if (data.len < FOOTER_SIZE) {
            return FooterError.BufferTooSmall;
        }
        return parse(data[data.len - FOOTER_SIZE ..][0..FOOTER_SIZE]);
    }

    /// Get the format version enum from major/minor version numbers.
    pub fn getVersion(self: Footer) Version {
        return Version.fromPair(self.major_version, self.minor_version);
    }

    /// Check if this footer indicates a supported Lance version.
    pub fn isSupported(self: Footer) bool {
        return self.getVersion() != .unknown;
    }

    /// Calculate the size of the column metadata section.
    pub fn columnMetaSize(self: Footer) u64 {
        return self.column_meta_offsets_start - self.column_meta_start;
    }
};

test "parse valid footer" {
    // Construct a valid 40-byte footer
    var data: [FOOTER_SIZE]u8 = undefined;

    // column_meta_start = 1000
    std.mem.writeInt(u64, data[0..8], 1000, .little);
    // column_meta_offsets_start = 2000
    std.mem.writeInt(u64, data[8..16], 2000, .little);
    // global_buff_offsets_start = 3000
    std.mem.writeInt(u64, data[16..24], 3000, .little);
    // num_global_buffers = 5
    std.mem.writeInt(u32, data[24..28], 5, .little);
    // num_columns = 10
    std.mem.writeInt(u32, data[28..32], 10, .little);
    // major_version = 0
    std.mem.writeInt(u16, data[32..34], 0, .little);
    // minor_version = 3 (V2_0)
    std.mem.writeInt(u16, data[34..36], 3, .little);
    // magic = "LANC"
    @memcpy(data[36..40], LANCE_MAGIC);

    const footer = try Footer.parse(&data);

    try std.testing.expectEqual(@as(u64, 1000), footer.column_meta_start);
    try std.testing.expectEqual(@as(u64, 2000), footer.column_meta_offsets_start);
    try std.testing.expectEqual(@as(u64, 3000), footer.global_buff_offsets_start);
    try std.testing.expectEqual(@as(u32, 5), footer.num_global_buffers);
    try std.testing.expectEqual(@as(u32, 10), footer.num_columns);
    try std.testing.expectEqual(@as(u16, 0), footer.major_version);
    try std.testing.expectEqual(@as(u16, 3), footer.minor_version);
    try std.testing.expectEqual(Version.v2_0, footer.getVersion());
    try std.testing.expect(footer.isSupported());
}

test "parse invalid magic" {
    var data: [FOOTER_SIZE]u8 = undefined;
    @memset(&data, 0);
    @memcpy(data[36..40], "NOPE");

    const result = Footer.parse(&data);
    try std.testing.expectError(FooterError.InvalidMagic, result);
}

test "parse v2_1 footer" {
    var data: [FOOTER_SIZE]u8 = undefined;
    @memset(&data, 0);

    // major_version = 2, minor_version = 1 (V2_1)
    std.mem.writeInt(u16, data[32..34], 2, .little);
    std.mem.writeInt(u16, data[34..36], 1, .little);
    @memcpy(data[36..40], LANCE_MAGIC);

    const footer = try Footer.parse(&data);
    try std.testing.expectEqual(Version.v2_1, footer.getVersion());
}

test "parseSlice with larger buffer" {
    var data: [100]u8 = undefined;
    @memset(&data, 0);

    // Put valid footer at the end
    std.mem.writeInt(u64, data[60..68], 500, .little); // column_meta_start
    std.mem.writeInt(u32, data[88..92], 3, .little); // num_columns
    std.mem.writeInt(u16, data[92..94], 0, .little); // major
    std.mem.writeInt(u16, data[94..96], 3, .little); // minor
    @memcpy(data[96..100], LANCE_MAGIC);

    const footer = try Footer.parseSlice(&data);
    try std.testing.expectEqual(@as(u64, 500), footer.column_meta_start);
    try std.testing.expectEqual(@as(u32, 3), footer.num_columns);
}

test "parseSlice with too small buffer" {
    var data: [20]u8 = undefined;
    const result = Footer.parseSlice(&data);
    try std.testing.expectError(FooterError.BufferTooSmall, result);
}
