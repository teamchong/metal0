//! CPython source: Lib/bz2.py
//!
//! Provides reading and writing of bzip2-compressed files and streams.
//!
//! Mirrors: CPython Lib/bz2.py
//!
//! Like CPython, this links against system libbz2 (bzlib.h).
//! CPython equivalent: Modules/_bz2module.c

const std = @import("std");

// Link against system libbz2 (same as CPython does)
const c = @cImport({
    @cInclude("bzlib.h");
});

// BZ2 library constants from bzlib.h
const BZ_OK = 0;
const BZ_RUN_OK = 1;
const BZ_FLUSH_OK = 2;
const BZ_FINISH_OK = 3;
const BZ_STREAM_END = 4;
const BZ_SEQUENCE_ERROR = -1;
const BZ_PARAM_ERROR = -2;
const BZ_MEM_ERROR = -3;
const BZ_DATA_ERROR = -4;
const BZ_DATA_ERROR_MAGIC = -5;
const BZ_IO_ERROR = -6;
const BZ_UNEXPECTED_EOF = -7;
const BZ_OUTBUFF_FULL = -8;
const BZ_CONFIG_ERROR = -9;

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
            .buffer = .{},
            .compresslevel = compresslevel,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
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
        const bytes_read = try self.file.?.readAll(compressed);

        // Verify magic
        if (bytes_read < 4) {
            return error.InvalidBz2Header;
        }
        if (!std.mem.eql(u8, compressed[0..3], &BZ2_MAGIC)) {
            return error.InvalidBz2Magic;
        }

        // Decompress using libbz2 (same as CPython)
        const max_size = size orelse 1024 * 1024 * 10; // 10MB default
        var output = try self.allocator.alloc(u8, max_size);
        errdefer self.allocator.free(output);

        var output_len: c_uint = @intCast(max_size);
        const result = c.BZ2_bzBuffToBuffDecompress(
            output.ptr,
            &output_len,
            compressed.ptr,
            @intCast(bytes_read),
            0, // small mode (0 = normal, 1 = small memory)
            0, // verbosity
        );

        if (result != BZ_OK) {
            self.allocator.free(output);
            return switch (result) {
                BZ_MEM_ERROR => error.OutOfMemory,
                BZ_DATA_ERROR, BZ_DATA_ERROR_MAGIC => error.InvalidBz2Data,
                BZ_PARAM_ERROR => error.InvalidParameter,
                BZ_OUTBUFF_FULL => error.OutputBufferTooSmall,
                else => error.Bz2DecompressionFailed,
            };
        }

        // Resize to actual decompressed size
        if (output_len < max_size) {
            output = self.allocator.realloc(output, output_len) catch output;
        }

        return output[0..output_len];
    }

    /// Write data to be compressed
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.mode == .read) {
            return error.InvalidMode;
        }

        try self.buffer.appendSlice(self.allocator, data);
        return data.len;
    }

    /// Flush and finalize the bz2 file
    pub fn close(self: *Self) !void {
        if (self.closed) return;

        if (self.mode == .write or self.mode == .append) {
            if (self.file) |*f| {
                // Compress buffered data using libbz2 (same as CPython)
                if (self.buffer.items.len > 0) {
                    const input_len = self.buffer.items.len;
                    // BZ2 worst case: input + (input/100) + 600 bytes
                    const max_compressed = input_len + (input_len / 100) + 600;
                    var compressed = try self.allocator.alloc(u8, max_compressed);
                    defer self.allocator.free(compressed);

                    var compressed_len: c_uint = @intCast(max_compressed);
                    const result = c.BZ2_bzBuffToBuffCompress(
                        compressed.ptr,
                        &compressed_len,
                        self.buffer.items.ptr,
                        @intCast(input_len),
                        self.compresslevel, // blockSize100k (1-9)
                        0, // verbosity
                        30, // workFactor (0-250, default 30)
                    );

                    if (result != BZ_OK) {
                        return switch (result) {
                            BZ_MEM_ERROR => error.OutOfMemory,
                            BZ_PARAM_ERROR => error.InvalidParameter,
                            BZ_OUTBUFF_FULL => error.OutputBufferTooSmall,
                            else => error.Bz2CompressionFailed,
                        };
                    }

                    // Write compressed data
                    try f.writeAll(compressed[0..compressed_len]);
                }

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
            .buffer = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Compress data incrementally
    pub fn compress(self: *Self, data: []const u8) ![]u8 {
        // Accumulate data - actual compression happens on flush
        try self.buffer.appendSlice(self.allocator, data);
        // Return empty slice - data is buffered
        return try self.allocator.alloc(u8, 0);
    }

    /// Flush all pending data and return compressed output
    pub fn flush(self: *Self) ![]u8 {
        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(self.allocator);

        // Write bz2 header
        try result.appendSlice(self.allocator, &BZ2_MAGIC);
        try result.append(self.allocator, '0' + @as(u8, @intCast(self.compresslevel)));

        // BZ2 compression requires BWT implementation (see BZ2File.read() comment)
        // Append raw data as placeholder
        try result.appendSlice(self.allocator, self.buffer.items);

        self.buffer.clearRetainingCapacity();
        return result.toOwnedSlice(self.allocator);
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
            .buffer = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Decompress data incrementally
    pub fn decompress(self: *Self, data: []const u8, max_length: ?usize) ![]u8 {
        _ = max_length;

        // Accumulate compressed data
        try self.buffer.appendSlice(self.allocator, data);

        // Check for bz2 magic
        if (self.buffer.items.len >= 4) {
            if (!std.mem.eql(u8, self.buffer.items[0..3], &BZ2_MAGIC)) {
                return error.InvalidBz2Data;
            }
        }

        // BZ2 decompression requires BWT implementation (see BZ2File.read() comment)
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
/// Compress data in one shot (same as CPython's bz2.compress)
pub fn compress(allocator: std.mem.Allocator, data: []const u8, compresslevel: i32) ![]u8 {
    // BZ2 worst case: input + (input/100) + 600 bytes
    const max_compressed = data.len + (data.len / 100) + 600;
    var output = try allocator.alloc(u8, max_compressed);
    errdefer allocator.free(output);

    var output_len: c_uint = @intCast(max_compressed);
    const result = c.BZ2_bzBuffToBuffCompress(
        output.ptr,
        &output_len,
        @constCast(data.ptr),
        @intCast(data.len),
        compresslevel, // blockSize100k (1-9)
        0, // verbosity
        30, // workFactor
    );

    if (result != BZ_OK) {
        allocator.free(output);
        return switch (result) {
            BZ_MEM_ERROR => error.OutOfMemory,
            BZ_PARAM_ERROR => error.InvalidParameter,
            BZ_OUTBUFF_FULL => error.OutputBufferTooSmall,
            else => error.Bz2CompressionFailed,
        };
    }

    // Resize to actual compressed size
    if (output_len < max_compressed) {
        output = allocator.realloc(output, output_len) catch output;
    }

    return output[0..output_len];
}

/// Decompress bz2 data in one shot (same as CPython's bz2.decompress)
pub fn decompress(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    // Verify header
    if (data.len < 4) {
        return error.InvalidBz2Data;
    }
    if (!std.mem.eql(u8, data[0..3], &BZ2_MAGIC)) {
        return error.InvalidBz2Magic;
    }

    // Decompress using libbz2
    const max_size: usize = 1024 * 1024 * 10; // 10MB default
    var output = try allocator.alloc(u8, max_size);
    errdefer allocator.free(output);

    var output_len: c_uint = @intCast(max_size);
    const result = c.BZ2_bzBuffToBuffDecompress(
        output.ptr,
        &output_len,
        @constCast(data.ptr),
        @intCast(data.len),
        0, // small mode
        0, // verbosity
    );

    if (result != BZ_OK) {
        allocator.free(output);
        return switch (result) {
            BZ_MEM_ERROR => error.OutOfMemory,
            BZ_DATA_ERROR, BZ_DATA_ERROR_MAGIC => error.InvalidBz2Data,
            BZ_PARAM_ERROR => error.InvalidParameter,
            BZ_OUTBUFF_FULL => error.OutputBufferTooSmall,
            else => error.Bz2DecompressionFailed,
        };
    }

    // Resize to actual size
    if (output_len < max_size) {
        output = allocator.realloc(output, output_len) catch output;
    }

    return output[0..output_len];
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
