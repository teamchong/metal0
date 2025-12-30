//! In-memory reader implementation.
//!
//! Provides a Reader implementation for reading from an in-memory buffer.
//! Useful for testing and for cases where data is already loaded into memory.

const std = @import("std");
const reader_mod = @import("reader.zig");

const Reader = reader_mod.Reader;
const ReadError = reader_mod.ReadError;

/// Reader implementation for in-memory buffers.
pub const MemoryReader = struct {
    data: []const u8,

    const Self = @This();

    /// Create a new MemoryReader wrapping the given data.
    ///
    /// The data must remain valid for the lifetime of the reader.
    pub fn init(data: []const u8) Self {
        return Self{ .data = data };
    }

    /// Get a Reader interface for this buffer.
    pub fn reader(self: *Self) Reader {
        return Reader{
            .ptr = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    // VTable implementation
    const vtable = Reader.VTable{
        .read = readImpl,
        .size = sizeImpl,
        .deinit = deinitImpl,
    };

    fn readImpl(ptr: *anyopaque, offset: u64, buffer: []u8) ReadError!usize {
        const self: *Self = @ptrCast(@alignCast(ptr));

        const offset_usize: usize = @intCast(offset);
        if (offset_usize >= self.data.len) {
            return ReadError.OffsetOutOfBounds;
        }

        const available = self.data.len - offset_usize;
        const to_read = @min(buffer.len, available);

        @memcpy(buffer[0..to_read], self.data[offset_usize..][0..to_read]);
        return to_read;
    }

    fn sizeImpl(ptr: *anyopaque) ReadError!u64 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return @intCast(self.data.len);
    }

    fn deinitImpl(_: *anyopaque) void {
        // Nothing to clean up for memory reader
    }
};

test "memory reader read all" {
    const data = "Hello, Lance!";
    var mem_reader = MemoryReader.init(data);
    var r = mem_reader.reader();

    var buffer: [20]u8 = undefined;
    const bytes_read = try r.read(0, &buffer);

    try std.testing.expectEqual(@as(usize, 13), bytes_read);
    try std.testing.expectEqualStrings("Hello, Lance!", buffer[0..bytes_read]);
}

test "memory reader partial read" {
    const data = "Hello, Lance!";
    var mem_reader = MemoryReader.init(data);
    var r = mem_reader.reader();

    var buffer: [5]u8 = undefined;
    const bytes_read = try r.read(7, &buffer);

    try std.testing.expectEqual(@as(usize, 5), bytes_read);
    try std.testing.expectEqualStrings("Lance", buffer[0..bytes_read]);
}

test "memory reader size" {
    const data = "Hello, Lance!";
    var mem_reader = MemoryReader.init(data);
    var r = mem_reader.reader();

    const sz = try r.size();
    try std.testing.expectEqual(@as(u64, 13), sz);
}

test "memory reader offset out of bounds" {
    const data = "Hello";
    var mem_reader = MemoryReader.init(data);
    var r = mem_reader.reader();

    var buffer: [10]u8 = undefined;
    const result = r.read(100, &buffer);
    try std.testing.expectError(ReadError.OffsetOutOfBounds, result);
}

test "memory reader read exact" {
    const data = "Hello, Lance!";
    var mem_reader = MemoryReader.init(data);
    var r = mem_reader.reader();

    var buffer: [5]u8 = undefined;
    try r.readExact(0, &buffer);
    try std.testing.expectEqualStrings("Hello", &buffer);
}

test "memory reader read exact fails at end" {
    const data = "Hi";
    var mem_reader = MemoryReader.init(data);
    var r = mem_reader.reader();

    var buffer: [10]u8 = undefined;
    const result = r.readExact(0, &buffer);
    try std.testing.expectError(ReadError.OffsetOutOfBounds, result);
}
