/// Internal classes used by the gzip, lzma and bz2 modules
/// Ported from CPython Lib/_compression.py
const std = @import("std");

// Compressed data read chunk size
pub const BUFFER_SIZE: usize = 8192; // io.DEFAULT_BUFFER_SIZE

/// Mode-checking helper functions for compression streams
pub const BaseStream = struct {
    closed: bool = false,
    _readable: bool = false,
    _writable: bool = false,
    _seekable: bool = false,

    pub fn init(can_read: bool, can_write: bool, can_seek: bool) @This() {
        return .{
            .closed = false,
            ._readable = can_read,
            ._writable = can_write,
            ._seekable = can_seek,
        };
    }

    pub fn _check_not_closed(self: *const @This()) !void {
        if (self.closed) {
            return error.ValueError; // "I/O operation on closed file"
        }
    }

    pub fn _check_can_read(self: *const @This()) !void {
        if (!self.readable()) {
            return error.UnsupportedOperation; // "File not open for reading"
        }
    }

    pub fn _check_can_write(self: *const @This()) !void {
        if (!self.writable()) {
            return error.UnsupportedOperation; // "File not open for writing"
        }
    }

    pub fn _check_can_seek(self: *const @This()) !void {
        if (!self.readable()) {
            return error.UnsupportedOperation; // "Seeking is only supported on files open for reading"
        }
        if (!self.seekable()) {
            return error.UnsupportedOperation; // "The underlying file object does not support seeking"
        }
    }

    pub fn readable(self: *const @This()) bool {
        return self._readable;
    }

    pub fn writable(self: *const @This()) bool {
        return self._writable;
    }

    pub fn seekable(self: *const @This()) bool {
        return self._seekable;
    }
};

/// Adapts the decompressor API to a RawIOBase reader API
/// This is a minimal stub - full implementation would require decompressor integration
pub const DecompressReader = struct {
    fp: ?*anyopaque = null, // File pointer (opaque for now)
    eof: bool = false,
    pos: usize = 0, // Current offset in decompressed stream
    size: i64 = -1, // Size of decompressed stream (-1 = unknown)
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, fp: ?*anyopaque) @This() {
        return .{
            .fp = fp,
            .eof = false,
            .pos = 0,
            .size = -1,
            .allocator = allocator,
        };
    }

    pub fn readable(_: *const @This()) bool {
        return true;
    }

    pub fn seekable(_: *const @This()) bool {
        // Would check if underlying fp is seekable
        return false; // Stub: assume not seekable
    }

    pub fn read(self: *@This(), size: i64) ![]u8 {
        _ = size;
        if (self.eof) {
            return &[_]u8{};
        }
        // Stub: minimal implementation
        // Full version would call decompressor.decompress()
        return error.NotImplemented;
    }

    pub fn readall(self: *@This()) ![]u8 {
        var chunks = std.ArrayList(u8).init(self.allocator);
        defer chunks.deinit();

        // Stub: would read until EOF
        // while (const data = try self.read(std.math.maxInt(i64))) {
        //     try chunks.appendSlice(data);
        // }

        return chunks.toOwnedSlice();
    }

    pub fn close(self: *@This()) void {
        self.fp = null;
        self.eof = true;
    }

    pub fn _rewind(self: *@This()) void {
        // Would seek fp to beginning
        self.eof = false;
        self.pos = 0;
        // Would recreate decompressor
    }

    pub fn seek(self: *@This(), offset: i64, whence: u8) !i64 {
        const SEEK_SET: u8 = 0;
        const SEEK_CUR: u8 = 1;
        const SEEK_END: u8 = 2;

        var new_offset: i64 = offset;

        // Recalculate offset as an absolute file position
        switch (whence) {
            SEEK_SET => {},
            SEEK_CUR => {
                new_offset = @as(i64, @intCast(self.pos)) + offset;
            },
            SEEK_END => {
                // Seeking relative to EOF - need to know file size
                if (self.size < 0) {
                    // Would read until EOF to determine size
                    return error.NotImplemented;
                }
                new_offset = self.size + offset;
            },
            else => return error.ValueError, // "Invalid value for whence"
        }

        // Make new_offset relative to current position
        if (new_offset < @as(i64, @intCast(self.pos))) {
            self._rewind();
        } else {
            new_offset -= @as(i64, @intCast(self.pos));
        }

        // Would skip forward by reading and discarding data
        // Stub: Skip forward logic not implemented yet
        // In full implementation: while (new_offset > 0) { read and discard }

        return @as(i64, @intCast(self.pos));
    }
};

// DCE-friendly: All exports are struct-based, unused structs will be eliminated
