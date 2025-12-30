//! Reader interface (VFS abstraction).
//!
//! The Reader interface allows LanceQL to read data from various sources
//! (files, memory, HTTP) using the same parsing code. This is essential
//! for supporting both native execution and WASM browser targets.

const std = @import("std");

/// Errors that can occur during read operations
pub const ReadError = error{
    /// Requested offset is beyond end of data
    OffsetOutOfBounds,
    /// I/O operation failed
    IoError,
    /// Connection/network error
    NetworkError,
    /// Operation not supported on this platform
    Unsupported,
    /// Generic read failure
    ReadFailed,
};

/// Virtual file system reader interface.
///
/// This type-erased interface allows the same code to read from different
/// sources: local files, memory buffers, or HTTP endpoints.
pub const Reader = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Read data at the given offset into the buffer.
        /// Returns the number of bytes actually read.
        read: *const fn (ptr: *anyopaque, offset: u64, buffer: []u8) ReadError!usize,

        /// Get the total size of the data source.
        size: *const fn (ptr: *anyopaque) ReadError!u64,

        /// Release resources associated with this reader.
        deinit: *const fn (ptr: *anyopaque) void,
    };

    /// Read data at the given offset into the buffer.
    ///
    /// Returns the number of bytes actually read, which may be less than
    /// buffer.len if the end of data is reached.
    pub fn read(self: Reader, offset: u64, buffer: []u8) ReadError!usize {
        return self.vtable.read(self.ptr, offset, buffer);
    }

    /// Read exactly buffer.len bytes at the given offset.
    ///
    /// Returns an error if fewer bytes are available.
    pub fn readExact(self: Reader, offset: u64, buffer: []u8) ReadError!void {
        const bytes_read = try self.read(offset, buffer);
        if (bytes_read < buffer.len) {
            return ReadError.OffsetOutOfBounds;
        }
    }

    /// Get the total size of the data source in bytes.
    pub fn size(self: Reader) ReadError!u64 {
        return self.vtable.size(self.ptr);
    }

    /// Release resources associated with this reader.
    pub fn deinit(self: Reader) void {
        self.vtable.deinit(self.ptr);
    }

    /// Read and return allocated bytes from the given offset.
    ///
    /// Caller owns the returned memory and must free it.
    pub fn readAlloc(self: Reader, allocator: std.mem.Allocator, offset: u64, len: usize) ![]u8 {
        const buffer = try allocator.alloc(u8, len);
        errdefer allocator.free(buffer);

        try self.readExact(offset, buffer);
        return buffer;
    }
};

test "reader interface" {
    // This test verifies the interface compiles correctly.
    // Actual implementation tests are in file_reader.zig and memory_reader.zig.
    const vtable = Reader.VTable{
        .read = struct {
            fn f(_: *anyopaque, _: u64, _: []u8) ReadError!usize {
                return 0;
            }
        }.f,
        .size = struct {
            fn f(_: *anyopaque) ReadError!u64 {
                return 0;
            }
        }.f,
        .deinit = struct {
            fn f(_: *anyopaque) void {}
        }.f,
    };

    var dummy: u8 = 0;
    const reader_instance = Reader{
        .ptr = @ptrCast(&dummy),
        .vtable = &vtable,
    };

    const sz = try reader_instance.size();
    try std.testing.expectEqual(@as(u64, 0), sz);
}
