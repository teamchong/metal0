//! test.test_ctypes.test_unaligned - Tests for unaligned structure access
//! Reference: cpython/Lib/test/test_ctypes/test_unaligned.py

const std = @import("std");

pub const PackedStruct = packed struct {
    a: u8,
    b: u32,
    c: u16,
};

pub fn readUnaligned(comptime T: type, ptr: [*]const u8) T {
    return std.mem.readInt(T, ptr[0..@sizeOf(T)], .little);
}

pub fn writeUnaligned(comptime T: type, ptr: [*]u8, value: T) void {
    std.mem.writeInt(T, ptr[0..@sizeOf(T)], value, .little);
}

test "packed_struct" {
    const s = PackedStruct{ .a = 1, .b = 2, .c = 3 };
    try std.testing.expectEqual(@as(u8, 1), s.a);
}
