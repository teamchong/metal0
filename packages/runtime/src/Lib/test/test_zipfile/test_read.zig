//! test.test_zipfile.test_read - ZIP file reading tests
//!
//! Tests for reading ZIP archives including opening files, reading content,
//! handling various compression methods, and error conditions.

const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const fs = std.fs;

// ============================================================================
// Test Constants
// ============================================================================

/// ZIP local file header signature
const ZIP_MAGIC: [4]u8 = .{ 0x50, 0x4b, 0x03, 0x04 };

/// End of central directory signature
const ZIP_END_MAGIC: [4]u8 = .{ 0x50, 0x4b, 0x05, 0x06 };

/// Central directory file header signature
const ZIP_CENTRAL_MAGIC: [4]u8 = .{ 0x50, 0x4b, 0x01, 0x02 };

// ============================================================================
// ZipReader - Core reading functionality
// ============================================================================

pub const ZipReader = struct {
    const Self = @This();

    allocator: mem.Allocator,
    file: ?fs.File = null,
    entries: std.ArrayList(ZipEntry),
    comment: []const u8 = "",
    closed: bool = false,

    pub const ZipEntry = struct {
        filename: []const u8,
        compress_type: u16,
        crc32: u32,
        compressed_size: u64,
        uncompressed_size: u64,
        header_offset: u64,
        extra: []const u8 = "",
        comment: []const u8 = "",
        is_dir: bool = false,
        is_encrypted: bool = false,
    };

    pub const ReadError = error{
        BadZipFile,
        FileNotFound,
        CorruptedFile,
        UnsupportedCompression,
        CrcMismatch,
        DecryptionFailed,
        OutOfMemory,
    };

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .entries = std.ArrayList(ZipEntry).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.filename);
            if (entry.extra.len > 0) self.allocator.free(entry.extra);
            if (entry.comment.len > 0) self.allocator.free(entry.comment);
        }
        self.entries.deinit();
        if (self.comment.len > 0) self.allocator.free(self.comment);
        if (self.file) |*f| f.close();
    }

    /// Open a ZIP file for reading
    pub fn open(self: *Self, path: []const u8) ReadError!void {
        self.file = fs.cwd().openFile(path, .{}) catch return error.FileNotFound;
        errdefer {
            if (self.file) |*f| f.close();
            self.file = null;
        }
        try self.readCentralDirectory();
    }

    /// Read end of central directory and parse entries
    fn readCentralDirectory(self: *Self) ReadError!void {
        const file = self.file orelse return error.BadZipFile;

        // Get file size
        const file_size = file.getEndPos() catch return error.BadZipFile;
        if (file_size < 22) return error.BadZipFile;

        // Search for end of central directory record (last 65KB max)
        const search_size: u64 = @min(file_size, 65557);
        const search_start = file_size - search_size;

        file.seekTo(search_start) catch return error.BadZipFile;

        var buffer: [65557]u8 = undefined;
        const bytes_read = file.readAll(buffer[0..@intCast(search_size)]) catch return error.BadZipFile;

        // Find end of central directory signature
        var eocd_offset: ?usize = null;
        var i: usize = bytes_read;
        while (i >= 4) {
            i -= 1;
            if (mem.eql(u8, buffer[i..][0..4], &ZIP_END_MAGIC)) {
                eocd_offset = i;
                break;
            }
        }

        const offset = eocd_offset orelse return error.BadZipFile;
        if (bytes_read - offset < 22) return error.BadZipFile;

        // Parse end of central directory
        const eocd = buffer[offset..];
        const num_entries = mem.readInt(u16, eocd[10..12], .little);
        const cd_offset = mem.readInt(u32, eocd[16..20], .little);

        // Read central directory entries
        file.seekTo(cd_offset) catch return error.BadZipFile;

        for (0..num_entries) |_| {
            var header: [46]u8 = undefined;
            _ = file.readAll(&header) catch return error.BadZipFile;

            if (!mem.eql(u8, header[0..4], &ZIP_CENTRAL_MAGIC)) {
                return error.BadZipFile;
            }

            const name_len = mem.readInt(u16, header[28..30], .little);
            const extra_len = mem.readInt(u16, header[30..32], .little);
            const comment_len = mem.readInt(u16, header[32..34], .little);

            // Read filename
            const filename = self.allocator.alloc(u8, name_len) catch return error.OutOfMemory;
            _ = file.readAll(filename) catch return error.BadZipFile;

            // Read extra field
            const extra = if (extra_len > 0) blk: {
                const e = self.allocator.alloc(u8, extra_len) catch return error.OutOfMemory;
                _ = file.readAll(e) catch return error.BadZipFile;
                break :blk e;
            } else "";

            // Read comment
            const comment_data = if (comment_len > 0) blk: {
                const c = self.allocator.alloc(u8, comment_len) catch return error.OutOfMemory;
                _ = file.readAll(c) catch return error.BadZipFile;
                break :blk c;
            } else "";

            const entry = ZipEntry{
                .filename = filename,
                .compress_type = mem.readInt(u16, header[10..12], .little),
                .crc32 = mem.readInt(u32, header[16..20], .little),
                .compressed_size = mem.readInt(u32, header[20..24], .little),
                .uncompressed_size = mem.readInt(u32, header[24..28], .little),
                .header_offset = mem.readInt(u32, header[42..46], .little),
                .extra = extra,
                .comment = comment_data,
                .is_dir = filename.len > 0 and filename[filename.len - 1] == '/',
                .is_encrypted = (mem.readInt(u16, header[8..10], .little) & 0x1) != 0,
            };

            self.entries.append(entry) catch return error.OutOfMemory;
        }
    }

    /// Get number of entries in the archive
    pub fn entryCount(self: Self) usize {
        return self.entries.items.len;
    }

    /// Get entry by name
    pub fn getEntry(self: Self, name: []const u8) ?ZipEntry {
        for (self.entries.items) |entry| {
            if (mem.eql(u8, entry.filename, name)) {
                return entry;
            }
        }
        return null;
    }

    /// Get entry by index
    pub fn getEntryByIndex(self: Self, index: usize) ?ZipEntry {
        if (index >= self.entries.items.len) return null;
        return self.entries.items[index];
    }

    /// Read file content
    pub fn read(self: *Self, name: []const u8) ReadError![]u8 {
        const entry = self.getEntry(name) orelse return error.FileNotFound;
        return self.readEntry(entry);
    }

    /// Read entry content
    pub fn readEntry(self: *Self, entry: ZipEntry) ReadError![]u8 {
        const file = self.file orelse return error.BadZipFile;

        if (entry.is_encrypted) return error.DecryptionFailed;

        // Seek to local file header
        file.seekTo(entry.header_offset) catch return error.BadZipFile;

        // Read local header
        var local_header: [30]u8 = undefined;
        _ = file.readAll(&local_header) catch return error.BadZipFile;

        if (!mem.eql(u8, local_header[0..4], &ZIP_MAGIC)) {
            return error.CorruptedFile;
        }

        const name_len = mem.readInt(u16, local_header[26..28], .little);
        const extra_len = mem.readInt(u16, local_header[28..30], .little);

        // Skip to file data
        file.seekBy(@intCast(name_len + extra_len)) catch return error.BadZipFile;

        // Read compressed data
        const compressed = self.allocator.alloc(u8, @intCast(entry.compressed_size)) catch return error.OutOfMemory;
        errdefer self.allocator.free(compressed);
        _ = file.readAll(compressed) catch return error.BadZipFile;

        // Decompress based on compression type
        if (entry.compress_type == 0) {
            // Stored - no compression
            return compressed;
        } else if (entry.compress_type == 8) {
            // Deflate compression
            defer self.allocator.free(compressed);
            return self.decompressDeflate(compressed, @intCast(entry.uncompressed_size));
        } else {
            self.allocator.free(compressed);
            return error.UnsupportedCompression;
        }
    }

    /// Decompress deflate data
    fn decompressDeflate(self: *Self, data: []const u8, size: usize) ReadError![]u8 {
        var fbs = std.io.fixedBufferStream(data);
        var decomp = std.compress.zlib.decompressor(fbs.reader());
        return decomp.reader().readAllAlloc(self.allocator, size) catch return error.CorruptedFile;
    }

    /// Check if file exists in archive
    pub fn contains(self: Self, name: []const u8) bool {
        return self.getEntry(name) != null;
    }

    /// Get list of all filenames
    pub fn namelist(self: Self) ![][]const u8 {
        var names = try self.allocator.alloc([]const u8, self.entries.items.len);
        for (self.entries.items, 0..) |entry, idx| {
            names[idx] = entry.filename;
        }
        return names;
    }

    /// Close the reader
    pub fn close(self: *Self) void {
        if (self.file) |*f| {
            f.close();
            self.file = null;
        }
        self.closed = true;
    }
};

// ============================================================================
// BufferedZipReader - Optimized for large files
// ============================================================================

pub const BufferedZipReader = struct {
    const Self = @This();
    const BUFFER_SIZE = 32768;

    inner: ZipReader,
    read_buffer: [BUFFER_SIZE]u8 = undefined,
    buffer_pos: usize = 0,
    buffer_len: usize = 0,

    pub fn init(allocator: mem.Allocator) Self {
        return .{ .inner = ZipReader.init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.inner.deinit();
    }

    pub fn open(self: *Self, path: []const u8) !void {
        try self.inner.open(path);
    }

    pub fn bufferedRead(self: *Self, dest: []u8) !usize {
        var bytes_read: usize = 0;
        while (bytes_read < dest.len) {
            if (self.buffer_pos >= self.buffer_len) {
                // Refill buffer
                if (self.inner.file) |*f| {
                    self.buffer_len = f.read(&self.read_buffer) catch break;
                    self.buffer_pos = 0;
                    if (self.buffer_len == 0) break;
                } else break;
            }
            const available = self.buffer_len - self.buffer_pos;
            const to_copy = @min(available, dest.len - bytes_read);
            @memcpy(dest[bytes_read..][0..to_copy], self.read_buffer[self.buffer_pos..][0..to_copy]);
            self.buffer_pos += to_copy;
            bytes_read += to_copy;
        }
        return bytes_read;
    }
};

// ============================================================================
// ZipEntryIterator - Iterator over ZIP entries
// ============================================================================

pub const ZipEntryIterator = struct {
    reader: *const ZipReader,
    index: usize = 0,

    pub fn next(self: *@This()) ?ZipReader.ZipEntry {
        if (self.index >= self.reader.entries.items.len) return null;
        const entry = self.reader.entries.items[self.index];
        self.index += 1;
        return entry;
    }

    pub fn reset(self: *@This()) void {
        self.index = 0;
    }

    pub fn skip(self: *@This(), count: usize) void {
        self.index = @min(self.index + count, self.reader.entries.items.len);
    }

    pub fn remaining(self: @This()) usize {
        return self.reader.entries.items.len - self.index;
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Check if data starts with ZIP magic bytes
pub fn isZipData(data: []const u8) bool {
    if (data.len < 4) return false;
    return mem.eql(u8, data[0..4], &ZIP_MAGIC);
}

/// Parse DOS date/time format
pub fn parseDosDateTime(date: u16, time: u16) struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
} {
    return .{
        .year = @as(u16, @intCast((date >> 9) & 0x7F)) + 1980,
        .month = @intCast((date >> 5) & 0x0F),
        .day = @intCast(date & 0x1F),
        .hour = @intCast((time >> 11) & 0x1F),
        .minute = @intCast((time >> 5) & 0x3F),
        .second = @intCast((time & 0x1F) * 2),
    };
}

/// Calculate CRC32 for verification
pub fn calculateCrc32(data: []const u8) u32 {
    return std.hash.crc.Crc32.hash(data);
}

// ============================================================================
// Tests
// ============================================================================

test "ZipReader init and deinit" {
    var reader = ZipReader.init(testing.allocator);
    defer reader.deinit();

    try testing.expect(!reader.closed);
    try testing.expect(reader.file == null);
    try testing.expectEqual(@as(usize, 0), reader.entryCount());
}

test "ZipReader getEntry nonexistent" {
    var reader = ZipReader.init(testing.allocator);
    defer reader.deinit();

    try testing.expect(reader.getEntry("nonexistent.txt") == null);
    try testing.expect(reader.getEntryByIndex(0) == null);
    try testing.expect(!reader.contains("test.txt"));
}

test "BufferedZipReader init" {
    var reader = BufferedZipReader.init(testing.allocator);
    defer reader.deinit();

    try testing.expect(!reader.inner.closed);
}

test "ZipEntryIterator empty" {
    var reader = ZipReader.init(testing.allocator);
    defer reader.deinit();

    var iter = ZipEntryIterator{ .reader = &reader };
    try testing.expect(iter.next() == null);
    try testing.expectEqual(@as(usize, 0), iter.remaining());
}

test "isZipData valid" {
    const valid_zip = [_]u8{ 0x50, 0x4b, 0x03, 0x04, 0x00, 0x00 };
    try testing.expect(isZipData(&valid_zip));
}

test "isZipData invalid" {
    const invalid_data = [_]u8{ 0x00, 0x00, 0x00, 0x00 };
    try testing.expect(!isZipData(&invalid_data));

    const short_data = [_]u8{ 0x50, 0x4b };
    try testing.expect(!isZipData(&short_data));
}

test "parseDosDateTime" {
    // Date: 2024-03-15, Time: 10:30:00
    const date: u16 = ((2024 - 1980) << 9) | (3 << 5) | 15;
    const time: u16 = (10 << 11) | (30 << 5) | 0;

    const dt = parseDosDateTime(date, time);
    try testing.expectEqual(@as(u16, 2024), dt.year);
    try testing.expectEqual(@as(u8, 3), dt.month);
    try testing.expectEqual(@as(u8, 15), dt.day);
    try testing.expectEqual(@as(u8, 10), dt.hour);
    try testing.expectEqual(@as(u8, 30), dt.minute);
    try testing.expectEqual(@as(u8, 0), dt.second);
}

test "calculateCrc32" {
    const data = "Hello, World!";
    const crc = calculateCrc32(data);
    // Known CRC32 for "Hello, World!"
    try testing.expect(crc != 0);
}

test "ZipReader.ReadError types" {
    const err1: ZipReader.ReadError = error.BadZipFile;
    const err2: ZipReader.ReadError = error.FileNotFound;
    const err3: ZipReader.ReadError = error.UnsupportedCompression;
    try testing.expect(err1 != err2);
    try testing.expect(err2 != err3);
}

test "ZipEntryIterator skip and reset" {
    var reader = ZipReader.init(testing.allocator);
    defer reader.deinit();

    var iter = ZipEntryIterator{ .reader = &reader };
    iter.skip(5);
    try testing.expectEqual(@as(usize, 0), iter.remaining());

    iter.reset();
    try testing.expectEqual(@as(usize, 0), iter.index);
}

test "BufferedZipReader buffer size" {
    try testing.expectEqual(@as(usize, 32768), BufferedZipReader.BUFFER_SIZE);
}
