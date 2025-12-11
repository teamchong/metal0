/// _pyio.string_io - In-memory I/O streams
/// StringIO and BytesIO for reading/writing strings in memory

const std = @import("std");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const base = @import("base.zig");

// ============================================================================
// String I/O
// ============================================================================

/// StringIO - in-memory text stream
pub const StringIO = struct {
    const Self = @This();

    base: base.IOBase,
    buffer: std.ArrayList(u8),
    pos: usize = 0,
    allocator: Allocator,

    pub fn init(allocator: Allocator, initial: ?[]const u8) !Self {
        var buffer = std.ArrayList(u8).init(allocator);
        if (initial) |data| {
            try buffer.appendSlice(data);
        }
        return Self{
            .allocator = allocator,
            .buffer = buffer,
            .base = base.IOBase{
                .readable = true,
                .writable = true,
                .seekable = true,
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    pub fn getvalue(self: *const Self) []const u8 {
        return self.buffer.items;
    }

    pub fn read(self: *Self, size: ?usize) []const u8 {
        const max_size = size orelse (self.buffer.items.len - self.pos);
        const end = @min(self.pos + max_size, self.buffer.items.len);
        const result = self.buffer.items[self.pos..end];
        self.pos = end;
        return result;
    }

    pub fn write(self: *Self, data: []const u8) !usize {
        // Extend buffer if needed
        if (self.pos + data.len > self.buffer.items.len) {
            try self.buffer.resize(self.pos + data.len);
        }
        @memcpy(self.buffer.items[self.pos..][0..data.len], data);
        self.pos += data.len;
        return data.len;
    }

    pub fn seek(self: *Self, offset: i64, whence: types.SeekWhence) !u64 {
        const new_pos: i64 = switch (whence) {
            .set => offset,
            .cur => @as(i64, @intCast(self.pos)) + offset,
            .end => @as(i64, @intCast(self.buffer.items.len)) + offset,
        };
        if (new_pos < 0) return error.InvalidMode;
        self.pos = @intCast(new_pos);
        return self.pos;
    }

    pub fn tell(self: *const Self) u64 {
        return self.pos;
    }

    pub fn truncate(self: *Self, size: ?usize) !void {
        const new_size = size orelse self.pos;
        try self.buffer.resize(new_size);
        if (self.pos > new_size) {
            self.pos = new_size;
        }
    }
};

/// BytesIO - in-memory binary stream
pub const BytesIO = StringIO; // Same implementation for binary

// ============================================================================
// Tests
// ============================================================================

test "string io" {
    const allocator = std.testing.allocator;
    var sio = try StringIO.init(allocator, "hello");
    defer sio.deinit();

    try std.testing.expectEqualStrings("hello", sio.getvalue());

    const data = sio.read(3);
    try std.testing.expectEqualStrings("hel", data);
    try std.testing.expectEqual(@as(u64, 3), sio.tell());

    _ = try sio.write(" world");
    try std.testing.expectEqualStrings("hel world", sio.getvalue());
}

test "string io seek" {
    const allocator = std.testing.allocator;
    var sio = try StringIO.init(allocator, "hello");
    defer sio.deinit();

    _ = try sio.seek(2, .set);
    try std.testing.expectEqual(@as(u64, 2), sio.tell());

    _ = try sio.seek(1, .cur);
    try std.testing.expectEqual(@as(u64, 3), sio.tell());

    _ = try sio.seek(-1, .end);
    try std.testing.expectEqual(@as(u64, 4), sio.tell());
}
