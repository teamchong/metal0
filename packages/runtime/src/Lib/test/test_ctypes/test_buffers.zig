//! test.test_ctypes.test_buffers - Tests for ctypes buffer operations
//! Reference: cpython/Lib/test/test_ctypes/test_buffers.py
//!
//! Tests for buffer protocol support in ctypes including memory views,
//! buffer exports, and raw memory access.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Buffer Type
// ============================================================================

/// A buffer that provides raw memory access
pub fn Buffer(comptime size: usize) type {
    return struct {
        const Self = @This();

        data: [size]u8 = undefined,
        len: usize = size,
        readonly: bool = false,

        pub fn init() Self {
            var self = Self{};
            @memset(&self.data, 0);
            return self;
        }

        pub fn initReadonly(src: []const u8) Self {
            var self = Self{};
            const copy_len = @min(src.len, size);
            @memcpy(self.data[0..copy_len], src[0..copy_len]);
            self.readonly = true;
            return self;
        }

        /// Get raw buffer pointer
        pub fn ptr(self: *Self) [*]u8 {
            return &self.data;
        }

        /// Get const pointer
        pub fn constPtr(self: *const Self) [*]const u8 {
            return &self.data;
        }

        /// Get as slice
        pub fn slice(self: *Self) []u8 {
            return self.data[0..self.len];
        }

        /// Get as const slice
        pub fn constSlice(self: *const Self) []const u8 {
            return self.data[0..self.len];
        }

        /// Get buffer size
        pub fn bufferSize(_: *const Self) usize {
            return size;
        }

        /// Write at offset
        pub fn writeAt(self: *Self, offset: usize, bytes: []const u8) !void {
            if (self.readonly) return error.ReadOnlyBuffer;
            if (offset + bytes.len > size) return error.BufferOverflow;
            @memcpy(self.data[offset .. offset + bytes.len], bytes);
        }

        /// Read at offset
        pub fn readAt(self: *const Self, offset: usize, len: usize) ![]const u8 {
            if (offset + len > size) return error.BufferOverflow;
            return self.data[offset .. offset + len];
        }

        /// Fill buffer with value
        pub fn fill(self: *Self, value: u8) !void {
            if (self.readonly) return error.ReadOnlyBuffer;
            @memset(&self.data, value);
        }

        /// Clear buffer
        pub fn clear(self: *Self) !void {
            return self.fill(0);
        }
    };
}

// ============================================================================
// Memory View
// ============================================================================

/// A view into a buffer (similar to memoryview)
pub const MemoryView = struct {
    const Self = @This();

    ptr: [*]const u8,
    len: usize,
    readonly: bool,
    format: []const u8 = "B", // Default: unsigned char

    pub fn init(data: []const u8) Self {
        return .{
            .ptr = data.ptr,
            .len = data.len,
            .readonly = true,
        };
    }

    pub fn initMutable(data: []u8) Self {
        return .{
            .ptr = data.ptr,
            .len = data.len,
            .readonly = false,
        };
    }

    /// Get byte at index
    pub fn get(self: Self, index: usize) ?u8 {
        if (index >= self.len) return null;
        return self.ptr[index];
    }

    /// Set byte at index (if mutable)
    pub fn set(self: *Self, index: usize, value: u8) !void {
        if (self.readonly) return error.ReadOnlyBuffer;
        if (index >= self.len) return error.IndexOutOfBounds;
        @as([*]u8, @ptrCast(@constCast(self.ptr)))[index] = value;
    }

    /// Get slice of view
    pub fn subview(self: Self, start: usize, end: usize) !MemoryView {
        if (start > end or end > self.len) return error.InvalidSlice;
        return .{
            .ptr = self.ptr + start,
            .len = end - start,
            .readonly = self.readonly,
            .format = self.format,
        };
    }

    /// Convert to slice
    pub fn toSlice(self: Self) []const u8 {
        return self.ptr[0..self.len];
    }

    /// Get item size for format
    pub fn itemSize(self: Self) usize {
        if (std.mem.eql(u8, self.format, "B") or std.mem.eql(u8, self.format, "b")) return 1;
        if (std.mem.eql(u8, self.format, "H") or std.mem.eql(u8, self.format, "h")) return 2;
        if (std.mem.eql(u8, self.format, "I") or std.mem.eql(u8, self.format, "i")) return 4;
        if (std.mem.eql(u8, self.format, "Q") or std.mem.eql(u8, self.format, "q")) return 8;
        return 1;
    }
};

// ============================================================================
// Create Buffer Functions
// ============================================================================

/// Create buffer from string
pub fn createStringBuffer(s: []const u8) Buffer(256) {
    var buf = Buffer(256).init();
    const len = @min(s.len, 256);
    @memcpy(buf.data[0..len], s[0..len]);
    buf.len = len;
    return buf;
}

/// Create buffer from array
pub fn createArrayBuffer(comptime T: type, arr: []const T) Buffer(@sizeOf(T) * 64) {
    var buf = Buffer(@sizeOf(T) * 64).init();
    const bytes = std.mem.sliceAsBytes(arr);
    const len = @min(bytes.len, buf.data.len);
    @memcpy(buf.data[0..len], bytes[0..len]);
    buf.len = len;
    return buf;
}

// ============================================================================
// Test Types
// ============================================================================

pub const SmallBuffer = Buffer(16);
pub const MediumBuffer = Buffer(256);
pub const LargeBuffer = Buffer(4096);

// ============================================================================
// Test Cases
// ============================================================================

fn testBufferInit() !void {
    const buf = SmallBuffer.init();
    try std.testing.expectEqual(@as(usize, 16), buf.bufferSize());

    // Should be zero-initialized
    for (buf.data) |b| {
        try std.testing.expectEqual(@as(u8, 0), b);
    }
}

fn testBufferReadWrite() !void {
    var buf = SmallBuffer.init();

    try buf.writeAt(0, "Hello");
    const data = try buf.readAt(0, 5);
    try std.testing.expectEqualStrings("Hello", data);
}

fn testBufferOverflow() !void {
    var buf = SmallBuffer.init();

    // Writing beyond buffer should fail
    const result = buf.writeAt(14, "ABCD"); // 14 + 4 > 16
    try std.testing.expectError(error.BufferOverflow, result);
}

fn testReadonlyBuffer() !void {
    var buf = SmallBuffer.initReadonly("readonly data");

    // Writing to readonly buffer should fail
    const result = buf.writeAt(0, "X");
    try std.testing.expectError(error.ReadOnlyBuffer, result);
}

fn testBufferFill() !void {
    var buf = SmallBuffer.init();

    try buf.fill(0xAA);
    for (buf.data) |b| {
        try std.testing.expectEqual(@as(u8, 0xAA), b);
    }

    try buf.clear();
    for (buf.data) |b| {
        try std.testing.expectEqual(@as(u8, 0), b);
    }
}

fn testMemoryViewBasic() !void {
    const data = "Hello, World!";
    const view = MemoryView.init(data);

    try std.testing.expectEqual(@as(usize, 13), view.len);
    try std.testing.expectEqual(@as(?u8, 'H'), view.get(0));
    try std.testing.expectEqual(@as(?u8, '!'), view.get(12));
    try std.testing.expectEqual(@as(?u8, null), view.get(13));
}

fn testMemoryViewSubview() !void {
    const data = "Hello, World!";
    const view = MemoryView.init(data);

    const sub = try view.subview(0, 5);
    try std.testing.expectEqual(@as(usize, 5), sub.len);
    try std.testing.expectEqualStrings("Hello", sub.toSlice());
}

fn testMemoryViewMutable() !void {
    var data = [_]u8{ 'H', 'e', 'l', 'l', 'o' };
    var view = MemoryView.initMutable(&data);

    try view.set(0, 'J');
    try std.testing.expectEqual(@as(u8, 'J'), data[0]);
}

fn testMemoryViewReadonly() !void {
    const data = "Readonly";
    var view = MemoryView.init(data);

    const result = view.set(0, 'X');
    try std.testing.expectError(error.ReadOnlyBuffer, result);
}

fn testStringBuffer() !void {
    const buf = createStringBuffer("Test string");
    try std.testing.expectEqual(@as(usize, 11), buf.len);
    try std.testing.expectEqualStrings("Test string", buf.data[0..11]);
}

fn testMemoryViewFormat() !void {
    const view = MemoryView{
        .ptr = "test".ptr,
        .len = 4,
        .readonly = true,
        .format = "I",
    };

    try std.testing.expectEqual(@as(usize, 4), view.itemSize());
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "buffer_init" {
    try testBufferInit();
}

test "buffer_read_write" {
    try testBufferReadWrite();
}

test "buffer_overflow" {
    try testBufferOverflow();
}

test "readonly_buffer" {
    try testReadonlyBuffer();
}

test "buffer_fill" {
    try testBufferFill();
}

test "memoryview_basic" {
    try testMemoryViewBasic();
}

test "memoryview_subview" {
    try testMemoryViewSubview();
}

test "memoryview_mutable" {
    try testMemoryViewMutable();
}

test "memoryview_readonly" {
    try testMemoryViewReadonly();
}

test "string_buffer" {
    try testStringBuffer();
}

test "memoryview_format" {
    try testMemoryViewFormat();
}
