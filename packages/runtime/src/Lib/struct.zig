//! Python 'struct' module - Interpret bytes as packed binary data
//!
//! Provides functions to pack and unpack binary data according to format strings.
//! Format characters specify byte order, size, and alignment.
//!
//! Mirrors: CPython Lib/struct.py

const std = @import("std");
const builtin = @import("builtin");

pub const StructError = error{
    InvalidFormat,
    BufferTooSmall,
    OutOfMemory,
};

/// Byte order markers
pub const ByteOrder = enum {
    native, // @
    little, // <
    big, // >
    network, // ! (same as big)

    pub fn fromChar(c: u8) ?ByteOrder {
        return switch (c) {
            '@' => .native,
            '=' => .native,
            '<' => .little,
            '>' => .big,
            '!' => .network,
            else => null,
        };
    }
};

/// Calculate the size of a format string
pub fn calcsize(format: []const u8) !usize {
    var size: usize = 0;
    var i: usize = 0;

    // Skip byte order marker
    if (format.len > 0 and ByteOrder.fromChar(format[0]) != null) {
        i = 1;
    }

    while (i < format.len) {
        // Parse optional count
        var count: usize = 1;
        while (i < format.len and format[i] >= '0' and format[i] <= '9') {
            count = count * 10 + (format[i] - '0');
            i += 1;
        }

        if (i >= format.len) break;

        const c = format[i];
        i += 1;

        size += count * switch (c) {
            'x' => 1, // pad byte
            'c' => 1, // char
            'b', 'B' => 1, // signed/unsigned byte
            '?' => 1, // bool
            'h', 'H' => 2, // short
            'i', 'I' => 4, // int
            'l', 'L' => 4, // long
            'q', 'Q' => 8, // long long
            'n', 'N' => @sizeOf(isize), // ssize_t / size_t
            'e' => 2, // half float
            'f' => 4, // float
            'd' => 8, // double
            's', 'p' => count, // string (count is length, not repeat)
            'P' => @sizeOf(usize), // pointer
            else => return error.InvalidFormat,
        };

        // For s and p, count is the length, reset to 1 for next iteration
        if (c == 's' or c == 'p') {
            // Already added count bytes, don't multiply
            size -= count; // Undo the multiplication
            size += count; // Add back correctly
        }
    }

    return size;
}

/// Pack values into bytes according to format
pub fn pack(allocator: std.mem.Allocator, format: []const u8, args: anytype) ![]u8 {
    const size = try calcsize(format);
    const buffer = try allocator.alloc(u8, size);
    errdefer allocator.free(buffer);

    try packInto(buffer, format, args);
    return buffer;
}

/// Pack values into an existing buffer
pub fn packInto(buffer: []u8, format: []const u8, args: anytype) !void {
    var offset: usize = 0;
    var arg_idx: usize = 0;
    var i: usize = 0;

    // Determine byte order
    var byte_order: ByteOrder = .native;
    if (format.len > 0) {
        if (ByteOrder.fromChar(format[0])) |order| {
            byte_order = order;
            i = 1;
        }
    }

    const is_little = switch (byte_order) {
        .native => builtin.cpu.arch.endian() == .little,
        .little => true,
        .big, .network => false,
    };

    while (i < format.len) {
        // Parse optional count
        var count: usize = 1;
        while (i < format.len and format[i] >= '0' and format[i] <= '9') {
            count = count * 10 + (format[i] - '0');
            i += 1;
        }

        if (i >= format.len) break;

        const c = format[i];
        i += 1;

        // Handle each format character
        for (0..count) |_| {
            switch (c) {
                'x' => {
                    buffer[offset] = 0;
                    offset += 1;
                },
                'b' => {
                    const val: i8 = args[arg_idx];
                    arg_idx += 1;
                    buffer[offset] = @bitCast(val);
                    offset += 1;
                },
                'B' => {
                    const val: u8 = args[arg_idx];
                    arg_idx += 1;
                    buffer[offset] = val;
                    offset += 1;
                },
                'h' => {
                    const val: i16 = args[arg_idx];
                    arg_idx += 1;
                    const bytes = if (is_little)
                        std.mem.toBytes(std.mem.nativeToLittle(i16, val))
                    else
                        std.mem.toBytes(std.mem.nativeToBig(i16, val));
                    @memcpy(buffer[offset..][0..2], &bytes);
                    offset += 2;
                },
                'H' => {
                    const val: u16 = args[arg_idx];
                    arg_idx += 1;
                    const bytes = if (is_little)
                        std.mem.toBytes(std.mem.nativeToLittle(u16, val))
                    else
                        std.mem.toBytes(std.mem.nativeToBig(u16, val));
                    @memcpy(buffer[offset..][0..2], &bytes);
                    offset += 2;
                },
                'i', 'l' => {
                    const val: i32 = args[arg_idx];
                    arg_idx += 1;
                    const bytes = if (is_little)
                        std.mem.toBytes(std.mem.nativeToLittle(i32, val))
                    else
                        std.mem.toBytes(std.mem.nativeToBig(i32, val));
                    @memcpy(buffer[offset..][0..4], &bytes);
                    offset += 4;
                },
                'I', 'L' => {
                    const val: u32 = args[arg_idx];
                    arg_idx += 1;
                    const bytes = if (is_little)
                        std.mem.toBytes(std.mem.nativeToLittle(u32, val))
                    else
                        std.mem.toBytes(std.mem.nativeToBig(u32, val));
                    @memcpy(buffer[offset..][0..4], &bytes);
                    offset += 4;
                },
                'q' => {
                    const val: i64 = args[arg_idx];
                    arg_idx += 1;
                    const bytes = if (is_little)
                        std.mem.toBytes(std.mem.nativeToLittle(i64, val))
                    else
                        std.mem.toBytes(std.mem.nativeToBig(i64, val));
                    @memcpy(buffer[offset..][0..8], &bytes);
                    offset += 8;
                },
                'Q' => {
                    const val: u64 = args[arg_idx];
                    arg_idx += 1;
                    const bytes = if (is_little)
                        std.mem.toBytes(std.mem.nativeToLittle(u64, val))
                    else
                        std.mem.toBytes(std.mem.nativeToBig(u64, val));
                    @memcpy(buffer[offset..][0..8], &bytes);
                    offset += 8;
                },
                'f' => {
                    const val: f32 = args[arg_idx];
                    arg_idx += 1;
                    const int_val: u32 = @bitCast(val);
                    const bytes = if (is_little)
                        std.mem.toBytes(std.mem.nativeToLittle(u32, int_val))
                    else
                        std.mem.toBytes(std.mem.nativeToBig(u32, int_val));
                    @memcpy(buffer[offset..][0..4], &bytes);
                    offset += 4;
                },
                'd' => {
                    const val: f64 = args[arg_idx];
                    arg_idx += 1;
                    const int_val: u64 = @bitCast(val);
                    const bytes = if (is_little)
                        std.mem.toBytes(std.mem.nativeToLittle(u64, int_val))
                    else
                        std.mem.toBytes(std.mem.nativeToBig(u64, int_val));
                    @memcpy(buffer[offset..][0..8], &bytes);
                    offset += 8;
                },
                '?' => {
                    const val: bool = args[arg_idx];
                    arg_idx += 1;
                    buffer[offset] = if (val) 1 else 0;
                    offset += 1;
                },
                else => return error.InvalidFormat,
            }
        }
    }
}

/// Unpack bytes into a tuple of values
pub fn unpack(comptime format: []const u8, buffer: []const u8) !UnpackResult(format) {
    return unpackImpl(format, buffer);
}

fn UnpackResult(comptime format: []const u8) type {
    comptime {
        var fields: []const std.builtin.Type.StructField = &.{};
        var i: usize = 0;
        var field_idx: usize = 0;

        // Skip byte order marker
        if (format.len > 0 and ByteOrder.fromChar(format[0]) != null) {
            i = 1;
        }

        while (i < format.len) {
            // Parse optional count
            var count: usize = 1;
            while (i < format.len and format[i] >= '0' and format[i] <= '9') {
                count = count * 10 + (format[i] - '0');
                i += 1;
            }

            if (i >= format.len) break;

            const c = format[i];
            i += 1;

            if (c == 'x') continue; // Skip pad bytes

            for (0..count) |_| {
                const FieldType = switch (c) {
                    'b' => i8,
                    'B', 'c' => u8,
                    'h' => i16,
                    'H' => u16,
                    'i', 'l' => i32,
                    'I', 'L' => u32,
                    'q' => i64,
                    'Q' => u64,
                    'f' => f32,
                    'd' => f64,
                    '?' => bool,
                    else => u8,
                };

                fields = fields ++ &[_]std.builtin.Type.StructField{.{
                    .name = std.fmt.comptimePrint("{d}", .{field_idx}),
                    .type = FieldType,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = 0,
                }};
                field_idx += 1;
            }
        }

        return @Type(.{ .@"struct" = .{
            .layout = .auto,
            .fields = fields,
            .decls = &.{},
            .is_tuple = true,
        } });
    }
}

fn unpackImpl(comptime format: []const u8, buffer: []const u8) !UnpackResult(format) {
    var result: UnpackResult(format) = undefined;
    var offset: usize = 0;
    var field_idx: usize = 0;
    var i: usize = 0;

    // Determine byte order
    comptime var byte_order: ByteOrder = .native;
    if (format.len > 0) {
        if (comptime ByteOrder.fromChar(format[0])) |order| {
            byte_order = order;
            i = 1;
        }
    }

    const is_little = comptime switch (byte_order) {
        .native => builtin.cpu.arch.endian() == .little,
        .little => true,
        .big, .network => false,
    };

    inline while (i < format.len) {
        // Parse optional count
        comptime var count: usize = 1;
        inline while (i < format.len and format[i] >= '0' and format[i] <= '9') {
            count = count * 10 + (format[i] - '0');
            i += 1;
        }

        if (i >= format.len) break;

        const c = format[i];
        i += 1;

        if (c == 'x') {
            offset += count;
            continue;
        }

        inline for (0..count) |_| {
            switch (c) {
                'b' => {
                    @field(result, std.fmt.comptimePrint("{d}", .{field_idx})) = @bitCast(buffer[offset]);
                    offset += 1;
                    field_idx += 1;
                },
                'B', 'c' => {
                    @field(result, std.fmt.comptimePrint("{d}", .{field_idx})) = buffer[offset];
                    offset += 1;
                    field_idx += 1;
                },
                'h' => {
                    const bytes = buffer[offset..][0..2].*;
                    const val = if (is_little)
                        std.mem.littleToNative(i16, @bitCast(bytes))
                    else
                        std.mem.bigToNative(i16, @bitCast(bytes));
                    @field(result, std.fmt.comptimePrint("{d}", .{field_idx})) = val;
                    offset += 2;
                    field_idx += 1;
                },
                'H' => {
                    const bytes = buffer[offset..][0..2].*;
                    const val = if (is_little)
                        std.mem.littleToNative(u16, @bitCast(bytes))
                    else
                        std.mem.bigToNative(u16, @bitCast(bytes));
                    @field(result, std.fmt.comptimePrint("{d}", .{field_idx})) = val;
                    offset += 2;
                    field_idx += 1;
                },
                'i', 'l' => {
                    const bytes = buffer[offset..][0..4].*;
                    const val = if (is_little)
                        std.mem.littleToNative(i32, @bitCast(bytes))
                    else
                        std.mem.bigToNative(i32, @bitCast(bytes));
                    @field(result, std.fmt.comptimePrint("{d}", .{field_idx})) = val;
                    offset += 4;
                    field_idx += 1;
                },
                'I', 'L' => {
                    const bytes = buffer[offset..][0..4].*;
                    const val = if (is_little)
                        std.mem.littleToNative(u32, @bitCast(bytes))
                    else
                        std.mem.bigToNative(u32, @bitCast(bytes));
                    @field(result, std.fmt.comptimePrint("{d}", .{field_idx})) = val;
                    offset += 4;
                    field_idx += 1;
                },
                'q' => {
                    const bytes = buffer[offset..][0..8].*;
                    const val = if (is_little)
                        std.mem.littleToNative(i64, @bitCast(bytes))
                    else
                        std.mem.bigToNative(i64, @bitCast(bytes));
                    @field(result, std.fmt.comptimePrint("{d}", .{field_idx})) = val;
                    offset += 8;
                    field_idx += 1;
                },
                'Q' => {
                    const bytes = buffer[offset..][0..8].*;
                    const val = if (is_little)
                        std.mem.littleToNative(u64, @bitCast(bytes))
                    else
                        std.mem.bigToNative(u64, @bitCast(bytes));
                    @field(result, std.fmt.comptimePrint("{d}", .{field_idx})) = val;
                    offset += 8;
                    field_idx += 1;
                },
                'f' => {
                    const bytes = buffer[offset..][0..4].*;
                    const int_val = if (is_little)
                        std.mem.littleToNative(u32, @bitCast(bytes))
                    else
                        std.mem.bigToNative(u32, @bitCast(bytes));
                    @field(result, std.fmt.comptimePrint("{d}", .{field_idx})) = @bitCast(int_val);
                    offset += 4;
                    field_idx += 1;
                },
                'd' => {
                    const bytes = buffer[offset..][0..8].*;
                    const int_val = if (is_little)
                        std.mem.littleToNative(u64, @bitCast(bytes))
                    else
                        std.mem.bigToNative(u64, @bitCast(bytes));
                    @field(result, std.fmt.comptimePrint("{d}", .{field_idx})) = @bitCast(int_val);
                    offset += 8;
                    field_idx += 1;
                },
                '?' => {
                    @field(result, std.fmt.comptimePrint("{d}", .{field_idx})) = buffer[offset] != 0;
                    offset += 1;
                    field_idx += 1;
                },
                else => {},
            }
        }
    }

    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "calcsize" {
    try std.testing.expectEqual(@as(usize, 1), try calcsize("b"));
    try std.testing.expectEqual(@as(usize, 2), try calcsize("h"));
    try std.testing.expectEqual(@as(usize, 4), try calcsize("i"));
    try std.testing.expectEqual(@as(usize, 8), try calcsize("q"));
    try std.testing.expectEqual(@as(usize, 4), try calcsize("f"));
    try std.testing.expectEqual(@as(usize, 8), try calcsize("d"));
    try std.testing.expectEqual(@as(usize, 6), try calcsize("bhi"));
    try std.testing.expectEqual(@as(usize, 3), try calcsize("3b"));
    try std.testing.expectEqual(@as(usize, 6), try calcsize(">bhi"));
}

test "unpack integers" {
    // Little endian
    const le_data = [_]u8{ 0x01, 0x00, 0x02, 0x00, 0x00, 0x00 };
    const le_result = try unpack("<hi", &le_data);
    try std.testing.expectEqual(@as(i16, 1), le_result[0]);
    try std.testing.expectEqual(@as(i32, 2), le_result[1]);

    // Big endian
    const be_data = [_]u8{ 0x00, 0x01, 0x00, 0x00, 0x00, 0x02 };
    const be_result = try unpack(">hi", &be_data);
    try std.testing.expectEqual(@as(i16, 1), be_result[0]);
    try std.testing.expectEqual(@as(i32, 2), be_result[1]);
}

test "unpack floats" {
    // Little endian float 1.0
    const float_data = [_]u8{ 0x00, 0x00, 0x80, 0x3f };
    const float_result = try unpack("<f", &float_data);
    try std.testing.expectEqual(@as(f32, 1.0), float_result[0]);
}

test "unpack bool" {
    const bool_data = [_]u8{ 0x01, 0x00 };
    const bool_result = try unpack("??", &bool_data);
    try std.testing.expectEqual(true, bool_result[0]);
    try std.testing.expectEqual(false, bool_result[1]);
}

test "unpack with pad bytes" {
    const data = [_]u8{ 0x01, 0x00, 0x02 };
    const result = try unpack("bxb", &data);
    try std.testing.expectEqual(@as(i8, 1), result[0]);
    try std.testing.expectEqual(@as(i8, 2), result[1]);
}
