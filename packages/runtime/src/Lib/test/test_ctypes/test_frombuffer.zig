//! test.test_ctypes.test_frombuffer - Tests for buffer creation
//! Reference: cpython/Lib/test/test_ctypes/test_frombuffer.py
//!
//! Tests for creating ctypes objects from existing memory buffers
//! including from_buffer, from_buffer_copy, and memory views.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// From Buffer Functions
// ============================================================================

/// Create a type instance from a buffer (shares memory)
pub fn fromBuffer(comptime T: type, buffer: []u8) !*T {
    if (buffer.len < @sizeOf(T)) {
        return error.BufferTooSmall;
    }

    const alignment = @alignOf(T);
    const addr = @intFromPtr(buffer.ptr);
    if (addr % alignment != 0) {
        return error.BufferNotAligned;
    }

    return @ptrCast(@alignCast(buffer.ptr));
}

/// Create a type instance from a buffer (copies data)
pub fn fromBufferCopy(comptime T: type, buffer: []const u8, out: *T) !void {
    if (buffer.len < @sizeOf(T)) {
        return error.BufferTooSmall;
    }

    const dest = std.mem.asBytes(out);
    @memcpy(dest, buffer[0..@sizeOf(T)]);
}

/// Create an array from a buffer
pub fn arrayFromBuffer(comptime T: type, comptime N: usize, buffer: []u8) !*[N]T {
    const required_size = @sizeOf(T) * N;
    if (buffer.len < required_size) {
        return error.BufferTooSmall;
    }

    const alignment = @alignOf(T);
    const addr = @intFromPtr(buffer.ptr);
    if (addr % alignment != 0) {
        return error.BufferNotAligned;
    }

    return @ptrCast(@alignCast(buffer.ptr));
}

// ============================================================================
// Buffer View
// ============================================================================

/// A view into a buffer that can be interpreted as different types
pub const BufferView = struct {
    const Self = @This();

    data: []u8,
    offset: usize = 0,
    readonly: bool = false,

    pub fn init(data: []u8) Self {
        return .{ .data = data };
    }

    pub fn initReadonly(data: []const u8) Self {
        return .{
            .data = @constCast(data),
            .readonly = true,
        };
    }

    /// Get a typed pointer at current offset
    pub fn as(self: *Self, comptime T: type) !*T {
        if (self.offset + @sizeOf(T) > self.data.len) {
            return error.BufferOverflow;
        }
        const ptr = self.data[self.offset..].ptr;
        const addr = @intFromPtr(ptr);
        if (addr % @alignOf(T) != 0) {
            return error.BufferNotAligned;
        }
        return @ptrCast(@alignCast(ptr));
    }

    /// Advance offset
    pub fn advance(self: *Self, bytes: usize) !void {
        if (self.offset + bytes > self.data.len) {
            return error.BufferOverflow;
        }
        self.offset += bytes;
    }

    /// Get remaining bytes
    pub fn remaining(self: *const Self) usize {
        return self.data.len - self.offset;
    }

    /// Reset offset
    pub fn reset(self: *Self) void {
        self.offset = 0;
    }
};

// ============================================================================
// Ctypes-like Wrappers
// ============================================================================

/// c_int from buffer
pub const c_int_buffer = struct {
    const Self = @This();

    ptr: *align(1) i32,

    pub fn fromBuffer(buffer: []u8) !Self {
        if (buffer.len < 4) return error.BufferTooSmall;
        return .{ .ptr = @ptrCast(buffer.ptr) };
    }

    pub fn value(self: Self) i32 {
        return self.ptr.*;
    }

    pub fn setValue(self: Self, v: i32) void {
        self.ptr.* = v;
    }
};

/// c_double from buffer
pub const c_double_buffer = struct {
    const Self = @This();

    ptr: *align(1) f64,

    pub fn fromBuffer(buffer: []u8) !Self {
        if (buffer.len < 8) return error.BufferTooSmall;
        return .{ .ptr = @ptrCast(buffer.ptr) };
    }

    pub fn value(self: Self) f64 {
        return self.ptr.*;
    }

    pub fn setValue(self: Self, v: f64) void {
        self.ptr.* = v;
    }
};

// ============================================================================
// Test Types
// ============================================================================

const TestStruct = extern struct {
    a: i32,
    b: i32,
    c: f64,
};

// ============================================================================
// Test Cases
// ============================================================================

fn testFromBufferBasic() !void {
    var buffer: [16]u8 align(8) = undefined;
    @memset(&buffer, 0);

    // Write a value
    const int_ptr: *i32 = @ptrCast(@alignCast(&buffer));
    int_ptr.* = 42;

    // Read via fromBuffer
    const read_ptr = try fromBuffer(i32, &buffer);
    try std.testing.expectEqual(@as(i32, 42), read_ptr.*);
}

fn testFromBufferModify() !void {
    var buffer: [16]u8 align(8) = undefined;
    @memset(&buffer, 0);

    const int_ptr = try fromBuffer(i32, &buffer);
    int_ptr.* = 100;

    // Verify modification is reflected in buffer
    const check: *i32 = @ptrCast(@alignCast(&buffer));
    try std.testing.expectEqual(@as(i32, 100), check.*);
}

fn testFromBufferTooSmall() !void {
    var buffer: [2]u8 = undefined;
    try std.testing.expectError(error.BufferTooSmall, fromBuffer(i32, &buffer));
}

fn testFromBufferCopyBasic() !void {
    const source = [_]u8{ 0x01, 0x00, 0x00, 0x00 }; // 1 in little-endian

    var dest: i32 = 0;
    try fromBufferCopy(i32, &source, &dest);

    try std.testing.expectEqual(@as(i32, 1), dest);
}

fn testFromBufferCopyIsolated() !void {
    var source = [_]u8{ 0x2A, 0x00, 0x00, 0x00 }; // 42

    var dest: i32 = 0;
    try fromBufferCopy(i32, &source, &dest);

    // Modify source
    source[0] = 0xFF;

    // dest should be unchanged (it's a copy)
    try std.testing.expectEqual(@as(i32, 42), dest);
}

fn testArrayFromBuffer() !void {
    var buffer: [20]u8 align(4) = undefined;
    @memset(&buffer, 0);

    const arr = try arrayFromBuffer(i32, 5, &buffer);
    arr[0] = 10;
    arr[4] = 50;

    try std.testing.expectEqual(@as(i32, 10), arr[0]);
    try std.testing.expectEqual(@as(i32, 50), arr[4]);
}

fn testBufferView() !void {
    var buffer: [32]u8 align(8) = undefined;
    @memset(&buffer, 0);

    var view = BufferView.init(&buffer);
    try std.testing.expectEqual(@as(usize, 32), view.remaining());

    const int_ptr = try view.as(i32);
    int_ptr.* = 123;

    try view.advance(4);
    try std.testing.expectEqual(@as(usize, 28), view.remaining());

    const next_int = try view.as(i32);
    next_int.* = 456;

    // Reset and verify
    view.reset();
    const first = try view.as(i32);
    try std.testing.expectEqual(@as(i32, 123), first.*);
}

fn testBufferViewOverflow() !void {
    var buffer: [4]u8 = undefined;
    var view = BufferView.init(&buffer);

    try view.advance(2);
    try std.testing.expectError(error.BufferOverflow, view.as(i32));
}

fn testCIntBuffer() !void {
    var buffer: [4]u8 align(4) = undefined;
    @memset(&buffer, 0);

    const ci = try c_int_buffer.fromBuffer(&buffer);
    ci.setValue(12345);
    try std.testing.expectEqual(@as(i32, 12345), ci.value());
}

fn testCDoubleBuffer() !void {
    var buffer: [8]u8 align(8) = undefined;
    @memset(&buffer, 0);

    const cd = try c_double_buffer.fromBuffer(&buffer);
    cd.setValue(3.14159);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14159), cd.value(), 0.00001);
}

fn testStructFromBuffer() !void {
    var buffer: [24]u8 align(8) = undefined;
    @memset(&buffer, 0);

    const s = try fromBuffer(TestStruct, &buffer);
    s.a = 1;
    s.b = 2;
    s.c = 3.0;

    try std.testing.expectEqual(@as(i32, 1), s.a);
    try std.testing.expectEqual(@as(i32, 2), s.b);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), s.c, 0.001);
}

fn testBufferViewReadonly() !void {
    const data = [_]u8{ 1, 2, 3, 4 };
    const view = BufferView.initReadonly(&data);

    try std.testing.expect(view.readonly);
    try std.testing.expectEqual(@as(usize, 4), view.remaining());
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "from_buffer_basic" {
    try testFromBufferBasic();
}

test "from_buffer_modify" {
    try testFromBufferModify();
}

test "from_buffer_too_small" {
    try testFromBufferTooSmall();
}

test "from_buffer_copy_basic" {
    try testFromBufferCopyBasic();
}

test "from_buffer_copy_isolated" {
    try testFromBufferCopyIsolated();
}

test "array_from_buffer" {
    try testArrayFromBuffer();
}

test "buffer_view" {
    try testBufferView();
}

test "buffer_view_overflow" {
    try testBufferViewOverflow();
}

test "c_int_buffer" {
    try testCIntBuffer();
}

test "c_double_buffer" {
    try testCDoubleBuffer();
}

test "struct_from_buffer" {
    try testStructFromBuffer();
}

test "buffer_view_readonly" {
    try testBufferViewReadonly();
}
