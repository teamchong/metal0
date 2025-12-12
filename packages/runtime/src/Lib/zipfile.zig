//! Python 'zipfile' module - Work with ZIP archives
//!
//! Provides tools to create, read, write, append, and list a ZIP file.
//!
//! Mirrors: CPython Lib/zipfile.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// ZIP magic bytes
pub const ZIP_MAGIC: [4]u8 = .{ 0x50, 0x4b, 0x03, 0x04 };
pub const ZIP_END_MAGIC: [4]u8 = .{ 0x50, 0x4b, 0x05, 0x06 };

/// Compression methods
pub const ZIP_STORED = 0;
pub const ZIP_DEFLATED = 8;
pub const ZIP_BZIP2 = 12;
pub const ZIP_LZMA = 14;

/// Default buffer size
pub const ZIP_BUFSIZE = 32768;

/// File attribute constants
pub const ZIP_FILECOUNT_LIMIT: u32 = (1 << 16) - 1;
pub const ZIP_MAX_COMMENT: u16 = (1 << 16) - 1;

// ============================================================================
// ZipInfo - Information about a member of a ZIP archive
// ============================================================================

/// Information about a member of a ZIP archive
pub const ZipInfo = struct {
    const Self = @This();

    filename: []const u8,
    date_time: DateTime = .{},
    compress_type: u16 = ZIP_STORED,
    comment: []const u8 = "",
    extra: []const u8 = "",
    internal_attr: u16 = 0,
    external_attr: u32 = 0,
    header_offset: u64 = 0,
    crc: u32 = 0,
    compress_size: u64 = 0,
    file_size: u64 = 0,
    flag_bits: u16 = 0,

    pub const DateTime = struct {
        year: u16 = 1980,
        month: u8 = 1,
        day: u8 = 1,
        hour: u8 = 0,
        minute: u8 = 0,
        second: u8 = 0,
    };

    pub fn init(filename: []const u8) Self {
        return .{ .filename = filename };
    }

    /// Check if this is a directory entry
    pub fn isDir(self: Self) bool {
        return self.filename.len > 0 and self.filename[self.filename.len - 1] == '/';
    }

    /// Get the DOS date format
    pub fn dosDate(self: Self) u16 {
        return (@as(u16, self.date_time.year - 1980) << 9) |
            (@as(u16, self.date_time.month) << 5) |
            @as(u16, self.date_time.day);
    }

    /// Get the DOS time format
    pub fn dosTime(self: Self) u16 {
        return (@as(u16, self.date_time.hour) << 11) |
            (@as(u16, self.date_time.minute) << 5) |
            (@as(u16, self.date_time.second) >> 1);
    }
};

// ============================================================================
// ZipFile - Main ZIP archive handler
// ============================================================================

/// A class for reading and writing ZIP files
pub const ZipFile = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    mode: Mode,
    filename: ?[]const u8 = null,
    file: ?std.fs.File = null,
    filelist: std.ArrayList(ZipInfo),
    compression: u16 = ZIP_DEFLATED,
    compresslevel: ?i32 = null,
    comment: []const u8 = "",
    closed: bool = false,

    pub const Mode = enum {
        read,
        write,
        append,
        exclusive,
    };

    pub fn init(allocator: std.mem.Allocator, mode: Mode) Self {
        return .{
            .allocator = allocator,
            .mode = mode,
            .filelist = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.filelist.deinit(self.allocator);
        if (self.file) |*f| {
            f.close();
        }
    }

    /// Open a ZIP file
    pub fn open(self: *Self, filename: []const u8) !void {
        self.filename = filename;
        switch (self.mode) {
            .read => {
                self.file = try std.fs.cwd().openFile(filename, .{});
                try self.readDirectory();
            },
            .write => {
                self.file = try std.fs.cwd().createFile(filename, .{});
            },
            .append => {
                self.file = std.fs.cwd().openFile(filename, .{ .mode = .read_write }) catch |err| {
                    if (err == error.FileNotFound) {
                        self.file = try std.fs.cwd().createFile(filename, .{});
                        return;
                    }
                    return err;
                };
                try self.file.?.seekFromEnd(0);
            },
            .exclusive => {
                // Fail if file exists
                if (std.fs.cwd().access(filename, .{})) |_| {
                    return error.FileExistsError;
                } else |_| {}
                self.file = try std.fs.cwd().createFile(filename, .{});
            },
        }
    }

    /// Read the central directory from the ZIP file
    fn readDirectory(self: *Self) !void {
        if (self.file == null) return;

        // Seek to find end of central directory
        const file_size = try self.file.?.getEndPos();
        if (file_size < 22) return error.BadZipFile;

        // Read end of central directory record
        try self.file.?.seekTo(file_size - 22);
        var end_record: [22]u8 = undefined;
        _ = try self.file.?.readAll(&end_record);

        if (!std.mem.eql(u8, end_record[0..4], &ZIP_END_MAGIC)) {
            return error.BadZipFile;
        }

        const num_entries = std.mem.readInt(u16, end_record[8..10], .little);
        const cd_offset = std.mem.readInt(u32, end_record[16..20], .little);

        // Read central directory
        try self.file.?.seekTo(cd_offset);

        for (0..num_entries) |_| {
            var header: [46]u8 = undefined;
            _ = try self.file.?.readAll(&header);

            // Verify central directory signature
            if (!std.mem.eql(u8, header[0..4], &[_]u8{ 0x50, 0x4b, 0x01, 0x02 })) {
                return error.BadZipFile;
            }

            const name_len = std.mem.readInt(u16, header[28..30], .little);
            const extra_len = std.mem.readInt(u16, header[30..32], .little);
            const comment_len = std.mem.readInt(u16, header[32..34], .little);

            // Read filename
            const name = try self.allocator.alloc(u8, name_len);
            _ = try self.file.?.readAll(name);

            // Skip extra and comment
            try self.file.?.seekBy(@intCast(extra_len + comment_len));

            var info = ZipInfo.init(name);
            info.compress_type = std.mem.readInt(u16, header[10..12], .little);
            info.crc = std.mem.readInt(u32, header[16..20], .little);
            info.compress_size = std.mem.readInt(u32, header[20..24], .little);
            info.file_size = std.mem.readInt(u32, header[24..28], .little);
            info.header_offset = std.mem.readInt(u32, header[42..46], .little);

            try self.filelist.append(self.allocator, info);
        }
    }

    /// Get list of archive members
    pub fn namelist(self: Self) ![][]const u8 {
        var names = try self.allocator.alloc([]const u8, self.filelist.items.len);
        for (self.filelist.items, 0..) |info, i| {
            names[i] = info.filename;
        }
        return names;
    }

    /// Get list of ZipInfo objects
    pub fn infolist(self: Self) []ZipInfo {
        return self.filelist.items;
    }

    /// Get info about a specific member
    pub fn getinfo(self: Self, name: []const u8) ?ZipInfo {
        for (self.filelist.items) |info| {
            if (std.mem.eql(u8, info.filename, name)) {
                return info;
            }
        }
        return null;
    }

    /// Read a file from the archive
    pub fn read(self: *Self, name: []const u8) ![]u8 {
        const info = self.getinfo(name) orelse return error.KeyError;
        return self.readWithInfo(info);
    }

    /// Read a file using ZipInfo
    pub fn readWithInfo(self: *Self, info: ZipInfo) ![]u8 {
        if (self.file == null) return error.FileNotOpen;

        // Seek to local file header
        try self.file.?.seekTo(info.header_offset);

        // Read local file header
        var local_header: [30]u8 = undefined;
        _ = try self.file.?.readAll(&local_header);

        if (!std.mem.eql(u8, local_header[0..4], &ZIP_MAGIC)) {
            return error.BadZipFile;
        }

        const name_len = std.mem.readInt(u16, local_header[26..28], .little);
        const extra_len = std.mem.readInt(u16, local_header[28..30], .little);

        // Skip filename and extra
        try self.file.?.seekBy(@intCast(name_len + extra_len));

        // Read compressed data
        const compressed = try self.allocator.alloc(u8, @intCast(info.compress_size));
        errdefer self.allocator.free(compressed);
        _ = try self.file.?.readAll(compressed);

        // Decompress
        if (info.compress_type == ZIP_STORED) {
            return compressed;
        } else if (info.compress_type == ZIP_DEFLATED) {
            var fbs = std.io.fixedBufferStream(compressed);
            var decomp = std.compress.zlib.decompressor(fbs.reader());
            const result = try decomp.reader().readAllAlloc(self.allocator, @intCast(info.file_size));
            self.allocator.free(compressed);
            return result;
        } else {
            return error.UnsupportedCompression;
        }
    }

    /// Write a file to the archive
    pub fn writestr(self: *Self, name: []const u8, data: []const u8) !void {
        if (self.mode == .read) return error.InvalidMode;
        if (self.file == null) return error.FileNotOpen;

        var info = ZipInfo.init(name);
        info.file_size = data.len;
        info.compress_type = self.compression;

        // Compress data
        var compressed: std.ArrayList(u8) = .{};
        defer compressed.deinit(self.allocator);

        if (self.compression == ZIP_STORED) {
            try compressed.appendSlice(self.allocator, data);
        } else if (self.compression == ZIP_DEFLATED) {
            var comp = try std.compress.zlib.compressor(compressed.writer(self.allocator), .{});
            try comp.writer().writeAll(data);
            try comp.finish();
        } else {
            return error.UnsupportedCompression;
        }

        info.compress_size = compressed.items.len;
        info.crc = std.hash.crc.Crc32.hash(data);
        info.header_offset = try self.file.?.getPos();

        // Write local file header
        var local_header: [30]u8 = undefined;
        @memcpy(local_header[0..4], &ZIP_MAGIC);
        std.mem.writeInt(u16, local_header[4..6], 20, .little); // version needed
        std.mem.writeInt(u16, local_header[6..8], 0, .little); // flags
        std.mem.writeInt(u16, local_header[8..10], info.compress_type, .little);
        std.mem.writeInt(u16, local_header[10..12], info.dosTime(), .little);
        std.mem.writeInt(u16, local_header[12..14], info.dosDate(), .little);
        std.mem.writeInt(u32, local_header[14..18], info.crc, .little);
        std.mem.writeInt(u32, local_header[18..22], @intCast(info.compress_size), .little);
        std.mem.writeInt(u32, local_header[22..26], @intCast(info.file_size), .little);
        std.mem.writeInt(u16, local_header[26..28], @intCast(name.len), .little);
        std.mem.writeInt(u16, local_header[28..30], 0, .little); // extra length

        try self.file.?.writeAll(&local_header);
        try self.file.?.writeAll(name);
        try self.file.?.writeAll(compressed.items);

        try self.filelist.append(self.allocator, info);
    }

    /// Close the archive
    pub fn close(self: *Self) !void {
        if (self.closed) return;

        if (self.mode != .read and self.file != null) {
            // Write central directory
            const cd_offset = try self.file.?.getPos();

            for (self.filelist.items) |info| {
                var cd_entry: [46]u8 = undefined;
                @memcpy(cd_entry[0..4], &[_]u8{ 0x50, 0x4b, 0x01, 0x02 });
                std.mem.writeInt(u16, cd_entry[4..6], 20, .little); // version made by
                std.mem.writeInt(u16, cd_entry[6..8], 20, .little); // version needed
                std.mem.writeInt(u16, cd_entry[8..10], 0, .little); // flags
                std.mem.writeInt(u16, cd_entry[10..12], info.compress_type, .little);
                std.mem.writeInt(u16, cd_entry[12..14], info.dosTime(), .little);
                std.mem.writeInt(u16, cd_entry[14..16], info.dosDate(), .little);
                std.mem.writeInt(u32, cd_entry[16..20], info.crc, .little);
                std.mem.writeInt(u32, cd_entry[20..24], @intCast(info.compress_size), .little);
                std.mem.writeInt(u32, cd_entry[24..28], @intCast(info.file_size), .little);
                std.mem.writeInt(u16, cd_entry[28..30], @intCast(info.filename.len), .little);
                std.mem.writeInt(u16, cd_entry[30..32], 0, .little); // extra length
                std.mem.writeInt(u16, cd_entry[32..34], 0, .little); // comment length
                std.mem.writeInt(u16, cd_entry[34..36], 0, .little); // disk start
                std.mem.writeInt(u16, cd_entry[36..38], info.internal_attr, .little);
                std.mem.writeInt(u32, cd_entry[38..42], info.external_attr, .little);
                std.mem.writeInt(u32, cd_entry[42..46], @intCast(info.header_offset), .little);

                try self.file.?.writeAll(&cd_entry);
                try self.file.?.writeAll(info.filename);
            }

            const cd_end = try self.file.?.getPos();

            // Write end of central directory
            var end_record: [22]u8 = undefined;
            @memcpy(end_record[0..4], &ZIP_END_MAGIC);
            std.mem.writeInt(u16, end_record[4..6], 0, .little); // disk number
            std.mem.writeInt(u16, end_record[6..8], 0, .little); // disk with CD
            std.mem.writeInt(u16, end_record[8..10], @intCast(self.filelist.items.len), .little);
            std.mem.writeInt(u16, end_record[10..12], @intCast(self.filelist.items.len), .little);
            std.mem.writeInt(u32, end_record[12..16], @intCast(cd_end - cd_offset), .little);
            std.mem.writeInt(u32, end_record[16..20], @intCast(cd_offset), .little);
            std.mem.writeInt(u16, end_record[20..22], 0, .little); // comment length

            try self.file.?.writeAll(&end_record);
        }

        if (self.file) |*f| {
            f.close();
            self.file = null;
        }

        self.closed = true;
    }

    /// Test if the archive is valid
    pub fn testzip(self: *Self) !?[]const u8 {
        for (self.filelist.items) |info| {
            const data = self.readWithInfo(info) catch |err| {
                _ = err;
                return info.filename;
            };
            self.allocator.free(data);

            // Could verify CRC here
        }
        return null;
    }
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Check if a file is a valid ZIP file
pub fn isZipfile(filename: []const u8) bool {
    const file = std.fs.cwd().openFile(filename, .{}) catch return false;
    defer file.close();

    var magic: [4]u8 = undefined;
    _ = file.readAll(&magic) catch return false;

    return std.mem.eql(u8, &magic, &ZIP_MAGIC);
}

// ============================================================================
// Exceptions
// ============================================================================

pub const BadZipFile = error.BadZipFile;
pub const LargeZipFile = error.LargeZipFile;

// ============================================================================
// Tests
// ============================================================================

test "ZipInfo" {
    var info = ZipInfo.init("test.txt");

    try std.testing.expectEqualStrings("test.txt", info.filename);
    try std.testing.expect(!info.isDir());

    info = ZipInfo.init("testdir/");
    try std.testing.expect(info.isDir());
}

test "ZipFile init" {
    const allocator = std.testing.allocator;

    var zf = ZipFile.init(allocator, .write);
    defer zf.deinit();

    try std.testing.expect(!zf.closed);
    try std.testing.expectEqual(ZipFile.Mode.write, zf.mode);
}

test "constants" {
    try std.testing.expectEqual(@as(u8, 0x50), ZIP_MAGIC[0]);
    try std.testing.expectEqual(@as(u8, 0x4b), ZIP_MAGIC[1]);
    try std.testing.expectEqual(@as(u16, 0), ZIP_STORED);
    try std.testing.expectEqual(@as(u16, 8), ZIP_DEFLATED);
}
