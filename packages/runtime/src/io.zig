/// Python io module implementation
/// StringIO and BytesIO in-memory streams
const std = @import("std");

/// StringIO - In-memory text stream
pub const StringIO = struct {
    buffer: std.ArrayList(u8),
    position: usize,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Create empty StringIO
    pub fn create(allocator: std.mem.Allocator) !*Self {
        const self = try allocator.create(Self);
        self.* = Self{
            .buffer = std.ArrayList(u8){},
            .position = 0,
            .allocator = allocator,
        };
        return self;
    }

    /// Create StringIO with initial value
    pub fn createWithValue(allocator: std.mem.Allocator, initial: []const u8) !*Self {
        const self = try allocator.create(Self);
        var buffer = std.ArrayList(u8){};
        try buffer.appendSlice(allocator, initial);
        self.* = Self{
            .buffer = buffer,
            .position = 0,
            .allocator = allocator,
        };
        return self;
    }

    /// Write string to stream, returns bytes written
    pub fn write(self: *Self, data: []const u8) usize {
        self.buffer.appendSlice(self.allocator, data) catch return 0;
        self.position += data.len;
        return data.len;
    }

    /// Read from current position to end (or n bytes)
    pub fn read(self: *Self) []const u8 {
        if (self.position >= self.buffer.items.len) return "";
        const result = self.buffer.items[self.position..];
        self.position = self.buffer.items.len;
        return result;
    }

    /// Get entire buffer contents
    pub fn getvalue(self: *Self) []const u8 {
        return self.buffer.items;
    }

    /// Seek to position
    pub fn seek(self: *Self, pos: usize) void {
        self.position = @min(pos, self.buffer.items.len);
    }

    /// Get current position
    pub fn tell(self: *Self) usize {
        return self.position;
    }

    /// Truncate buffer at current position
    pub fn truncate(self: *Self) void {
        self.buffer.shrinkRetainingCapacity(self.position);
    }

    /// Close (no-op for memory streams, but required for API)
    pub fn close(self: *Self) void {
        _ = self;
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

/// BytesIO - In-memory binary stream (same as StringIO for now)
pub const BytesIO = StringIO;

// Tests
test "StringIO basic" {
    const testing = std.testing;
    var sio = try StringIO.create(testing.allocator);
    defer sio.deinit();

    _ = sio.write("hello");
    _ = sio.write(" world");

    try testing.expectEqualStrings("hello world", sio.getvalue());
}

test "StringIO seek and read" {
    const testing = std.testing;
    var sio = try StringIO.createWithValue(testing.allocator, "hello world");
    defer sio.deinit();

    sio.seek(6);
    try testing.expectEqualStrings("world", sio.read());
    try testing.expectEqual(@as(usize, 11), sio.tell());
}
