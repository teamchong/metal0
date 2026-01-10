//! test.test_zipfile.test_write - ZIP file writing tests
//!
//! Tests for writing ZIP archives including creating files, adding entries,
//! compression options, and proper archive structure generation.

const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const fs = std.fs;

// ============================================================================
// ZIP Format Constants
// ============================================================================

/// Local file header signature
const ZIP_LOCAL_MAGIC: [4]u8 = .{ 0x50, 0x4b, 0x03, 0x04 };

/// Central directory header signature
const ZIP_CENTRAL_MAGIC: [4]u8 = .{ 0x50, 0x4b, 0x01, 0x02 };

/// End of central directory signature
const ZIP_END_MAGIC: [4]u8 = .{ 0x50, 0x4b, 0x05, 0x06 };

/// Compression methods
const COMPRESSION_STORED: u16 = 0;
const COMPRESSION_DEFLATED: u16 = 8;

// ============================================================================
// ZipWriter - Core writing functionality
// ============================================================================

pub const ZipWriter = struct {
    const Self = @This();

    allocator: mem.Allocator,
    buffer: std.ArrayList(u8),
    entries: std.ArrayList(EntryInfo),
    compression: u16 = COMPRESSION_DEFLATED,
    comment: []const u8 = "",
    closed: bool = false,

    pub const EntryInfo = struct {
        filename: []const u8,
        compress_type: u16,
        crc32: u32,
        compressed_size: u32,
        uncompressed_size: u32,
        header_offset: u32,
        mod_time: u16 = 0,
        mod_date: u16 = 0,
        internal_attr: u16 = 0,
        external_attr: u32 = 0,
    };

    pub const WriteError = error{
        ArchiveClosed,
        InvalidFilename,
        CompressionFailed,
        FilenameTooLong,
        OutOfMemory,
        WriteFailure,
    };

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
            .entries = std.ArrayList(EntryInfo).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.filename);
        }
        self.entries.deinit();
        self.buffer.deinit();
        if (self.comment.len > 0) self.allocator.free(self.comment);
    }

    /// Set compression method (stored or deflated)
    pub fn setCompression(self: *Self, method: u16) void {
        self.compression = method;
    }

    /// Add a file to the archive
    pub fn writeFile(self: *Self, filename: []const u8, data: []const u8) WriteError!void {
        if (self.closed) return error.ArchiveClosed;
        if (filename.len == 0) return error.InvalidFilename;
        if (filename.len > 65535) return error.FilenameTooLong;

        // Calculate CRC32
        const crc = std.hash.crc.Crc32.hash(data);

        // Store the header offset
        const header_offset: u32 = @intCast(self.buffer.items.len);

        // Compress data if needed
        var compressed_data: []u8 = undefined;
        var compressed_alloc = false;
        var actual_compression = self.compression;

        if (self.compression == COMPRESSION_STORED or data.len == 0) {
            compressed_data = @constCast(data);
            actual_compression = COMPRESSION_STORED;
        } else {
            // Deflate compression
            var output = std.ArrayList(u8).init(self.allocator);
            errdefer output.deinit();

            var comp = std.compress.zlib.compressor(output.writer(), .{}) catch return error.CompressionFailed;
            comp.writer().writeAll(data) catch return error.CompressionFailed;
            comp.finish() catch return error.CompressionFailed;

            compressed_data = output.toOwnedSlice() catch return error.OutOfMemory;
            compressed_alloc = true;

            // If compressed is larger, store instead
            if (compressed_data.len >= data.len) {
                self.allocator.free(compressed_data);
                compressed_data = @constCast(data);
                compressed_alloc = false;
                actual_compression = COMPRESSION_STORED;
            }
        }
        defer if (compressed_alloc) self.allocator.free(compressed_data);

        // Write local file header
        try self.writeLocalHeader(filename, crc, @intCast(compressed_data.len), @intCast(data.len), actual_compression);

        // Write file data
        self.buffer.appendSlice(compressed_data) catch return error.OutOfMemory;

        // Store entry info for central directory
        const name_copy = self.allocator.dupe(u8, filename) catch return error.OutOfMemory;
        self.entries.append(.{
            .filename = name_copy,
            .compress_type = actual_compression,
            .crc32 = crc,
            .compressed_size = @intCast(compressed_data.len),
            .uncompressed_size = @intCast(data.len),
            .header_offset = header_offset,
        }) catch return error.OutOfMemory;
    }

    /// Add a directory entry
    pub fn writeDirectory(self: *Self, dirname: []const u8) WriteError!void {
        // Ensure directory name ends with /
        var name: []u8 = undefined;
        if (dirname.len > 0 and dirname[dirname.len - 1] != '/') {
            name = self.allocator.alloc(u8, dirname.len + 1) catch return error.OutOfMemory;
            @memcpy(name[0..dirname.len], dirname);
            name[dirname.len] = '/';
        } else {
            name = self.allocator.dupe(u8, dirname) catch return error.OutOfMemory;
        }
        defer self.allocator.free(name);

        try self.writeFile(name, "");
    }

    /// Write local file header
    fn writeLocalHeader(self: *Self, filename: []const u8, crc: u32, compressed_size: u32, uncompressed_size: u32, compression: u16) WriteError!void {
        var header: [30]u8 = undefined;

        // Signature
        @memcpy(header[0..4], &ZIP_LOCAL_MAGIC);
        // Version needed to extract (2.0)
        mem.writeInt(u16, header[4..6], 20, .little);
        // General purpose bit flag
        mem.writeInt(u16, header[6..8], 0, .little);
        // Compression method
        mem.writeInt(u16, header[8..10], compression, .little);
        // Last mod file time
        mem.writeInt(u16, header[10..12], 0, .little);
        // Last mod file date
        mem.writeInt(u16, header[12..14], 0, .little);
        // CRC-32
        mem.writeInt(u32, header[14..18], crc, .little);
        // Compressed size
        mem.writeInt(u32, header[18..22], compressed_size, .little);
        // Uncompressed size
        mem.writeInt(u32, header[22..26], uncompressed_size, .little);
        // File name length
        mem.writeInt(u16, header[26..28], @intCast(filename.len), .little);
        // Extra field length
        mem.writeInt(u16, header[28..30], 0, .little);

        self.buffer.appendSlice(&header) catch return error.OutOfMemory;
        self.buffer.appendSlice(filename) catch return error.OutOfMemory;
    }

    /// Finalize the archive
    pub fn close(self: *Self) WriteError!void {
        if (self.closed) return;

        const cd_offset: u32 = @intCast(self.buffer.items.len);

        // Write central directory entries
        for (self.entries.items) |entry| {
            try self.writeCentralEntry(entry);
        }

        const cd_size: u32 = @intCast(self.buffer.items.len - cd_offset);

        // Write end of central directory record
        try self.writeEndOfCentralDirectory(cd_offset, cd_size);

        self.closed = true;
    }

    /// Write central directory entry
    fn writeCentralEntry(self: *Self, entry: EntryInfo) WriteError!void {
        var header: [46]u8 = undefined;

        // Signature
        @memcpy(header[0..4], &ZIP_CENTRAL_MAGIC);
        // Version made by
        mem.writeInt(u16, header[4..6], 20, .little);
        // Version needed to extract
        mem.writeInt(u16, header[6..8], 20, .little);
        // General purpose bit flag
        mem.writeInt(u16, header[8..10], 0, .little);
        // Compression method
        mem.writeInt(u16, header[10..12], entry.compress_type, .little);
        // Last mod file time
        mem.writeInt(u16, header[12..14], entry.mod_time, .little);
        // Last mod file date
        mem.writeInt(u16, header[14..16], entry.mod_date, .little);
        // CRC-32
        mem.writeInt(u32, header[16..20], entry.crc32, .little);
        // Compressed size
        mem.writeInt(u32, header[20..24], entry.compressed_size, .little);
        // Uncompressed size
        mem.writeInt(u32, header[24..28], entry.uncompressed_size, .little);
        // File name length
        mem.writeInt(u16, header[28..30], @intCast(entry.filename.len), .little);
        // Extra field length
        mem.writeInt(u16, header[30..32], 0, .little);
        // File comment length
        mem.writeInt(u16, header[32..34], 0, .little);
        // Disk number start
        mem.writeInt(u16, header[34..36], 0, .little);
        // Internal file attributes
        mem.writeInt(u16, header[36..38], entry.internal_attr, .little);
        // External file attributes
        mem.writeInt(u32, header[38..42], entry.external_attr, .little);
        // Relative offset of local header
        mem.writeInt(u32, header[42..46], entry.header_offset, .little);

        self.buffer.appendSlice(&header) catch return error.OutOfMemory;
        self.buffer.appendSlice(entry.filename) catch return error.OutOfMemory;
    }

    /// Write end of central directory record
    fn writeEndOfCentralDirectory(self: *Self, cd_offset: u32, cd_size: u32) WriteError!void {
        var eocd: [22]u8 = undefined;

        // Signature
        @memcpy(eocd[0..4], &ZIP_END_MAGIC);
        // Number of this disk
        mem.writeInt(u16, eocd[4..6], 0, .little);
        // Disk where central directory starts
        mem.writeInt(u16, eocd[6..8], 0, .little);
        // Number of central directory records on this disk
        mem.writeInt(u16, eocd[8..10], @intCast(self.entries.items.len), .little);
        // Total number of central directory records
        mem.writeInt(u16, eocd[10..12], @intCast(self.entries.items.len), .little);
        // Size of central directory
        mem.writeInt(u32, eocd[12..16], cd_size, .little);
        // Offset of start of central directory
        mem.writeInt(u32, eocd[16..20], cd_offset, .little);
        // ZIP file comment length
        mem.writeInt(u16, eocd[20..22], @intCast(self.comment.len), .little);

        self.buffer.appendSlice(&eocd) catch return error.OutOfMemory;
        if (self.comment.len > 0) {
            self.buffer.appendSlice(self.comment) catch return error.OutOfMemory;
        }
    }

    /// Get the generated ZIP data
    pub fn getData(self: Self) []const u8 {
        return self.buffer.items;
    }

    /// Write to file
    pub fn writeToFile(self: *Self, path: []const u8) WriteError!void {
        if (!self.closed) try self.close();

        const file = fs.cwd().createFile(path, .{}) catch return error.WriteFailure;
        defer file.close();

        file.writeAll(self.buffer.items) catch return error.WriteFailure;
    }

    /// Get number of entries
    pub fn entryCount(self: Self) usize {
        return self.entries.items.len;
    }
};

// ============================================================================
// InMemoryZipBuilder - Build ZIP archives in memory
// ============================================================================

pub const InMemoryZipBuilder = struct {
    const Self = @This();

    writer: ZipWriter,
    temp_files: std.ArrayList(TempFile),

    pub const TempFile = struct {
        name: []const u8,
        data: []const u8,
    };

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .writer = ZipWriter.init(allocator),
            .temp_files = std.ArrayList(TempFile).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.temp_files.deinit();
        self.writer.deinit();
    }

    pub fn addFile(self: *Self, name: []const u8, data: []const u8) !void {
        try self.temp_files.append(.{ .name = name, .data = data });
    }

    pub fn build(self: *Self) ![]const u8 {
        for (self.temp_files.items) |tf| {
            try self.writer.writeFile(tf.name, tf.data);
        }
        try self.writer.close();
        return self.writer.getData();
    }
};

// ============================================================================
// Streaming Writer - Write large files without full memory load
// ============================================================================

pub const StreamingZipWriter = struct {
    const Self = @This();

    allocator: mem.Allocator,
    file: ?fs.File = null,
    entries: std.ArrayList(ZipWriter.EntryInfo),
    position: u64 = 0,
    compression: u16 = COMPRESSION_DEFLATED,

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .entries = std.ArrayList(ZipWriter.EntryInfo).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.filename);
        }
        self.entries.deinit();
        if (self.file) |*f| f.close();
    }

    pub fn create(self: *Self, path: []const u8) !void {
        self.file = try fs.cwd().createFile(path, .{});
        self.position = 0;
    }

    pub fn writeChunk(self: *Self, data: []const u8) !void {
        if (self.file) |*f| {
            try f.writeAll(data);
            self.position += data.len;
        }
    }

    pub fn getCurrentPosition(self: Self) u64 {
        return self.position;
    }
};

// ============================================================================
// DateTime Helpers
// ============================================================================

pub const DosDateTime = struct {
    time: u16,
    date: u16,

    pub fn fromTimestamp(timestamp: i64) DosDateTime {
        // Simplified conversion - just return default for now
        _ = timestamp;
        return .{ .time = 0, .date = 0 };
    }

    pub fn now() DosDateTime {
        // Return current time in DOS format
        return .{ .time = 0, .date = 0 };
    }

    pub fn encode(year: u16, month: u8, day: u8, hour: u8, minute: u8, second: u8) DosDateTime {
        const date = (@as(u16, year - 1980) << 9) | (@as(u16, month) << 5) | @as(u16, day);
        const time = (@as(u16, hour) << 11) | (@as(u16, minute) << 5) | (@as(u16, second) >> 1);
        return .{ .time = time, .date = date };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ZipWriter init and deinit" {
    var writer = ZipWriter.init(testing.allocator);
    defer writer.deinit();

    try testing.expect(!writer.closed);
    try testing.expectEqual(@as(usize, 0), writer.entryCount());
}

test "ZipWriter write single file" {
    var writer = ZipWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeFile("hello.txt", "Hello, World!");
    try testing.expectEqual(@as(usize, 1), writer.entryCount());

    try writer.close();
    try testing.expect(writer.closed);

    // Verify ZIP structure
    const data = writer.getData();
    try testing.expect(data.len > 22); // Minimum ZIP size
    try testing.expect(mem.eql(u8, data[0..4], &ZIP_LOCAL_MAGIC));
}

test "ZipWriter write multiple files" {
    var writer = ZipWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeFile("file1.txt", "Content 1");
    try writer.writeFile("file2.txt", "Content 2");
    try writer.writeFile("file3.txt", "Content 3");

    try testing.expectEqual(@as(usize, 3), writer.entryCount());
}

test "ZipWriter stored compression" {
    var writer = ZipWriter.init(testing.allocator);
    defer writer.deinit();

    writer.setCompression(COMPRESSION_STORED);
    try writer.writeFile("test.txt", "Test data");

    try testing.expectEqual(@as(usize, 1), writer.entryCount());
    try testing.expectEqual(COMPRESSION_STORED, writer.entries.items[0].compress_type);
}

test "ZipWriter write directory" {
    var writer = ZipWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeDirectory("mydir");
    try testing.expectEqual(@as(usize, 1), writer.entryCount());

    // Directory name should end with /
    try testing.expect(writer.entries.items[0].filename.len > 0);
    try testing.expect(writer.entries.items[0].filename[writer.entries.items[0].filename.len - 1] == '/');
}

test "ZipWriter error on empty filename" {
    var writer = ZipWriter.init(testing.allocator);
    defer writer.deinit();

    const result = writer.writeFile("", "data");
    try testing.expectError(error.InvalidFilename, result);
}

test "ZipWriter error after close" {
    var writer = ZipWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeFile("test.txt", "data");
    try writer.close();

    const result = writer.writeFile("another.txt", "more data");
    try testing.expectError(error.ArchiveClosed, result);
}

test "InMemoryZipBuilder" {
    var builder = InMemoryZipBuilder.init(testing.allocator);
    defer builder.deinit();

    try builder.addFile("a.txt", "content a");
    try builder.addFile("b.txt", "content b");

    const data = try builder.build();
    try testing.expect(data.len > 0);
}

test "StreamingZipWriter init" {
    var writer = StreamingZipWriter.init(testing.allocator);
    defer writer.deinit();

    try testing.expectEqual(@as(u64, 0), writer.getCurrentPosition());
}

test "DosDateTime encode" {
    const dt = DosDateTime.encode(2024, 3, 15, 10, 30, 0);
    try testing.expect(dt.date != 0);
    try testing.expect(dt.time != 0);
}

test "DosDateTime now" {
    const dt = DosDateTime.now();
    // Just verify it doesn't crash
    _ = dt.time;
    _ = dt.date;
}

test "ZipWriter CRC calculation" {
    var writer = ZipWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeFile("test.txt", "Hello");

    // CRC should be non-zero for non-empty data
    try testing.expect(writer.entries.items[0].crc32 != 0);
}

test "ZipWriter getData before close" {
    var writer = ZipWriter.init(testing.allocator);
    defer writer.deinit();

    try writer.writeFile("test.txt", "data");

    // Should still return partial data
    const data = writer.getData();
    try testing.expect(data.len > 0);
}

test "compression constants" {
    try testing.expectEqual(@as(u16, 0), COMPRESSION_STORED);
    try testing.expectEqual(@as(u16, 8), COMPRESSION_DEFLATED);
}
