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
    pub fn write(self: *Self, data: []const u8) i64 {
        self.buffer.appendSlice(self.allocator, data) catch return 0;
        self.position += data.len;
        return @intCast(data.len);
    }

    /// Read all remaining content from current position
    pub fn read(self: *Self) []const u8 {
        if (self.position >= self.buffer.items.len) return "";
        const result = self.buffer.items[self.position..];
        self.position = self.buffer.items.len;
        return result;
    }

    /// Read with size parameter (size=-1 means all remaining)
    pub fn readSize(self: *Self, size: i64) []const u8 {
        if (self.position >= self.buffer.items.len) return "";

        const remaining = self.buffer.items.len - self.position;
        const to_read = if (size < 0) remaining else @min(@as(usize, @intCast(size)), remaining);

        const result = self.buffer.items[self.position .. self.position + to_read];
        self.position += to_read;
        return result;
    }

    /// Read a single line (up to and including \n)
    pub fn readline(self: *Self) []const u8 {
        if (self.position >= self.buffer.items.len) return "";

        const start = self.position;
        var end = start;

        // Find newline or end of buffer
        while (end < self.buffer.items.len) {
            if (self.buffer.items[end] == '\n') {
                end += 1; // Include the newline
                break;
            }
            end += 1;
        }

        self.position = end;
        return self.buffer.items[start..end];
    }

    /// Read a single line with size limit
    pub fn readlineSize(self: *Self, size: i64) []const u8 {
        if (self.position >= self.buffer.items.len) return "";

        const max_read = if (size < 0) self.buffer.items.len else @as(usize, @intCast(size));
        const start = self.position;
        var end = start;

        // Find newline or end of buffer
        while (end < self.buffer.items.len and end - start < max_read) {
            if (self.buffer.items[end] == '\n') {
                end += 1; // Include the newline
                break;
            }
            end += 1;
        }

        self.position = end;
        return self.buffer.items[start..end];
    }

    /// Read all lines into a list
    pub fn readlines(self: *Self, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
        var lines = std.ArrayList([]const u8).init(allocator);
        errdefer lines.deinit();

        while (self.position < self.buffer.items.len) {
            const line = self.readline();
            if (line.len == 0) break;
            try lines.append(line);
        }

        return lines;
    }

    /// Write multiple lines
    pub fn writelines(self: *Self, lines: []const []const u8) i64 {
        var total: i64 = 0;
        for (lines) |line| {
            total += self.write(line);
        }
        return total;
    }

    /// Get entire buffer contents
    pub fn getvalue(self: *Self) []const u8 {
        return self.buffer.items;
    }

    /// Check if stream is readable
    pub fn readable(self: *Self) bool {
        _ = self;
        return true;
    }

    /// Check if stream is writable
    pub fn writable(self: *Self) bool {
        _ = self;
        return true;
    }

    /// Check if stream is seekable
    pub fn seekable(self: *Self) bool {
        _ = self;
        return true;
    }

    /// Check if stream is closed
    pub fn closed(self: *Self) bool {
        _ = self;
        return false; // In-memory streams are never really "closed"
    }

    /// Seek to position (from start, SEEK_SET)
    pub fn seek(self: *Self, offset: i64) i64 {
        self.position = @intCast(@max(0, @min(offset, @as(i64, @intCast(self.buffer.items.len)))));
        return @intCast(self.position);
    }

    /// Seek with whence parameter
    /// whence: 0=SEEK_SET (from start), 1=SEEK_CUR (from current), 2=SEEK_END (from end)
    pub fn seekWhence(self: *Self, offset: i64, whence: i32) i64 {
        const new_pos: i64 = switch (whence) {
            0 => offset, // SEEK_SET
            1 => @as(i64, @intCast(self.position)) + offset, // SEEK_CUR
            2 => @as(i64, @intCast(self.buffer.items.len)) + offset, // SEEK_END
            else => @as(i64, @intCast(self.position)),
        };

        self.position = @intCast(@max(0, @min(new_pos, @as(i64, @intCast(self.buffer.items.len)))));
        return @intCast(self.position);
    }

    /// Get current position
    pub fn tell(self: *Self) i64 {
        return @intCast(self.position);
    }

    /// Truncate buffer at current position
    pub fn truncate(self: *Self) i64 {
        if (self.position < self.buffer.items.len) {
            self.buffer.shrinkRetainingCapacity(self.position);
        }
        return @intCast(self.position);
    }

    /// Truncate buffer at given size
    pub fn truncateSize(self: *Self, size: i64) i64 {
        const truncate_at = @as(usize, @intCast(size));
        if (truncate_at < self.buffer.items.len) {
            self.buffer.shrinkRetainingCapacity(truncate_at);
        }
        return size;
    }

    /// Flush (no-op for memory streams)
    pub fn flush(self: *Self) void {
        _ = self;
    }

    /// Close (no-op for memory streams, but required for API)
    pub fn close(self: *Self) void {
        _ = self;
    }

    /// Check if at end of file
    pub fn isatty(self: *Self) bool {
        _ = self;
        return false;
    }

    /// Get file number (not applicable for memory streams)
    pub fn fileno(self: *Self) i32 {
        _ = self;
        return -1;
    }

    /// Free resources
    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
        self.allocator.destroy(self);
    }
};

/// BytesIO - In-memory binary stream (same as StringIO for now)
pub const BytesIO = StringIO;

/// SEEK constants for seek() whence parameter
pub const SEEK_SET: i32 = 0;
pub const SEEK_CUR: i32 = 1;
pub const SEEK_END: i32 = 2;

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

    _ = sio.seek(6, SEEK_SET);
    try testing.expectEqualStrings("world", sio.read(null));
    try testing.expectEqual(@as(i64, 11), sio.tell());
}

test "StringIO readline" {
    const testing = std.testing;
    var sio = try StringIO.createWithValue(testing.allocator, "line1\nline2\nline3");
    defer sio.deinit();

    try testing.expectEqualStrings("line1\n", sio.readline(null));
    try testing.expectEqualStrings("line2\n", sio.readline(null));
    try testing.expectEqualStrings("line3", sio.readline(null));
}

test "StringIO read with size" {
    const testing = std.testing;
    var sio = try StringIO.createWithValue(testing.allocator, "hello world");
    defer sio.deinit();

    try testing.expectEqualStrings("hello", sio.read(5));
    try testing.expectEqualStrings(" world", sio.read(null));
}
