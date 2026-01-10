//! test.test_zipfile.test_zipfile64 - ZIP64 large file support tests
//!
//! Tests for ZIP64 format extensions that support files larger than 4GB
//! and archives with more than 65535 entries.

const std = @import("std");
const testing = std.testing;
const mem = std.mem;

// ============================================================================
// ZIP64 Constants
// ============================================================================

/// ZIP64 End of Central Directory signature
const ZIP64_END_MAGIC: [4]u8 = .{ 0x50, 0x4b, 0x06, 0x06 };

/// ZIP64 End of Central Directory Locator signature
const ZIP64_LOCATOR_MAGIC: [4]u8 = .{ 0x50, 0x4b, 0x06, 0x07 };

/// ZIP64 extra field header ID
const ZIP64_EXTRA_ID: u16 = 0x0001;

/// Maximum values that trigger ZIP64
const MAX_32BIT_VALUE: u32 = 0xFFFFFFFF;
const MAX_16BIT_VALUE: u16 = 0xFFFF;

// ============================================================================
// ZIP64 Header Structures
// ============================================================================

pub const Zip64EndOfCentralDirectory = struct {
    signature: [4]u8 = ZIP64_END_MAGIC,
    record_size: u64 = 44, // Minimum size
    version_made_by: u16 = 45,
    version_needed: u16 = 45,
    disk_number: u32 = 0,
    disk_with_cd: u32 = 0,
    entries_on_disk: u64 = 0,
    total_entries: u64 = 0,
    cd_size: u64 = 0,
    cd_offset: u64 = 0,

    pub fn encode(self: Zip64EndOfCentralDirectory, buf: []u8) void {
        @memcpy(buf[0..4], &self.signature);
        mem.writeInt(u64, buf[4..12], self.record_size, .little);
        mem.writeInt(u16, buf[12..14], self.version_made_by, .little);
        mem.writeInt(u16, buf[14..16], self.version_needed, .little);
        mem.writeInt(u32, buf[16..20], self.disk_number, .little);
        mem.writeInt(u32, buf[20..24], self.disk_with_cd, .little);
        mem.writeInt(u64, buf[24..32], self.entries_on_disk, .little);
        mem.writeInt(u64, buf[32..40], self.total_entries, .little);
        mem.writeInt(u64, buf[40..48], self.cd_size, .little);
        mem.writeInt(u64, buf[48..56], self.cd_offset, .little);
    }

    pub fn decode(data: []const u8) ?Zip64EndOfCentralDirectory {
        if (data.len < 56) return null;
        if (!mem.eql(u8, data[0..4], &ZIP64_END_MAGIC)) return null;

        return .{
            .record_size = mem.readInt(u64, data[4..12], .little),
            .version_made_by = mem.readInt(u16, data[12..14], .little),
            .version_needed = mem.readInt(u16, data[14..16], .little),
            .disk_number = mem.readInt(u32, data[16..20], .little),
            .disk_with_cd = mem.readInt(u32, data[20..24], .little),
            .entries_on_disk = mem.readInt(u64, data[24..32], .little),
            .total_entries = mem.readInt(u64, data[32..40], .little),
            .cd_size = mem.readInt(u64, data[40..48], .little),
            .cd_offset = mem.readInt(u64, data[48..56], .little),
        };
    }

    pub const ENCODED_SIZE: usize = 56;
};

pub const Zip64Locator = struct {
    signature: [4]u8 = ZIP64_LOCATOR_MAGIC,
    disk_with_zip64_eocd: u32 = 0,
    zip64_eocd_offset: u64 = 0,
    total_disks: u32 = 1,

    pub fn encode(self: Zip64Locator, buf: []u8) void {
        @memcpy(buf[0..4], &self.signature);
        mem.writeInt(u32, buf[4..8], self.disk_with_zip64_eocd, .little);
        mem.writeInt(u64, buf[8..16], self.zip64_eocd_offset, .little);
        mem.writeInt(u32, buf[16..20], self.total_disks, .little);
    }

    pub fn decode(data: []const u8) ?Zip64Locator {
        if (data.len < 20) return null;
        if (!mem.eql(u8, data[0..4], &ZIP64_LOCATOR_MAGIC)) return null;

        return .{
            .disk_with_zip64_eocd = mem.readInt(u32, data[4..8], .little),
            .zip64_eocd_offset = mem.readInt(u64, data[8..16], .little),
            .total_disks = mem.readInt(u32, data[16..20], .little),
        };
    }

    pub const ENCODED_SIZE: usize = 20;
};

// ============================================================================
// ZIP64 Extra Field
// ============================================================================

pub const Zip64ExtraField = struct {
    uncompressed_size: ?u64 = null,
    compressed_size: ?u64 = null,
    header_offset: ?u64 = null,
    disk_number: ?u32 = null,

    pub fn encode(self: Zip64ExtraField, allocator: mem.Allocator) ![]u8 {
        var size: usize = 0;
        if (self.uncompressed_size != null) size += 8;
        if (self.compressed_size != null) size += 8;
        if (self.header_offset != null) size += 8;
        if (self.disk_number != null) size += 4;

        const total_size = 4 + size; // Header + data
        var buf = try allocator.alloc(u8, total_size);

        mem.writeInt(u16, buf[0..2], ZIP64_EXTRA_ID, .little);
        mem.writeInt(u16, buf[2..4], @intCast(size), .little);

        var offset: usize = 4;
        if (self.uncompressed_size) |v| {
            mem.writeInt(u64, buf[offset..][0..8], v, .little);
            offset += 8;
        }
        if (self.compressed_size) |v| {
            mem.writeInt(u64, buf[offset..][0..8], v, .little);
            offset += 8;
        }
        if (self.header_offset) |v| {
            mem.writeInt(u64, buf[offset..][0..8], v, .little);
            offset += 8;
        }
        if (self.disk_number) |v| {
            mem.writeInt(u32, buf[offset..][0..4], v, .little);
        }

        return buf;
    }

    pub fn decode(data: []const u8) ?Zip64ExtraField {
        if (data.len < 4) return null;

        const id = mem.readInt(u16, data[0..2], .little);
        if (id != ZIP64_EXTRA_ID) return null;

        const size = mem.readInt(u16, data[2..4], .little);
        if (data.len < 4 + size) return null;

        var result = Zip64ExtraField{};
        var offset: usize = 4;

        if (offset + 8 <= 4 + size) {
            result.uncompressed_size = mem.readInt(u64, data[offset..][0..8], .little);
            offset += 8;
        }
        if (offset + 8 <= 4 + size) {
            result.compressed_size = mem.readInt(u64, data[offset..][0..8], .little);
            offset += 8;
        }
        if (offset + 8 <= 4 + size) {
            result.header_offset = mem.readInt(u64, data[offset..][0..8], .little);
            offset += 8;
        }
        if (offset + 4 <= 4 + size) {
            result.disk_number = mem.readInt(u32, data[offset..][0..4], .little);
        }

        return result;
    }

    pub fn needsZip64(uncompressed: u64, compressed: u64, offset: u64, entries: u64) bool {
        return uncompressed >= MAX_32BIT_VALUE or
            compressed >= MAX_32BIT_VALUE or
            offset >= MAX_32BIT_VALUE or
            entries >= MAX_16BIT_VALUE;
    }
};

// ============================================================================
// ZIP64 Archive Handler
// ============================================================================

pub const Zip64Handler = struct {
    const Self = @This();

    allocator: mem.Allocator,
    is_zip64: bool = false,
    total_entries: u64 = 0,
    cd_size: u64 = 0,
    cd_offset: u64 = 0,

    pub fn init(allocator: mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// Check if archive is ZIP64 format
    pub fn detectZip64(self: *Self, data: []const u8) bool {
        // Look for ZIP64 EOCD locator before regular EOCD
        if (data.len < 42) return false;

        const eocd_pos = self.findEocd(data) orelse return false;
        if (eocd_pos < 20) return false;

        // Check for ZIP64 locator 20 bytes before EOCD
        const locator_pos = eocd_pos - 20;
        if (mem.eql(u8, data[locator_pos..][0..4], &ZIP64_LOCATOR_MAGIC)) {
            self.is_zip64 = true;
            return true;
        }

        // Also check if EOCD has 0xFFFFFFFF values
        if (eocd_pos + 22 <= data.len) {
            const entries = mem.readInt(u16, data[eocd_pos + 10 ..][0..2], .little);
            const cd_size = mem.readInt(u32, data[eocd_pos + 12 ..][0..4], .little);
            const cd_offset = mem.readInt(u32, data[eocd_pos + 16 ..][0..4], .little);

            if (entries == MAX_16BIT_VALUE or cd_size == MAX_32BIT_VALUE or cd_offset == MAX_32BIT_VALUE) {
                self.is_zip64 = true;
                return true;
            }
        }

        return false;
    }

    fn findEocd(self: *Self, data: []const u8) ?usize {
        _ = self;
        if (data.len < 22) return null;

        const search_start = if (data.len > 65557) data.len - 65557 else 0;
        var i: usize = data.len - 22;

        while (i >= search_start) : (i -= 1) {
            if (mem.eql(u8, data[i..][0..4], &[_]u8{ 0x50, 0x4b, 0x05, 0x06 })) {
                return i;
            }
            if (i == 0) break;
        }
        return null;
    }

    /// Read ZIP64 EOCD
    pub fn readZip64Eocd(self: *Self, data: []const u8, locator: Zip64Locator) ?Zip64EndOfCentralDirectory {
        const offset = locator.zip64_eocd_offset;
        if (offset + 56 > data.len) return null;

        const eocd = Zip64EndOfCentralDirectory.decode(data[offset..]);
        if (eocd) |e| {
            self.total_entries = e.total_entries;
            self.cd_size = e.cd_size;
            self.cd_offset = e.cd_offset;
        }
        return eocd;
    }
};

// ============================================================================
// Large File Size Utilities
// ============================================================================

/// Format large file size with units
pub fn formatSize(size: u64) struct { value: f64, unit: []const u8 } {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB", "PB" };
    var value = @as(f64, @floatFromInt(size));
    var unit_idx: usize = 0;

    while (value >= 1024.0 and unit_idx < units.len - 1) {
        value /= 1024.0;
        unit_idx += 1;
    }

    return .{ .value = value, .unit = units[unit_idx] };
}

/// Check if size requires ZIP64
pub fn requiresZip64(size: u64) bool {
    return size >= @as(u64, MAX_32BIT_VALUE);
}

/// Check if entry count requires ZIP64
pub fn requiresZip64Entries(count: u64) bool {
    return count >= @as(u64, MAX_16BIT_VALUE);
}

// ============================================================================
// Tests
// ============================================================================

test "Zip64EndOfCentralDirectory encode decode roundtrip" {
    const original = Zip64EndOfCentralDirectory{
        .total_entries = 100000,
        .entries_on_disk = 100000,
        .cd_size = 5000000000,
        .cd_offset = 10000000000,
    };

    var buf: [56]u8 = undefined;
    original.encode(&buf);

    const decoded = Zip64EndOfCentralDirectory.decode(&buf);
    try testing.expect(decoded != null);
    try testing.expectEqual(original.total_entries, decoded.?.total_entries);
    try testing.expectEqual(original.cd_size, decoded.?.cd_size);
    try testing.expectEqual(original.cd_offset, decoded.?.cd_offset);
}

test "Zip64EndOfCentralDirectory decode invalid" {
    const invalid = [_]u8{0} ** 56;
    try testing.expect(Zip64EndOfCentralDirectory.decode(&invalid) == null);
}

test "Zip64EndOfCentralDirectory decode too short" {
    const short = [_]u8{0} ** 40;
    try testing.expect(Zip64EndOfCentralDirectory.decode(&short) == null);
}

test "Zip64Locator encode decode roundtrip" {
    const original = Zip64Locator{
        .disk_with_zip64_eocd = 0,
        .zip64_eocd_offset = 12345678901234,
        .total_disks = 1,
    };

    var buf: [20]u8 = undefined;
    original.encode(&buf);

    const decoded = Zip64Locator.decode(&buf);
    try testing.expect(decoded != null);
    try testing.expectEqual(original.zip64_eocd_offset, decoded.?.zip64_eocd_offset);
    try testing.expectEqual(original.total_disks, decoded.?.total_disks);
}

test "Zip64Locator decode invalid" {
    const invalid = [_]u8{0} ** 20;
    try testing.expect(Zip64Locator.decode(&invalid) == null);
}

test "Zip64ExtraField encode decode" {
    const original = Zip64ExtraField{
        .uncompressed_size = 5000000000,
        .compressed_size = 4000000000,
        .header_offset = 3000000000,
    };

    const encoded = try original.encode(testing.allocator);
    defer testing.allocator.free(encoded);

    const decoded = Zip64ExtraField.decode(encoded);
    try testing.expect(decoded != null);
    try testing.expectEqual(original.uncompressed_size, decoded.?.uncompressed_size);
    try testing.expectEqual(original.compressed_size, decoded.?.compressed_size);
}

test "Zip64ExtraField needsZip64" {
    try testing.expect(Zip64ExtraField.needsZip64(5000000000, 0, 0, 0));
    try testing.expect(Zip64ExtraField.needsZip64(0, 5000000000, 0, 0));
    try testing.expect(Zip64ExtraField.needsZip64(0, 0, 5000000000, 0));
    try testing.expect(Zip64ExtraField.needsZip64(0, 0, 0, 70000));
    try testing.expect(!Zip64ExtraField.needsZip64(1000, 1000, 1000, 1000));
}

test "Zip64Handler init" {
    var handler = Zip64Handler.init(testing.allocator);
    try testing.expect(!handler.is_zip64);
    try testing.expectEqual(@as(u64, 0), handler.total_entries);
}

test "formatSize bytes" {
    const result = formatSize(500);
    try testing.expectEqualStrings("B", result.unit);
    try testing.expectEqual(@as(f64, 500.0), result.value);
}

test "formatSize kilobytes" {
    const result = formatSize(2048);
    try testing.expectEqualStrings("KB", result.unit);
    try testing.expectEqual(@as(f64, 2.0), result.value);
}

test "formatSize megabytes" {
    const result = formatSize(5 * 1024 * 1024);
    try testing.expectEqualStrings("MB", result.unit);
    try testing.expectEqual(@as(f64, 5.0), result.value);
}

test "formatSize gigabytes" {
    const result = formatSize(10 * 1024 * 1024 * 1024);
    try testing.expectEqualStrings("GB", result.unit);
    try testing.expectEqual(@as(f64, 10.0), result.value);
}

test "requiresZip64" {
    try testing.expect(!requiresZip64(0));
    try testing.expect(!requiresZip64(1000000));
    try testing.expect(!requiresZip64(MAX_32BIT_VALUE - 1));
    try testing.expect(requiresZip64(MAX_32BIT_VALUE));
    try testing.expect(requiresZip64(5000000000));
}

test "requiresZip64Entries" {
    try testing.expect(!requiresZip64Entries(0));
    try testing.expect(!requiresZip64Entries(1000));
    try testing.expect(!requiresZip64Entries(MAX_16BIT_VALUE - 1));
    try testing.expect(requiresZip64Entries(MAX_16BIT_VALUE));
    try testing.expect(requiresZip64Entries(100000));
}

test "ZIP64 magic constants" {
    try testing.expectEqual(@as(u8, 0x50), ZIP64_END_MAGIC[0]);
    try testing.expectEqual(@as(u8, 0x4b), ZIP64_END_MAGIC[1]);
    try testing.expectEqual(@as(u8, 0x06), ZIP64_END_MAGIC[2]);
    try testing.expectEqual(@as(u8, 0x06), ZIP64_END_MAGIC[3]);

    try testing.expectEqual(@as(u8, 0x06), ZIP64_LOCATOR_MAGIC[2]);
    try testing.expectEqual(@as(u8, 0x07), ZIP64_LOCATOR_MAGIC[3]);
}

test "MAX values" {
    try testing.expectEqual(@as(u32, 0xFFFFFFFF), MAX_32BIT_VALUE);
    try testing.expectEqual(@as(u16, 0xFFFF), MAX_16BIT_VALUE);
}

test "Zip64EndOfCentralDirectory ENCODED_SIZE" {
    try testing.expectEqual(@as(usize, 56), Zip64EndOfCentralDirectory.ENCODED_SIZE);
}

test "Zip64Locator ENCODED_SIZE" {
    try testing.expectEqual(@as(usize, 20), Zip64Locator.ENCODED_SIZE);
}

test "ZIP64_EXTRA_ID constant" {
    try testing.expectEqual(@as(u16, 0x0001), ZIP64_EXTRA_ID);
}
