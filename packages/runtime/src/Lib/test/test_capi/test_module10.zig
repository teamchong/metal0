//! test.test_capi.test_module10 - C API Module Tests Part 10 - Buffer Protocol
const std = @import("std");

/// Buffer view structure
pub const Py_buffer = struct {
    buf: [*]u8,
    len: usize,
    itemsize: usize = 1,
    readonly: bool = false,
    ndim: u8 = 1,
    format: ?[]const u8 = null,
    shape: ?[]const usize = null,
    strides: ?[]const usize = null,

    pub fn init(buf: []u8) Py_buffer {
        return .{
            .buf = buf.ptr,
            .len = buf.len,
        };
    }

    pub fn initReadonly(buf: []const u8) Py_buffer {
        return .{
            .buf = @constCast(buf.ptr),
            .len = buf.len,
            .readonly = true,
        };
    }

    pub fn asSlice(self: *const Py_buffer) []u8 {
        return self.buf[0..self.len];
    }

    pub fn asConstSlice(self: *const Py_buffer) []const u8 {
        return self.buf[0..self.len];
    }
};

/// Memory view object
pub const PyMemoryView = struct {
    buffer: Py_buffer,
    released: bool = false,

    pub fn fromBuffer(buffer: Py_buffer) PyMemoryView {
        return .{ .buffer = buffer };
    }

    pub fn release(self: *PyMemoryView) void {
        self.released = true;
    }

    pub fn toBytes(self: *const PyMemoryView) []const u8 {
        return self.buffer.asConstSlice();
    }

    pub fn len(self: *const PyMemoryView) usize {
        return self.buffer.len;
    }

    pub fn isReadonly(self: *const PyMemoryView) bool {
        return self.buffer.readonly;
    }
};

/// Bytes object
pub const PyBytes = struct {
    data: []const u8,
    hash: ?u64 = null,

    pub fn fromSlice(data: []const u8) PyBytes {
        return .{ .data = data };
    }

    pub fn len(self: *const PyBytes) usize {
        return self.data.len;
    }

    pub fn getItem(self: *const PyBytes, index: usize) !u8 {
        if (index >= self.data.len) return error.IndexError;
        return self.data[index];
    }

    pub fn getSlice(self: *const PyBytes, start: usize, end: usize) []const u8 {
        const s = @min(start, self.data.len);
        const e = @min(end, self.data.len);
        return self.data[s..e];
    }

    pub fn getHash(self: *PyBytes) u64 {
        if (self.hash) |h| return h;
        self.hash = std.hash.Wyhash.hash(0, self.data);
        return self.hash.?;
    }
};

/// Bytearray object (mutable)
pub const PyByteArray = struct {
    data: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) PyByteArray {
        return .{ .data = std.ArrayList(u8).init(allocator) };
    }

    pub fn initWithCapacity(allocator: std.mem.Allocator, capacity: usize) !PyByteArray {
        var arr = PyByteArray.init(allocator);
        try arr.data.ensureTotalCapacity(capacity);
        return arr;
    }

    pub fn deinit(self: *PyByteArray) void {
        self.data.deinit();
    }

    pub fn len(self: *const PyByteArray) usize {
        return self.data.items.len;
    }

    pub fn append(self: *PyByteArray, byte: u8) !void {
        try self.data.append(byte);
    }

    pub fn extend(self: *PyByteArray, bytes: []const u8) !void {
        try self.data.appendSlice(bytes);
    }

    pub fn getItem(self: *const PyByteArray, index: usize) !u8 {
        if (index >= self.data.items.len) return error.IndexError;
        return self.data.items[index];
    }

    pub fn setItem(self: *PyByteArray, index: usize, value: u8) !void {
        if (index >= self.data.items.len) return error.IndexError;
        self.data.items[index] = value;
    }

    pub fn clear(self: *PyByteArray) void {
        self.data.clearRetainingCapacity();
    }

    pub fn pop(self: *PyByteArray) ?u8 {
        return self.data.popOrNull();
    }

    pub fn asSlice(self: *const PyByteArray) []const u8 {
        return self.data.items;
    }
};

/// Pack/unpack binary data
pub const Struct = struct {
    format: []const u8,

    pub fn init(format: []const u8) Struct {
        return .{ .format = format };
    }

    pub fn calcsize(self: *const Struct) usize {
        var size: usize = 0;
        for (self.format) |c| {
            size += switch (c) {
                'b', 'B', 'c', '?' => 1,
                'h', 'H' => 2,
                'i', 'I', 'l', 'L', 'f' => 4,
                'q', 'Q', 'd' => 8,
                else => 0,
            };
        }
        return size;
    }
};

test "Py_buffer basic" {
    var data = [_]u8{ 1, 2, 3, 4, 5 };
    const buf = Py_buffer.init(&data);

    try std.testing.expectEqual(@as(usize, 5), buf.len);
    try std.testing.expect(!buf.readonly);

    const slice = buf.asSlice();
    try std.testing.expectEqual(@as(u8, 1), slice[0]);
}

test "Py_buffer readonly" {
    const data = "hello";
    const buf = Py_buffer.initReadonly(data);

    try std.testing.expect(buf.readonly);
    try std.testing.expectEqualStrings("hello", buf.asConstSlice());
}

test "PyMemoryView" {
    var data = [_]u8{ 10, 20, 30 };
    const buf = Py_buffer.init(&data);
    var view = PyMemoryView.fromBuffer(buf);

    try std.testing.expectEqual(@as(usize, 3), view.len());
    try std.testing.expect(!view.isReadonly());

    view.release();
    try std.testing.expect(view.released);
}

test "PyBytes" {
    var bytes = PyBytes.fromSlice("hello");

    try std.testing.expectEqual(@as(usize, 5), bytes.len());
    try std.testing.expectEqual(@as(u8, 'h'), try bytes.getItem(0));
    try std.testing.expectEqualStrings("ell", bytes.getSlice(1, 4));
}

test "PyByteArray" {
    const allocator = std.testing.allocator;
    var arr = PyByteArray.init(allocator);
    defer arr.deinit();

    try arr.append(65);
    try arr.append(66);
    try arr.extend("CD");

    try std.testing.expectEqual(@as(usize, 4), arr.len());
    try std.testing.expectEqualStrings("ABCD", arr.asSlice());

    try arr.setItem(0, 90);
    try std.testing.expectEqual(@as(u8, 90), try arr.getItem(0));
}

test "Struct calcsize" {
    const s1 = Struct.init("b");
    try std.testing.expectEqual(@as(usize, 1), s1.calcsize());

    const s2 = Struct.init("ih");
    try std.testing.expectEqual(@as(usize, 6), s2.calcsize());

    const s3 = Struct.init("qd");
    try std.testing.expectEqual(@as(usize, 16), s3.calcsize());
}
