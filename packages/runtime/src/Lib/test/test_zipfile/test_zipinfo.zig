//! test.test_zipfile.test_zipinfo - ZipInfo tests
//!
//! Tests for ZipInfo struct which contains metadata about files in a ZIP archive,
//! including timestamps, compression, permissions, and file attributes.

const std = @import("std");
const testing = std.testing;
const mem = std.mem;

// ============================================================================
// ZipInfo - File metadata in ZIP archive
// ============================================================================

pub const ZipInfo = struct {
    const Self = @This();

    /// File name (path within archive)
    filename: []const u8,

    /// File modification date and time
    date_time: DateTime = .{},

    /// Compression method
    compress_type: CompressionType = .stored,

    /// File comment
    comment: []const u8 = "",

    /// Extra field data
    extra: []const u8 = "",

    /// System that created the file
    create_system: CreateSystem = .unix,

    /// ZIP version used to create
    create_version: u8 = 20,

    /// ZIP version needed to extract
    extract_version: u8 = 20,

    /// General purpose bit flags
    flag_bits: u16 = 0,

    /// Disk number start
    volume: u16 = 0,

    /// Internal file attributes
    internal_attr: u16 = 0,

    /// External file attributes (permissions)
    external_attr: u32 = 0,

    /// Local header offset
    header_offset: u64 = 0,

    /// CRC-32 checksum
    crc: u32 = 0,

    /// Compressed size
    compress_size: u64 = 0,

    /// Uncompressed size
    file_size: u64 = 0,

    pub const CompressionType = enum(u16) {
        stored = 0,
        deflated = 8,
        bzip2 = 12,
        lzma = 14,
    };

    pub const CreateSystem = enum(u8) {
        msdos = 0,
        amiga = 1,
        openvms = 2,
        unix = 3,
        vm_cms = 4,
        atari = 5,
        os2_hpfs = 6,
        macintosh = 7,
        z_system = 8,
        cpm = 9,
        ntfs = 10,
        mvs = 11,
        vse = 12,
        acorn_risc = 13,
        vfat = 14,
        alt_mvs = 15,
        beos = 16,
        tandem = 17,
        os400 = 18,
        osx = 19,
    };

    pub const DateTime = struct {
        year: u16 = 1980,
        month: u8 = 1,
        day: u8 = 1,
        hour: u8 = 0,
        minute: u8 = 0,
        second: u8 = 0,

        /// Create from DOS date/time format
        pub fn fromDos(date: u16, time: u16) DateTime {
            return .{
                .year = @as(u16, @intCast((date >> 9) & 0x7F)) + 1980,
                .month = @intCast((date >> 5) & 0x0F),
                .day = @intCast(date & 0x1F),
                .hour = @intCast((time >> 11) & 0x1F),
                .minute = @intCast((time >> 5) & 0x3F),
                .second = @intCast((time & 0x1F) * 2),
            };
        }

        /// Convert to DOS date format
        pub fn toDosDate(self: DateTime) u16 {
            return (@as(u16, self.year - 1980) << 9) |
                (@as(u16, self.month) << 5) |
                @as(u16, self.day);
        }

        /// Convert to DOS time format
        pub fn toDosTime(self: DateTime) u16 {
            return (@as(u16, self.hour) << 11) |
                (@as(u16, self.minute) << 5) |
                (@as(u16, self.second) >> 1);
        }

        /// Check if date is valid
        pub fn isValid(self: DateTime) bool {
            if (self.year < 1980 or self.year > 2107) return false;
            if (self.month < 1 or self.month > 12) return false;
            if (self.day < 1 or self.day > 31) return false;
            if (self.hour > 23) return false;
            if (self.minute > 59) return false;
            if (self.second > 59) return false;
            return true;
        }

        /// Format as ISO string
        pub fn toIsoString(self: DateTime, buf: []u8) ![]u8 {
            return try std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
                self.year, self.month, self.day,
                self.hour, self.minute, self.second,
            });
        }
    };

    /// Create ZipInfo for a file
    pub fn init(filename: []const u8) Self {
        return .{ .filename = filename };
    }

    /// Check if this entry is a directory
    pub fn isDir(self: Self) bool {
        return self.filename.len > 0 and self.filename[self.filename.len - 1] == '/';
    }

    /// Check if entry is encrypted
    pub fn isEncrypted(self: Self) bool {
        return (self.flag_bits & 0x1) != 0;
    }

    /// Check if entry has data descriptor
    pub fn hasDataDescriptor(self: Self) bool {
        return (self.flag_bits & 0x8) != 0;
    }

    /// Check if entry uses UTF-8 encoding
    pub fn isUtf8(self: Self) bool {
        return (self.flag_bits & 0x800) != 0;
    }

    /// Get Unix file mode (permissions)
    pub fn getUnixMode(self: Self) ?u16 {
        if (self.create_system != .unix) return null;
        return @truncate(self.external_attr >> 16);
    }

    /// Set Unix file mode
    pub fn setUnixMode(self: *Self, mode: u16) void {
        self.create_system = .unix;
        self.external_attr = @as(u32, mode) << 16;
    }

    /// Get compression ratio
    pub fn compressionRatio(self: Self) f64 {
        if (self.file_size == 0) return 0.0;
        return 1.0 - (@as(f64, @floatFromInt(self.compress_size)) /
            @as(f64, @floatFromInt(self.file_size)));
    }

    /// Get file extension
    pub fn extension(self: Self) ?[]const u8 {
        const dot = mem.lastIndexOfScalar(u8, self.filename, '.');
        if (dot) |pos| {
            if (pos < self.filename.len - 1) {
                return self.filename[pos + 1 ..];
            }
        }
        return null;
    }

    /// Check if entry appears to be text file
    pub fn isTextFile(self: Self) bool {
        // Based on internal attributes bit 0
        return (self.internal_attr & 0x1) != 0;
    }

    /// Clone the ZipInfo
    pub fn clone(self: Self, allocator: mem.Allocator) !Self {
        var copy = self;
        copy.filename = try allocator.dupe(u8, self.filename);
        if (self.comment.len > 0) {
            copy.comment = try allocator.dupe(u8, self.comment);
        }
        if (self.extra.len > 0) {
            copy.extra = try allocator.dupe(u8, self.extra);
        }
        return copy;
    }

    /// Free cloned resources
    pub fn deinitCloned(self: Self, allocator: mem.Allocator) void {
        allocator.free(self.filename);
        if (self.comment.len > 0) allocator.free(self.comment);
        if (self.extra.len > 0) allocator.free(self.extra);
    }
};

// ============================================================================
// ZipInfoList - Collection of ZipInfo entries
// ============================================================================

pub const ZipInfoList = struct {
    const Self = @This();

    allocator: mem.Allocator,
    items: std.ArrayList(ZipInfo),

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .items = std.ArrayList(ZipInfo).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.items.deinit();
    }

    pub fn add(self: *Self, info: ZipInfo) !void {
        try self.items.append(info);
    }

    pub fn len(self: Self) usize {
        return self.items.items.len;
    }

    pub fn get(self: Self, index: usize) ?ZipInfo {
        if (index >= self.items.items.len) return null;
        return self.items.items[index];
    }

    pub fn findByName(self: Self, name: []const u8) ?ZipInfo {
        for (self.items.items) |info| {
            if (mem.eql(u8, info.filename, name)) {
                return info;
            }
        }
        return null;
    }

    pub fn totalSize(self: Self) u64 {
        var total: u64 = 0;
        for (self.items.items) |info| {
            total += info.file_size;
        }
        return total;
    }

    pub fn totalCompressedSize(self: Self) u64 {
        var total: u64 = 0;
        for (self.items.items) |info| {
            total += info.compress_size;
        }
        return total;
    }
};

// ============================================================================
// Extra Field Parsing
// ============================================================================

pub const ExtraField = struct {
    header_id: u16,
    data: []const u8,

    pub const HeaderId = enum(u16) {
        zip64 = 0x0001,
        av_info = 0x0007,
        extended_language = 0x0008,
        os2 = 0x0009,
        ntfs = 0x000a,
        openvms = 0x000c,
        unix = 0x000d,
        stream_and_fork = 0x000e,
        patch_descriptor = 0x000f,
        pkcs7_store = 0x0014,
        x509_cert = 0x0015,
        x509_central = 0x0016,
        strong_encryption = 0x0017,
        record_mgmt = 0x0018,
        pkcs7_recipient = 0x0019,
        ibm_attributes = 0x0065,
        unicode_path = 0x7075,
        unicode_comment = 0x6375,
        aes_encryption = 0x9901,
        _,
    };
};

/// Parse extra field data
pub fn parseExtraFields(data: []const u8, allocator: mem.Allocator) !std.ArrayList(ExtraField) {
    var fields = std.ArrayList(ExtraField).init(allocator);
    errdefer fields.deinit();

    var offset: usize = 0;
    while (offset + 4 <= data.len) {
        const header_id = mem.readInt(u16, data[offset..][0..2], .little);
        const size = mem.readInt(u16, data[offset + 2 ..][0..2], .little);
        offset += 4;

        if (offset + size > data.len) break;

        try fields.append(.{
            .header_id = header_id,
            .data = data[offset..][0..size],
        });

        offset += size;
    }

    return fields;
}

// ============================================================================
// Tests
// ============================================================================

test "ZipInfo init" {
    const info = ZipInfo.init("test.txt");
    try testing.expectEqualStrings("test.txt", info.filename);
    try testing.expect(!info.isDir());
}

test "ZipInfo isDir" {
    const file_info = ZipInfo.init("file.txt");
    const dir_info = ZipInfo.init("directory/");

    try testing.expect(!file_info.isDir());
    try testing.expect(dir_info.isDir());
}

test "ZipInfo.DateTime fromDos" {
    // 2024-03-15 10:30:00
    const date: u16 = ((2024 - 1980) << 9) | (3 << 5) | 15;
    const time: u16 = (10 << 11) | (30 << 5) | 0;

    const dt = ZipInfo.DateTime.fromDos(date, time);
    try testing.expectEqual(@as(u16, 2024), dt.year);
    try testing.expectEqual(@as(u8, 3), dt.month);
    try testing.expectEqual(@as(u8, 15), dt.day);
    try testing.expectEqual(@as(u8, 10), dt.hour);
    try testing.expectEqual(@as(u8, 30), dt.minute);
}

test "ZipInfo.DateTime toDos roundtrip" {
    const dt = ZipInfo.DateTime{
        .year = 2024,
        .month = 6,
        .day = 20,
        .hour = 14,
        .minute = 45,
        .second = 30,
    };

    const date = dt.toDosDate();
    const time = dt.toDosTime();
    const restored = ZipInfo.DateTime.fromDos(date, time);

    try testing.expectEqual(dt.year, restored.year);
    try testing.expectEqual(dt.month, restored.month);
    try testing.expectEqual(dt.day, restored.day);
    try testing.expectEqual(dt.hour, restored.hour);
    try testing.expectEqual(dt.minute, restored.minute);
}

test "ZipInfo.DateTime isValid" {
    const valid = ZipInfo.DateTime{
        .year = 2024,
        .month = 6,
        .day = 15,
        .hour = 12,
        .minute = 30,
        .second = 45,
    };
    try testing.expect(valid.isValid());

    const invalid_month = ZipInfo.DateTime{ .month = 13 };
    try testing.expect(!invalid_month.isValid());

    const invalid_day = ZipInfo.DateTime{ .day = 32 };
    try testing.expect(!invalid_day.isValid());

    const invalid_year = ZipInfo.DateTime{ .year = 1970 };
    try testing.expect(!invalid_year.isValid());
}

test "ZipInfo.DateTime toIsoString" {
    const dt = ZipInfo.DateTime{
        .year = 2024,
        .month = 3,
        .day = 15,
        .hour = 10,
        .minute = 30,
        .second = 0,
    };

    var buf: [32]u8 = undefined;
    const str = try dt.toIsoString(&buf);
    try testing.expectEqualStrings("2024-03-15 10:30:00", str);
}

test "ZipInfo isEncrypted" {
    var info = ZipInfo.init("secret.txt");
    try testing.expect(!info.isEncrypted());

    info.flag_bits = 0x1;
    try testing.expect(info.isEncrypted());
}

test "ZipInfo hasDataDescriptor" {
    var info = ZipInfo.init("test.txt");
    try testing.expect(!info.hasDataDescriptor());

    info.flag_bits = 0x8;
    try testing.expect(info.hasDataDescriptor());
}

test "ZipInfo isUtf8" {
    var info = ZipInfo.init("test.txt");
    try testing.expect(!info.isUtf8());

    info.flag_bits = 0x800;
    try testing.expect(info.isUtf8());
}

test "ZipInfo getUnixMode" {
    var info = ZipInfo.init("test.txt");
    info.create_system = .unix;
    info.external_attr = 0o644 << 16;

    try testing.expectEqual(@as(u16, 0o644), info.getUnixMode().?);

    info.create_system = .msdos;
    try testing.expect(info.getUnixMode() == null);
}

test "ZipInfo setUnixMode" {
    var info = ZipInfo.init("test.txt");
    info.setUnixMode(0o755);

    try testing.expectEqual(ZipInfo.CreateSystem.unix, info.create_system);
    try testing.expectEqual(@as(u16, 0o755), info.getUnixMode().?);
}

test "ZipInfo compressionRatio" {
    var info = ZipInfo.init("test.txt");
    info.file_size = 1000;
    info.compress_size = 500;

    try testing.expectEqual(@as(f64, 0.5), info.compressionRatio());

    info.file_size = 0;
    try testing.expectEqual(@as(f64, 0.0), info.compressionRatio());
}

test "ZipInfo extension" {
    const txt_info = ZipInfo.init("document.txt");
    try testing.expectEqualStrings("txt", txt_info.extension().?);

    const no_ext = ZipInfo.init("README");
    try testing.expect(no_ext.extension() == null);

    const hidden = ZipInfo.init(".gitignore");
    try testing.expectEqualStrings("gitignore", hidden.extension().?);
}

test "ZipInfo clone" {
    const original = ZipInfo{
        .filename = "test.txt",
        .comment = "A comment",
        .file_size = 100,
    };

    const cloned = try original.clone(testing.allocator);
    defer cloned.deinitCloned(testing.allocator);

    try testing.expectEqualStrings(original.filename, cloned.filename);
    try testing.expectEqualStrings(original.comment, cloned.comment);
    try testing.expectEqual(original.file_size, cloned.file_size);
}

test "ZipInfoList" {
    var list = ZipInfoList.init(testing.allocator);
    defer list.deinit();

    try list.add(ZipInfo.init("file1.txt"));
    try list.add(ZipInfo.init("file2.txt"));

    try testing.expectEqual(@as(usize, 2), list.len());
    try testing.expectEqualStrings("file1.txt", list.get(0).?.filename);
}

test "ZipInfoList findByName" {
    var list = ZipInfoList.init(testing.allocator);
    defer list.deinit();

    var info = ZipInfo.init("target.txt");
    info.file_size = 12345;
    try list.add(info);

    const found = list.findByName("target.txt");
    try testing.expect(found != null);
    try testing.expectEqual(@as(u64, 12345), found.?.file_size);

    try testing.expect(list.findByName("missing.txt") == null);
}

test "ZipInfoList totalSize" {
    var list = ZipInfoList.init(testing.allocator);
    defer list.deinit();

    var info1 = ZipInfo.init("file1.txt");
    info1.file_size = 100;
    info1.compress_size = 50;
    try list.add(info1);

    var info2 = ZipInfo.init("file2.txt");
    info2.file_size = 200;
    info2.compress_size = 100;
    try list.add(info2);

    try testing.expectEqual(@as(u64, 300), list.totalSize());
    try testing.expectEqual(@as(u64, 150), list.totalCompressedSize());
}

test "ExtraField.HeaderId" {
    try testing.expectEqual(@as(u16, 0x0001), @intFromEnum(ExtraField.HeaderId.zip64));
    try testing.expectEqual(@as(u16, 0x7075), @intFromEnum(ExtraField.HeaderId.unicode_path));
    try testing.expectEqual(@as(u16, 0x9901), @intFromEnum(ExtraField.HeaderId.aes_encryption));
}

test "parseExtraFields" {
    // Create a simple extra field: header_id=0x0001, size=4, data=0x01020304
    const data = [_]u8{
        0x01, 0x00, // header_id = 1 (zip64)
        0x04, 0x00, // size = 4
        0x01, 0x02, 0x03, 0x04, // data
    };

    var fields = try parseExtraFields(&data, testing.allocator);
    defer fields.deinit();

    try testing.expectEqual(@as(usize, 1), fields.items.len);
    try testing.expectEqual(@as(u16, 0x0001), fields.items[0].header_id);
    try testing.expectEqual(@as(usize, 4), fields.items[0].data.len);
}

test "CompressionType values" {
    try testing.expectEqual(@as(u16, 0), @intFromEnum(ZipInfo.CompressionType.stored));
    try testing.expectEqual(@as(u16, 8), @intFromEnum(ZipInfo.CompressionType.deflated));
    try testing.expectEqual(@as(u16, 12), @intFromEnum(ZipInfo.CompressionType.bzip2));
    try testing.expectEqual(@as(u16, 14), @intFromEnum(ZipInfo.CompressionType.lzma));
}

test "CreateSystem values" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(ZipInfo.CreateSystem.msdos));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(ZipInfo.CreateSystem.unix));
    try testing.expectEqual(@as(u8, 10), @intFromEnum(ZipInfo.CreateSystem.ntfs));
}
