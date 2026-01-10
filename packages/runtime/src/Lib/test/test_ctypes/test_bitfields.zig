//! test.test_ctypes.test_bitfields - Tests for ctypes bitfield structures
//! Reference: cpython/Lib/test/test_ctypes/test_bitfields.py
//!
//! Tests for bitfield support in ctypes structures including packing,
//! signed/unsigned fields, and cross-platform behavior.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Bitfield Types
// ============================================================================

/// Packed bitfield structure
pub fn BitfieldStruct(comptime fields: []const BitfieldDesc) type {
    const total_bits = calculateTotalBits(fields);
    const byte_size = (total_bits + 7) / 8;

    return struct {
        const Self = @This();
        pub const _fields_ = fields;

        data: [byte_size]u8 = undefined,

        pub fn init() Self {
            var self = Self{};
            @memset(&self.data, 0);
            return self;
        }

        /// Get a bitfield value by name
        pub fn getBitfield(self: *const Self, comptime name: []const u8) u64 {
            inline for (fields) |field| {
                if (std.mem.eql(u8, field.name, name)) {
                    return extractBits(&self.data, field.bit_offset, field.bit_width);
                }
            }
            return 0;
        }

        /// Set a bitfield value by name
        pub fn setBitfield(self: *Self, comptime name: []const u8, value: u64) void {
            inline for (fields) |field| {
                if (std.mem.eql(u8, field.name, name)) {
                    insertBits(&self.data, field.bit_offset, field.bit_width, value);
                    return;
                }
            }
        }

        pub fn sizeof() usize {
            return byte_size;
        }

        pub fn totalBits() usize {
            return total_bits;
        }
    };
}

/// Bitfield descriptor
pub const BitfieldDesc = struct {
    name: []const u8,
    bit_width: u6,
    bit_offset: usize,
    is_signed: bool = false,
};

/// Calculate total bits needed
fn calculateTotalBits(fields: []const BitfieldDesc) usize {
    var max: usize = 0;
    for (fields) |field| {
        const end = field.bit_offset + field.bit_width;
        max = @max(max, end);
    }
    return max;
}

/// Extract bits from byte array
fn extractBits(data: []const u8, bit_offset: usize, bit_width: u6) u64 {
    var result: u64 = 0;
    var bit: usize = 0;
    while (bit < bit_width) : (bit += 1) {
        const global_bit = bit_offset + bit;
        const byte_idx = global_bit / 8;
        const bit_idx: u3 = @intCast(global_bit % 8);
        if (byte_idx < data.len) {
            const bit_val: u64 = @as(u64, (data[byte_idx] >> bit_idx) & 1);
            result |= bit_val << @intCast(bit);
        }
    }
    return result;
}

/// Insert bits into byte array
fn insertBits(data: []u8, bit_offset: usize, bit_width: u6, value: u64) void {
    var bit: usize = 0;
    while (bit < bit_width) : (bit += 1) {
        const global_bit = bit_offset + bit;
        const byte_idx = global_bit / 8;
        const bit_idx: u3 = @intCast(global_bit % 8);
        if (byte_idx < data.len) {
            const bit_val: u8 = @intCast((value >> @intCast(bit)) & 1);
            data[byte_idx] = (data[byte_idx] & ~(@as(u8, 1) << bit_idx)) | (bit_val << bit_idx);
        }
    }
}

// ============================================================================
// Example Bitfield Structures
// ============================================================================

/// Simple flags structure
pub const Flags = BitfieldStruct(&.{
    .{ .name = "read", .bit_width = 1, .bit_offset = 0 },
    .{ .name = "write", .bit_width = 1, .bit_offset = 1 },
    .{ .name = "execute", .bit_width = 1, .bit_offset = 2 },
    .{ .name = "reserved", .bit_width = 5, .bit_offset = 3 },
});

/// RGB color packed into 16 bits
pub const RGB565 = BitfieldStruct(&.{
    .{ .name = "blue", .bit_width = 5, .bit_offset = 0 },
    .{ .name = "green", .bit_width = 6, .bit_offset = 5 },
    .{ .name = "red", .bit_width = 5, .bit_offset = 11 },
});

/// Multi-byte bitfield
pub const PackedData = BitfieldStruct(&.{
    .{ .name = "type_id", .bit_width = 4, .bit_offset = 0 },
    .{ .name = "flags", .bit_width = 8, .bit_offset = 4 },
    .{ .name = "length", .bit_width = 12, .bit_offset = 12 },
    .{ .name = "checksum", .bit_width = 8, .bit_offset = 24 },
});

/// Signed bitfield example
pub const SignedBits = BitfieldStruct(&.{
    .{ .name = "value", .bit_width = 4, .bit_offset = 0, .is_signed = true },
    .{ .name = "extra", .bit_width = 4, .bit_offset = 4, .is_signed = false },
});

// ============================================================================
// Helper Functions
// ============================================================================

/// Sign extend a value
pub fn signExtend(value: u64, bit_width: u6) i64 {
    const shift: u6 = @intCast(64 - bit_width);
    return @as(i64, @bitCast(value << shift)) >> shift;
}

/// Get maximum unsigned value for bit width
pub fn maxUnsigned(bit_width: u6) u64 {
    if (bit_width >= 64) return std.math.maxInt(u64);
    return (@as(u64, 1) << bit_width) - 1;
}

/// Get maximum signed value for bit width
pub fn maxSigned(bit_width: u6) i64 {
    if (bit_width >= 64) return std.math.maxInt(i64);
    return (@as(i64, 1) << (bit_width - 1)) - 1;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testFlagsStructure() !void {
    var flags = Flags.init();
    try std.testing.expectEqual(@as(usize, 1), Flags.sizeof());

    flags.setBitfield("read", 1);
    flags.setBitfield("write", 1);
    flags.setBitfield("execute", 0);

    try std.testing.expectEqual(@as(u64, 1), flags.getBitfield("read"));
    try std.testing.expectEqual(@as(u64, 1), flags.getBitfield("write"));
    try std.testing.expectEqual(@as(u64, 0), flags.getBitfield("execute"));
}

fn testRGB565() !void {
    var color = RGB565.init();
    try std.testing.expectEqual(@as(usize, 2), RGB565.sizeof());

    // Set bright red
    color.setBitfield("red", 31);
    color.setBitfield("green", 0);
    color.setBitfield("blue", 0);

    try std.testing.expectEqual(@as(u64, 31), color.getBitfield("red"));
    try std.testing.expectEqual(@as(u64, 0), color.getBitfield("green"));
    try std.testing.expectEqual(@as(u64, 0), color.getBitfield("blue"));

    // Check raw bytes (little-endian: red is in upper bits)
    // Red=31 at bit 11: 0xF800 = bytes [0x00, 0xF8]
    try std.testing.expectEqual(@as(u8, 0x00), color.data[0]);
    try std.testing.expectEqual(@as(u8, 0xF8), color.data[1]);
}

fn testPackedData() !void {
    var pkt = PackedData.init();
    try std.testing.expectEqual(@as(usize, 4), PackedData.sizeof());

    pkt.setBitfield("type_id", 0x0F);
    pkt.setBitfield("flags", 0xAB);
    pkt.setBitfield("length", 0x123);
    pkt.setBitfield("checksum", 0xCC);

    try std.testing.expectEqual(@as(u64, 0x0F), pkt.getBitfield("type_id"));
    try std.testing.expectEqual(@as(u64, 0xAB), pkt.getBitfield("flags"));
    try std.testing.expectEqual(@as(u64, 0x123), pkt.getBitfield("length"));
    try std.testing.expectEqual(@as(u64, 0xCC), pkt.getBitfield("checksum"));
}

fn testSignExtend() !void {
    // 4-bit value 0xF (-1 in signed 4-bit)
    try std.testing.expectEqual(@as(i64, -1), signExtend(0xF, 4));
    // 4-bit value 0x7 (7 in signed 4-bit)
    try std.testing.expectEqual(@as(i64, 7), signExtend(0x7, 4));
    // 4-bit value 0x8 (-8 in signed 4-bit)
    try std.testing.expectEqual(@as(i64, -8), signExtend(0x8, 4));
}

fn testMaxValues() !void {
    try std.testing.expectEqual(@as(u64, 1), maxUnsigned(1));
    try std.testing.expectEqual(@as(u64, 15), maxUnsigned(4));
    try std.testing.expectEqual(@as(u64, 255), maxUnsigned(8));
    try std.testing.expectEqual(@as(u64, 65535), maxUnsigned(16));

    try std.testing.expectEqual(@as(i64, 7), maxSigned(4));
    try std.testing.expectEqual(@as(i64, 127), maxSigned(8));
}

fn testBitfieldOverwrite() !void {
    var flags = Flags.init();

    // Set all bits
    flags.setBitfield("read", 1);
    flags.setBitfield("write", 1);
    flags.setBitfield("execute", 1);

    // Clear middle bit
    flags.setBitfield("write", 0);

    try std.testing.expectEqual(@as(u64, 1), flags.getBitfield("read"));
    try std.testing.expectEqual(@as(u64, 0), flags.getBitfield("write"));
    try std.testing.expectEqual(@as(u64, 1), flags.getBitfield("execute"));
}

fn testExtractBits() !void {
    const data = [_]u8{ 0b10110101, 0b11001010 };

    // Extract first 4 bits: 0101 = 5
    try std.testing.expectEqual(@as(u64, 0b0101), extractBits(&data, 0, 4));
    // Extract bits 4-7: 1011 = 11
    try std.testing.expectEqual(@as(u64, 0b1011), extractBits(&data, 4, 4));
    // Extract bits 8-11: 1010 = 10
    try std.testing.expectEqual(@as(u64, 0b1010), extractBits(&data, 8, 4));
}

fn testInsertBits() !void {
    var data = [_]u8{ 0, 0 };

    insertBits(&data, 0, 4, 0b1111);
    try std.testing.expectEqual(@as(u8, 0x0F), data[0]);

    insertBits(&data, 4, 4, 0b1010);
    try std.testing.expectEqual(@as(u8, 0xAF), data[0]);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "flags_structure" {
    try testFlagsStructure();
}

test "rgb565" {
    try testRGB565();
}

test "packed_data" {
    try testPackedData();
}

test "sign_extend" {
    try testSignExtend();
}

test "max_values" {
    try testMaxValues();
}

test "bitfield_overwrite" {
    try testBitfieldOverwrite();
}

test "extract_bits" {
    try testExtractBits();
}

test "insert_bits" {
    try testInsertBits();
}
