//! Footer parsing tests.
//!
//! These tests validate the Lance file footer parsing against known values.

const std = @import("std");
const format = @import("lanceql.format");

const Footer = format.Footer;
const Version = format.Version;
const LANCE_MAGIC = format.LANCE_MAGIC;
const FOOTER_SIZE = format.FOOTER_SIZE;

/// Create a valid footer with the given parameters.
fn createFooter(
    column_meta_start: u64,
    column_meta_offsets_start: u64,
    global_buff_offsets_start: u64,
    num_global_buffers: u32,
    num_columns: u32,
    major_version: u16,
    minor_version: u16,
) [FOOTER_SIZE]u8 {
    var data: [FOOTER_SIZE]u8 = undefined;

    std.mem.writeInt(u64, data[0..8], column_meta_start, .little);
    std.mem.writeInt(u64, data[8..16], column_meta_offsets_start, .little);
    std.mem.writeInt(u64, data[16..24], global_buff_offsets_start, .little);
    std.mem.writeInt(u32, data[24..28], num_global_buffers, .little);
    std.mem.writeInt(u32, data[28..32], num_columns, .little);
    std.mem.writeInt(u16, data[32..34], major_version, .little);
    std.mem.writeInt(u16, data[34..36], minor_version, .little);
    @memcpy(data[36..40], LANCE_MAGIC);

    return data;
}

test "parse v2_0 footer" {
    const data = createFooter(
        1000, // column_meta_start
        2000, // column_meta_offsets_start
        3000, // global_buff_offsets_start
        5, // num_global_buffers
        10, // num_columns
        0, // major_version (V2_0)
        3, // minor_version (V2_0)
    );

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

test "parse v2_1 footer" {
    const data = createFooter(
        5000, // column_meta_start
        6000, // column_meta_offsets_start
        7000, // global_buff_offsets_start
        2, // num_global_buffers
        25, // num_columns
        2, // major_version (V2_1)
        1, // minor_version (V2_1)
    );

    const footer = try Footer.parse(&data);

    try std.testing.expectEqual(@as(u64, 5000), footer.column_meta_start);
    try std.testing.expectEqual(@as(u32, 25), footer.num_columns);
    try std.testing.expectEqual(Version.v2_1, footer.getVersion());
    try std.testing.expect(footer.isSupported());
}

test "parse footer with zero columns" {
    const data = createFooter(0, 0, 0, 0, 0, 0, 3);

    const footer = try Footer.parse(&data);

    try std.testing.expectEqual(@as(u32, 0), footer.num_columns);
    try std.testing.expectEqual(@as(u32, 0), footer.num_global_buffers);
}

test "parse footer with max values" {
    const data = createFooter(
        std.math.maxInt(u64),
        std.math.maxInt(u64),
        std.math.maxInt(u64),
        std.math.maxInt(u32),
        std.math.maxInt(u32),
        std.math.maxInt(u16),
        std.math.maxInt(u16),
    );

    const footer = try Footer.parse(&data);

    try std.testing.expectEqual(std.math.maxInt(u64), footer.column_meta_start);
    try std.testing.expectEqual(std.math.maxInt(u32), footer.num_columns);
    try std.testing.expectEqual(Version.unknown, footer.getVersion());
    try std.testing.expect(!footer.isSupported());
}

test "invalid magic bytes" {
    var data = createFooter(0, 0, 0, 0, 0, 0, 3);
    @memcpy(data[36..40], "NOPE");

    const result = Footer.parse(&data);
    try std.testing.expectError(format.footer.FooterError.InvalidMagic, result);
}

test "column meta size calculation" {
    const data = createFooter(
        1000, // column_meta_start
        1500, // column_meta_offsets_start
        2000, // global_buff_offsets_start
        0,
        5,
        0,
        3,
    );

    const footer = try Footer.parse(&data);

    try std.testing.expectEqual(@as(u64, 500), footer.columnMetaSize());
}

test "parseSlice with extra data before footer" {
    // Create a larger buffer with footer at the end
    var buffer: [100]u8 = undefined;
    @memset(&buffer, 0xAB); // Fill with garbage

    // Put footer at the end
    const footer_data = createFooter(500, 600, 700, 1, 3, 0, 3);
    @memcpy(buffer[60..100], &footer_data);

    const footer = try Footer.parseSlice(&buffer);

    try std.testing.expectEqual(@as(u64, 500), footer.column_meta_start);
    try std.testing.expectEqual(@as(u32, 3), footer.num_columns);
}

test "parseSlice with buffer too small" {
    var buffer: [20]u8 = undefined;

    const result = Footer.parseSlice(&buffer);
    try std.testing.expectError(format.footer.FooterError.BufferTooSmall, result);
}

test "version string conversion" {
    try std.testing.expectEqualStrings("2.0", Version.v2_0.toString());
    try std.testing.expectEqualStrings("2.1", Version.v2_1.toString());
    try std.testing.expectEqualStrings("unknown", Version.unknown.toString());
}
