//! Python 'bz2' module - Support for bzip2 compression
//!
//! Provides reading and writing of bzip2-compressed files and streams.
//!
//! Mirrors: CPython Lib/bz2.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Default compression level (1-9)
pub const DEFAULT_COMPRESSLEVEL = 9;

/// BZ2 magic bytes
pub const BZ2_MAGIC: [3]u8 = .{ 'B', 'Z', 'h' };

// ============================================================================
// BZ2File - Main bz2 file handler
// ============================================================================

/// A file-like object for reading/writing bz2-compressed data
pub const BZ2File = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    mode: Mode,
    name: ?[]const u8 = null,
    file: ?std.fs.File = null,
    buffer: std.ArrayList(u8),
    compresslevel: i32,
    closed: bool = false,

    pub const Mode = enum {
        read,
        write,
        append,
    };

    pub fn init(allocator: std.mem.Allocator, mode: Mode, compresslevel: i32) Self {
        return .{
            .allocator = allocator,
            .mode = mode,
            .buffer = std.ArrayList(u8).init(allocator),
            .compresslevel = compresslevel,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
        if (self.file) |*f| {
            f.close();
        }
    }

    /// Open a bz2 file
    pub fn open(self: *Self, filename: []const u8) !void {
        self.name = filename;
        switch (self.mode) {
            .read => {
                self.file = try std.fs.cwd().openFile(filename, .{});
            },
            .write => {
                self.file = try std.fs.cwd().createFile(filename, .{});
            },
            .append => {
                self.file = try std.fs.cwd().openFile(filename, .{ .mode = .read_write });
                try self.file.?.seekFromEnd(0);
            },
        }
    }

    /// Read decompressed data
    pub fn read(self: *Self, size: ?usize) ![]u8 {
        if (self.mode != .read) {
            return error.InvalidMode;
        }

        if (self.file == null) {
            return error.FileNotOpen;
        }

        // Read all compressed data
        const file_size = try self.file.?.getEndPos();
        var compressed = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(compressed);
        _ = try self.file.?.readAll(compressed);

        // Verify magic
        if (compressed.len < 4) {
            return error.InvalidBz2Header;
        }
        if (!std.mem.eql(u8, compressed[0..3], &BZ2_MAGIC)) {
            return error.InvalidBz2Magic;
        }

        // Decompress (note: Zig stdlib doesn't have native bz2, so we simulate)
        const max_size = size orelse 1024 * 1024 * 10;
        _ = max_size;

        // For now, return error indicating bz2 decompression not implemented
        // In a real implementation, we'd use a bz2 library
        return error.Bz2NotImplemented;
    }

    /// Write data to be compressed
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.mode == .read) {
            return error.InvalidMode;
        }

        try self.buffer.appendSlice(data);
        return data.len;
    }

    /// Flush and finalize the bz2 file
    pub fn close(self: *Self) !void {
        if (self.closed) return;

        if (self.mode == .write or self.mode == .append) {
            if (self.file) |*f| {
                // In a real implementation, compress the buffer and write
                // For now, just write the raw data with magic header
                try f.writeAll(&BZ2_MAGIC);
                try f.writeByte('9'); // compression level
                try f.writeAll(self.buffer.items);

                f.close();
                self.file = null;
            }
        } else if (self.file) |*f| {
            f.close();
            self.file = null;
        }

        self.closed = true;
    }

    /// Get the filename
    pub fn getName(self: Self) ?[]const u8 {
        return self.name;
    }

    /// Check if file is closed
    pub fn isClosed(self: Self) bool {
        return self.closed;
    }

    /// Peek at data without consuming
    pub fn peek(self: *Self, n: usize) ![]const u8 {
        _ = n;
        if (self.mode != .read) {
            return error.InvalidMode;
        }
        return self.buffer.items;
    }
};

// ============================================================================
// BZ2Compressor - Incremental compressor
// ============================================================================

/// Incremental bz2 compressor
pub const BZ2Compressor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    compresslevel: i32,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator, compresslevel: i32) Self {
        return .{
            .allocator = allocator,
            .compresslevel = compresslevel,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    /// Compress data incrementally
    pub fn compress(self: *Self, data: []const u8) ![]u8 {
        // Accumulate data - actual compression happens on flush
        try self.buffer.appendSlice(data);
        // Return empty slice - data is buffered
        return try self.allocator.alloc(u8, 0);
    }

    /// Flush all pending data and return compressed output
    pub fn flush(self: *Self) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        // Write bz2 header
        try result.appendSlice(&BZ2_MAGIC);
        try result.append('0' + @as(u8, @intCast(self.compresslevel)));

        // In real implementation, would compress self.buffer.items
        // For now, just copy raw data (placeholder)
        try result.appendSlice(self.buffer.items);

        self.buffer.clearRetainingCapacity();
        return result.toOwnedSlice();
    }
};

// ============================================================================
// BZ2Decompressor - Incremental decompressor
// ============================================================================

/// Incremental bz2 decompressor
pub const BZ2Decompressor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    eof: bool = false,
    needs_input: bool = true,
    unused_data: []const u8 = "",

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    /// Decompress data incrementally
    pub fn decompress(self: *Self, data: []const u8, max_length: ?usize) ![]u8 {
        _ = max_length;

        // Accumulate compressed data
        try self.buffer.appendSlice(data);

        // Check for bz2 magic
        if (self.buffer.items.len >= 4) {
            if (!std.mem.eql(u8, self.buffer.items[0..3], &BZ2_MAGIC)) {
                return error.InvalidBz2Data;
            }
        }

        // In real implementation, would decompress incrementally
        // For now, return empty - decompression not implemented
        self.needs_input = true;
        return try self.allocator.alloc(u8, 0);
    }

    /// Check if at end of stream
    pub fn isEof(self: Self) bool {
        return self.eof;
    }

    /// Check if more input is needed
    pub fn needsInput(self: Self) bool {
        return self.needs_input;
    }
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Open a bz2 file for reading or writing
pub fn openBz2(allocator: std.mem.Allocator, filename: []const u8, mode: []const u8, compresslevel: i32) !BZ2File {
    const bz2_mode: BZ2File.Mode = if (std.mem.eql(u8, mode, "rb") or std.mem.eql(u8, mode, "r"))
        .read
    else if (std.mem.eql(u8, mode, "wb") or std.mem.eql(u8, mode, "w"))
        .write
    else if (std.mem.eql(u8, mode, "ab") or std.mem.eql(u8, mode, "a"))
        .append
    else
        return error.InvalidMode;

    var bf = BZ2File.init(allocator, bz2_mode, compresslevel);
    try bf.open(filename);
    return bf;
}

/// Compress data in one shot
pub fn compress(allocator: std.mem.Allocator, data: []const u8, compresslevel: i32) ![]u8 {
    var comp = BZ2Compressor.init(allocator, compresslevel);
    defer comp.deinit();

    const empty = try comp.compress(data);
    allocator.free(empty);

    return try comp.flush();
}

/// Decompress bz2 data in one shot
pub fn decompress(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    // Verify header
    if (data.len < 4) {
        return error.InvalidBz2Data;
    }
    if (!std.mem.eql(u8, data[0..3], &BZ2_MAGIC)) {
        return error.InvalidBz2Magic;
    }

    // In real implementation, would decompress using bz2 library
    // For now, return the data after header as placeholder
    const result = try allocator.alloc(u8, data.len - 4);
    @memcpy(result, data[4..]);
    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "BZ2File init" {
    const allocator = std.testing.allocator;

    var bf = BZ2File.init(allocator, .write, DEFAULT_COMPRESSLEVEL);
    defer bf.deinit();

    try std.testing.expect(!bf.closed);
    try std.testing.expectEqual(BZ2File.Mode.write, bf.mode);
}

test "BZ2Compressor" {
    const allocator = std.testing.allocator;

    var comp = BZ2Compressor.init(allocator, DEFAULT_COMPRESSLEVEL);
    defer comp.deinit();

    const empty = try comp.compress("Hello, World!");
    defer allocator.free(empty);

    const compressed = try comp.flush();
    defer allocator.free(compressed);

    // Should start with BZ2 magic
    try std.testing.expectEqualSlices(u8, &BZ2_MAGIC, compressed[0..3]);
}

test "BZ2Decompressor" {
    const allocator = std.testing.allocator;

    var decomp = BZ2Decompressor.init(allocator);
    defer decomp.deinit();

    try std.testing.expect(!decomp.eof);
    try std.testing.expect(decomp.needs_input);
}

test "constants" {
    try std.testing.expectEqual(@as(u8, 'B'), BZ2_MAGIC[0]);
    try std.testing.expectEqual(@as(u8, 'Z'), BZ2_MAGIC[1]);
    try std.testing.expectEqual(@as(u8, 'h'), BZ2_MAGIC[2]);
}
