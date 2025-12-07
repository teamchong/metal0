//! CPython source: Lib/lzma.py
//!
//! Provides reading and writing of LZMA/XZ-compressed files and streams.
//!
//! Mirrors: CPython Lib/lzma.py

const std = @import("std");

// ============================================================================
// Constants
// ============================================================================

/// Check types for integrity verification
pub const CHECK = enum(u8) {
    NONE = 0,
    CRC32 = 1,
    CRC64 = 4,
    SHA256 = 10,
};

/// Default check type
pub const CHECK_UNKNOWN: i32 = -1;

/// LZMA format identifiers
pub const FORMAT_AUTO = 0;
pub const FORMAT_XZ = 1;
pub const FORMAT_ALONE = 2;
pub const FORMAT_RAW = 3;

/// Compression presets (0-9)
pub const PRESET_DEFAULT = 6;
pub const PRESET_EXTREME: u32 = 1 << 31;

/// XZ magic bytes
pub const XZ_MAGIC: [6]u8 = .{ 0xFD, '7', 'z', 'X', 'Z', 0x00 };

/// LZMA alone magic byte
pub const LZMA_MAGIC: [1]u8 = .{0x5D};

// ============================================================================
// LZMAFile - Main LZMA file handler
// ============================================================================

/// A file-like object for reading/writing LZMA-compressed data
pub const LZMAFile = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    mode: Mode,
    name: ?[]const u8 = null,
    file: ?std.fs.File = null,
    buffer: std.ArrayList(u8),
    format: i32,
    check: CHECK,
    preset: ?u32,
    closed: bool = false,

    pub const Mode = enum {
        read,
        write,
        append,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        mode: Mode,
        format: i32,
        check: CHECK,
        preset: ?u32,
    ) Self {
        return .{
            .allocator = allocator,
            .mode = mode,
            .buffer = std.ArrayList(u8).init(allocator),
            .format = format,
            .check = check,
            .preset = preset,
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
        if (self.file) |*f| {
            f.close();
        }
    }

    /// Open an LZMA file
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

        // Read compressed data
        const file_size = try self.file.?.getEndPos();
        var compressed = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(compressed);
        _ = try self.file.?.readAll(compressed);

        // Check format
        if (compressed.len >= 6 and std.mem.eql(u8, compressed[0..6], &XZ_MAGIC)) {
            // XZ format - use std.compress.xz
            var fbs = std.io.fixedBufferStream(compressed);
            var decomp = std.compress.xz.decompress(self.allocator, fbs.reader()) catch
                return error.LzmaDecompressError;

            const max_size = size orelse 1024 * 1024 * 10;
            return decomp.reader().readAllAlloc(self.allocator, max_size) catch
                return error.LzmaDecompressError;
        } else if (compressed.len >= 1 and compressed[0] == LZMA_MAGIC[0]) {
            // LZMA alone format
            return error.LzmaAloneNotImplemented;
        } else {
            return error.InvalidLzmaFormat;
        }
    }

    /// Write data to be compressed
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.mode == .read) {
            return error.InvalidMode;
        }

        try self.buffer.appendSlice(data);
        return data.len;
    }

    /// Flush and finalize the LZMA file
    pub fn close(self: *Self) !void {
        if (self.closed) return;

        if (self.mode == .write or self.mode == .append) {
            if (self.file) |*f| {
                // Compress and write
                var compressed = std.ArrayList(u8).init(self.allocator);
                defer compressed.deinit();

                // Use XZ format
                var comp = try std.compress.xz.compressor(compressed.writer(), self.allocator, .{});
                try comp.write(self.buffer.items);
                try comp.finish();

                try f.writeAll(compressed.items);

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
};

// ============================================================================
// LZMACompressor - Incremental compressor
// ============================================================================

/// Incremental LZMA compressor
pub const LZMACompressor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    format: i32,
    check: CHECK,
    preset: ?u32,
    buffer: std.ArrayList(u8),

    pub fn init(
        allocator: std.mem.Allocator,
        format: i32,
        check: CHECK,
        preset: ?u32,
    ) Self {
        return .{
            .allocator = allocator,
            .format = format,
            .check = check,
            .preset = preset,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    /// Compress data incrementally
    pub fn compress(self: *Self, data: []const u8) ![]u8 {
        try self.buffer.appendSlice(data);
        // Data is buffered until flush
        return try self.allocator.alloc(u8, 0);
    }

    /// Flush all pending data and return compressed output
    pub fn flush(self: *Self) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        // Compress using XZ format
        var comp = try std.compress.xz.compressor(result.writer(), self.allocator, .{});
        try comp.write(self.buffer.items);
        try comp.finish();

        self.buffer.clearRetainingCapacity();
        return result.toOwnedSlice();
    }
};

// ============================================================================
// LZMADecompressor - Incremental decompressor
// ============================================================================

/// Incremental LZMA decompressor
pub const LZMADecompressor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    format: i32,
    buffer: std.ArrayList(u8),
    eof: bool = false,
    needs_input: bool = true,
    unused_data: []const u8 = "",
    check: CHECK = .NONE,

    pub fn init(allocator: std.mem.Allocator, format: i32) Self {
        return .{
            .allocator = allocator,
            .format = format,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    /// Decompress data incrementally
    pub fn decompress(self: *Self, data: []const u8, max_length: ?usize) ![]u8 {
        try self.buffer.appendSlice(data);

        // Need enough data to determine format
        if (self.buffer.items.len < 6) {
            self.needs_input = true;
            return try self.allocator.alloc(u8, 0);
        }

        // Check format and decompress
        if (std.mem.eql(u8, self.buffer.items[0..6], &XZ_MAGIC)) {
            var fbs = std.io.fixedBufferStream(self.buffer.items);
            var decomp = std.compress.xz.decompress(self.allocator, fbs.reader()) catch {
                self.needs_input = true;
                return try self.allocator.alloc(u8, 0);
            };

            const max_size = max_length orelse 1024 * 1024 * 10;
            const result = decomp.reader().readAllAlloc(self.allocator, max_size) catch {
                self.needs_input = true;
                return try self.allocator.alloc(u8, 0);
            };

            self.eof = true;
            self.needs_input = false;
            self.buffer.clearRetainingCapacity();
            return result;
        }

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

    /// Get the integrity check type
    pub fn getCheck(self: Self) CHECK {
        return self.check;
    }
};

// ============================================================================
// Convenience Functions
// ============================================================================

/// Open an LZMA file for reading or writing
pub fn openLzma(
    allocator: std.mem.Allocator,
    filename: []const u8,
    mode: []const u8,
    format: i32,
    check: CHECK,
    preset: ?u32,
) !LZMAFile {
    const lzma_mode: LZMAFile.Mode = if (std.mem.eql(u8, mode, "rb") or std.mem.eql(u8, mode, "r"))
        .read
    else if (std.mem.eql(u8, mode, "wb") or std.mem.eql(u8, mode, "w"))
        .write
    else if (std.mem.eql(u8, mode, "ab") or std.mem.eql(u8, mode, "a"))
        .append
    else
        return error.InvalidMode;

    var lf = LZMAFile.init(allocator, lzma_mode, format, check, preset);
    try lf.open(filename);
    return lf;
}

/// Compress data in one shot
pub fn compress(allocator: std.mem.Allocator, data: []const u8, format: i32, check: CHECK, preset: ?u32) ![]u8 {
    _ = format;
    _ = check;
    _ = preset;

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var comp = try std.compress.xz.compressor(result.writer(), allocator, .{});
    try comp.write(data);
    try comp.finish();

    return result.toOwnedSlice();
}

/// Decompress LZMA data in one shot
pub fn decompress(allocator: std.mem.Allocator, data: []const u8, format: i32, max_length: ?usize) ![]u8 {
    _ = format;

    // Verify XZ magic
    if (data.len < 6 or !std.mem.eql(u8, data[0..6], &XZ_MAGIC)) {
        return error.InvalidLzmaData;
    }

    var fbs = std.io.fixedBufferStream(data);
    var decomp = std.compress.xz.decompress(allocator, fbs.reader()) catch
        return error.LzmaDecompressError;

    const max_size = max_length orelse 1024 * 1024 * 100;
    return decomp.reader().readAllAlloc(allocator, max_size) catch
        return error.LzmaDecompressError;
}

/// Check if LZMA/XZ format is supported
pub fn isCheckSupported(check: CHECK) bool {
    return switch (check) {
        .NONE, .CRC32, .CRC64 => true,
        .SHA256 => false, // May not be supported
    };
}

// ============================================================================
// Filters (for advanced usage)
// ============================================================================

pub const Filter = struct {
    id: FilterId,
    options: ?FilterOptions = null,

    pub const FilterId = enum(u64) {
        LZMA1 = 0x4000000000000001,
        LZMA2 = 0x21,
        DELTA = 0x03,
        X86 = 0x04,
        IA64 = 0x06,
        ARM = 0x07,
        ARMTHUMB = 0x08,
        SPARC = 0x09,
        POWERPC = 0x05,
    };

    pub const FilterOptions = struct {
        preset: ?u32 = null,
        dict_size: ?u32 = null,
        lc: ?u32 = null,
        lp: ?u32 = null,
        pb: ?u32 = null,
        mode: ?u32 = null,
        nice_len: ?u32 = null,
        mf: ?[]const u8 = null,
        depth: ?u32 = null,
        dist: ?u32 = null,
    };
};

// ============================================================================
// LZMAError
// ============================================================================

pub const LZMAError = error{
    InvalidLzmaFormat,
    InvalidLzmaData,
    LzmaDecompressError,
    LzmaAloneNotImplemented,
    UnsupportedCheck,
};

// ============================================================================
// Tests
// ============================================================================

test "LZMAFile init" {
    const allocator = std.testing.allocator;

    var lf = LZMAFile.init(allocator, .write, FORMAT_XZ, .CRC64, PRESET_DEFAULT);
    defer lf.deinit();

    try std.testing.expect(!lf.closed);
    try std.testing.expectEqual(LZMAFile.Mode.write, lf.mode);
}

test "LZMACompressor and LZMADecompressor" {
    const allocator = std.testing.allocator;

    var comp = LZMACompressor.init(allocator, FORMAT_XZ, .CRC64, PRESET_DEFAULT);
    defer comp.deinit();

    const empty = try comp.compress("Hello, LZMA!");
    defer allocator.free(empty);

    const compressed = try comp.flush();
    defer allocator.free(compressed);

    // Should start with XZ magic
    try std.testing.expectEqualSlices(u8, &XZ_MAGIC, compressed[0..6]);
}

test "compress and decompress" {
    const allocator = std.testing.allocator;

    const original = "Hello, LZMA! This is a test of XZ compression.";
    const compressed = try compress(allocator, original, FORMAT_XZ, .CRC64, PRESET_DEFAULT);
    defer allocator.free(compressed);

    // Verify XZ magic
    try std.testing.expectEqualSlices(u8, &XZ_MAGIC, compressed[0..6]);

    const decompressed = try decompress(allocator, compressed, FORMAT_AUTO, null);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "isCheckSupported" {
    try std.testing.expect(isCheckSupported(.NONE));
    try std.testing.expect(isCheckSupported(.CRC32));
    try std.testing.expect(isCheckSupported(.CRC64));
}

test "constants" {
    try std.testing.expectEqual(@as(u8, 0xFD), XZ_MAGIC[0]);
    try std.testing.expectEqual(@as(i32, 6), PRESET_DEFAULT);
}
