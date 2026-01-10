//! test.test_ctypes.test_byteswap - Tests for ctypes byte swapping
//! Reference: cpython/Lib/test/test_ctypes/test_byteswap.py
//!
//! Tests for byte order swapping in ctypes including big-endian,
//! little-endian conversions and structure byte order.

const std = @import("std");
const builtin = @import("builtin");
const _support = @import("_support.zig");

// ============================================================================
// Byte Swap Functions
// ============================================================================

/// Swap bytes of a 16-bit value
pub fn swapBytes16(value: u16) u16 {
    return @byteSwap(value);
}

/// Swap bytes of a 32-bit value
pub fn swapBytes32(value: u32) u32 {
    return @byteSwap(value);
}

/// Swap bytes of a 64-bit value
pub fn swapBytes64(value: u64) u64 {
    return @byteSwap(value);
}

/// Convert native to big-endian
pub fn nativeToBig(comptime T: type, value: T) T {
    return std.mem.nativeToBig(T, value);
}

/// Convert big-endian to native
pub fn bigToNative(comptime T: type, value: T) T {
    return std.mem.bigToNative(T, value);
}

/// Convert native to little-endian
pub fn nativeToLittle(comptime T: type, value: T) T {
    return std.mem.nativeToLittle(T, value);
}

/// Convert little-endian to native
pub fn littleToNative(comptime T: type, value: T) T {
    return std.mem.littleToNative(T, value);
}

// ============================================================================
// Byte Order Markers
// ============================================================================

pub const ByteOrder = enum {
    little,
    big,
    native,

    pub fn isNativeLittle() bool {
        return builtin.cpu.arch.endian() == .little;
    }

    pub fn isNativeBig() bool {
        return builtin.cpu.arch.endian() == .big;
    }

    pub fn native() ByteOrder {
        return if (isNativeLittle()) .little else .big;
    }
};

// ============================================================================
// Big-Endian Structure
// ============================================================================

/// Structure with big-endian byte order
pub fn BigEndianStruct(comptime fields: []const FieldDesc) type {
    return struct {
        const Self = @This();
        pub const _fields_ = fields;
        pub const byte_order = ByteOrder.big;

        data: [calculateSize(fields)]u8 = undefined,

        pub fn init() Self {
            var self = Self{};
            @memset(&self.data, 0);
            return self;
        }

        /// Set a field value (stored as big-endian)
        pub fn setField(self: *Self, comptime name: []const u8, value: anytype) void {
            inline for (fields) |field| {
                if (std.mem.eql(u8, field.name, name)) {
                    const T = @TypeOf(value);
                    const be_value = std.mem.nativeToBig(T, value);
                    const bytes = std.mem.asBytes(&be_value);
                    @memcpy(self.data[field.offset .. field.offset + field.size], bytes);
                    return;
                }
            }
        }

        /// Get a field value (converted from big-endian)
        pub fn getField(self: *const Self, comptime name: []const u8, comptime T: type) T {
            inline for (fields) |field| {
                if (std.mem.eql(u8, field.name, name)) {
                    const field_bytes = self.data[field.offset..][0..@sizeOf(T)];
                    const be_value = std.mem.bytesToValue(T, field_bytes);
                    return std.mem.bigToNative(T, be_value);
                }
            }
            return std.mem.zeroes(T);
        }
    };
}

/// Little-endian structure
pub fn LittleEndianStruct(comptime fields: []const FieldDesc) type {
    return struct {
        const Self = @This();
        pub const _fields_ = fields;
        pub const byte_order = ByteOrder.little;

        data: [calculateSize(fields)]u8 = undefined,

        pub fn init() Self {
            var self = Self{};
            @memset(&self.data, 0);
            return self;
        }

        pub fn setField(self: *Self, comptime name: []const u8, value: anytype) void {
            inline for (fields) |field| {
                if (std.mem.eql(u8, field.name, name)) {
                    const T = @TypeOf(value);
                    const le_value = std.mem.nativeToLittle(T, value);
                    const bytes = std.mem.asBytes(&le_value);
                    @memcpy(self.data[field.offset .. field.offset + field.size], bytes);
                    return;
                }
            }
        }

        pub fn getField(self: *const Self, comptime name: []const u8, comptime T: type) T {
            inline for (fields) |field| {
                if (std.mem.eql(u8, field.name, name)) {
                    const field_bytes = self.data[field.offset..][0..@sizeOf(T)];
                    const le_value = std.mem.bytesToValue(T, field_bytes);
                    return std.mem.littleToNative(T, le_value);
                }
            }
            return std.mem.zeroes(T);
        }
    };
}

pub const FieldDesc = struct {
    name: []const u8,
    size: usize,
    offset: usize,
};

fn calculateSize(fields: []const FieldDesc) usize {
    if (fields.len == 0) return 0;
    const last = fields[fields.len - 1];
    return last.offset + last.size;
}

// ============================================================================
// Example Structures
// ============================================================================

pub const NetworkHeader = BigEndianStruct(&.{
    .{ .name = "version", .size = 2, .offset = 0 },
    .{ .name = "length", .size = 2, .offset = 2 },
    .{ .name = "id", .size = 4, .offset = 4 },
});

pub const FileHeader = LittleEndianStruct(&.{
    .{ .name = "magic", .size = 4, .offset = 0 },
    .{ .name = "version", .size = 2, .offset = 4 },
    .{ .name = "flags", .size = 2, .offset = 6 },
});

// ============================================================================
// Test Cases
// ============================================================================

fn testSwapBytes16() !void {
    try std.testing.expectEqual(@as(u16, 0x0102), swapBytes16(0x0201));
    try std.testing.expectEqual(@as(u16, 0xAABB), swapBytes16(0xBBAA));
    try std.testing.expectEqual(@as(u16, 0xFF00), swapBytes16(0x00FF));
}

fn testSwapBytes32() !void {
    try std.testing.expectEqual(@as(u32, 0x01020304), swapBytes32(0x04030201));
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), swapBytes32(0xEFBEADDE));
}

fn testSwapBytes64() !void {
    try std.testing.expectEqual(@as(u64, 0x0102030405060708), swapBytes64(0x0807060504030201));
}

fn testNativeToBig() !void {
    const native_val: u32 = 0x12345678;
    const big_val = nativeToBig(u32, native_val);

    if (ByteOrder.isNativeLittle()) {
        try std.testing.expectEqual(@as(u32, 0x78563412), big_val);
    } else {
        try std.testing.expectEqual(native_val, big_val);
    }
}

fn testBigToNative() !void {
    const big_val: u32 = 0x12345678;
    const native_val = bigToNative(u32, big_val);

    if (ByteOrder.isNativeLittle()) {
        try std.testing.expectEqual(@as(u32, 0x78563412), native_val);
    } else {
        try std.testing.expectEqual(big_val, native_val);
    }
}

fn testByteOrderDetection() !void {
    // One of these must be true
    try std.testing.expect(ByteOrder.isNativeLittle() or ByteOrder.isNativeBig());
    // They can't both be true
    try std.testing.expect(!(ByteOrder.isNativeLittle() and ByteOrder.isNativeBig()));
}

fn testBigEndianStruct() !void {
    var hdr = NetworkHeader.init();

    hdr.setField("version", @as(u16, 0x0100));
    hdr.setField("length", @as(u16, 0x0040));
    hdr.setField("id", @as(u32, 0x12345678));

    // Verify raw bytes are big-endian
    try std.testing.expectEqual(@as(u8, 0x01), hdr.data[0]); // version high byte
    try std.testing.expectEqual(@as(u8, 0x00), hdr.data[1]); // version low byte

    // Verify reading back
    try std.testing.expectEqual(@as(u16, 0x0100), hdr.getField("version", u16));
    try std.testing.expectEqual(@as(u32, 0x12345678), hdr.getField("id", u32));
}

fn testLittleEndianStruct() !void {
    var hdr = FileHeader.init();

    hdr.setField("magic", @as(u32, 0x50455A4D)); // "MZEP" in little-endian
    hdr.setField("version", @as(u16, 0x0001));

    // Verify raw bytes are little-endian
    try std.testing.expectEqual(@as(u8, 0x4D), hdr.data[0]); // 'M'
    try std.testing.expectEqual(@as(u8, 0x5A), hdr.data[1]); // 'Z'

    try std.testing.expectEqual(@as(u32, 0x50455A4D), hdr.getField("magic", u32));
}

fn testRoundtripConversion() !void {
    const original: u32 = 0xDEADBEEF;

    // Native -> Big -> Native
    const be = nativeToBig(u32, original);
    const back1 = bigToNative(u32, be);
    try std.testing.expectEqual(original, back1);

    // Native -> Little -> Native
    const le = nativeToLittle(u32, original);
    const back2 = littleToNative(u32, le);
    try std.testing.expectEqual(original, back2);
}

fn testSwapIsInvolution() !void {
    // Swapping twice should give original value
    const val16: u16 = 0xABCD;
    try std.testing.expectEqual(val16, swapBytes16(swapBytes16(val16)));

    const val32: u32 = 0x12345678;
    try std.testing.expectEqual(val32, swapBytes32(swapBytes32(val32)));

    const val64: u64 = 0x0102030405060708;
    try std.testing.expectEqual(val64, swapBytes64(swapBytes64(val64)));
}

fn testZeroSwap() !void {
    try std.testing.expectEqual(@as(u16, 0), swapBytes16(0));
    try std.testing.expectEqual(@as(u32, 0), swapBytes32(0));
    try std.testing.expectEqual(@as(u64, 0), swapBytes64(0));
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "swap_bytes_16" {
    try testSwapBytes16();
}

test "swap_bytes_32" {
    try testSwapBytes32();
}

test "swap_bytes_64" {
    try testSwapBytes64();
}

test "native_to_big" {
    try testNativeToBig();
}

test "big_to_native" {
    try testBigToNative();
}

test "byte_order_detection" {
    try testByteOrderDetection();
}

test "big_endian_struct" {
    try testBigEndianStruct();
}

test "little_endian_struct" {
    try testLittleEndianStruct();
}

test "roundtrip_conversion" {
    try testRoundtripConversion();
}

test "swap_is_involution" {
    try testSwapIsInvolution();
}

test "zero_swap" {
    try testZeroSwap();
}
