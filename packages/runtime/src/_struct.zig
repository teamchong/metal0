/// _struct - C accelerator module for struct
/// Interpret bytes as packed binary data
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Byte order/size/alignment specifiers
pub const ByteOrder = enum {
    native, // @
    little, // <
    big, // >
    network, // ! (big-endian)

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

/// Pack values into bytes according to format string
pub fn pack(comptime format: []const u8, args: anytype) ![calcsize(format)]u8 {
    var buffer: [calcsize(format)]u8 = undefined;
    const order = getByteOrder(format);
    comptime var fmt_idx: usize = if (ByteOrder.fromChar(format[0]) != null) 1 else 0;
    comptime var arg_idx: usize = 0;
    var buf_idx: usize = 0;

    inline while (fmt_idx < format.len) {
        const c = format[fmt_idx];
        fmt_idx += 1;

        switch (c) {
            'x' => {
                // Pad byte
                buffer[buf_idx] = 0;
                buf_idx += 1;
            },
            'c' => {
                // char
                buffer[buf_idx] = args[arg_idx];
                arg_idx += 1;
                buf_idx += 1;
            },
            'b' => {
                // signed char
                const val: i8 = args[arg_idx];
                buffer[buf_idx] = @bitCast(val);
                arg_idx += 1;
                buf_idx += 1;
            },
            'B' => {
                // unsigned char
                buffer[buf_idx] = args[arg_idx];
                arg_idx += 1;
                buf_idx += 1;
            },
            '?' => {
                // bool
                buffer[buf_idx] = if (args[arg_idx]) 1 else 0;
                arg_idx += 1;
                buf_idx += 1;
            },
            'h' => {
                // short (i16)
                const val: i16 = args[arg_idx];
                writeInt(i16, buffer[buf_idx..][0..2], val, order);
                arg_idx += 1;
                buf_idx += 2;
            },
            'H' => {
                // unsigned short (u16)
                const val: u16 = args[arg_idx];
                writeInt(u16, buffer[buf_idx..][0..2], val, order);
                arg_idx += 1;
                buf_idx += 2;
            },
            'i', 'l' => {
                // int/long (i32)
                const val: i32 = args[arg_idx];
                writeInt(i32, buffer[buf_idx..][0..4], val, order);
                arg_idx += 1;
                buf_idx += 4;
            },
            'I', 'L' => {
                // unsigned int/long (u32)
                const val: u32 = args[arg_idx];
                writeInt(u32, buffer[buf_idx..][0..4], val, order);
                arg_idx += 1;
                buf_idx += 4;
            },
            'q' => {
                // long long (i64)
                const val: i64 = args[arg_idx];
                writeInt(i64, buffer[buf_idx..][0..8], val, order);
                arg_idx += 1;
                buf_idx += 8;
            },
            'Q' => {
                // unsigned long long (u64)
                const val: u64 = args[arg_idx];
                writeInt(u64, buffer[buf_idx..][0..8], val, order);
                arg_idx += 1;
                buf_idx += 8;
            },
            'f' => {
                // float (f32)
                const val: f32 = args[arg_idx];
                const bits: u32 = @bitCast(val);
                writeInt(u32, buffer[buf_idx..][0..4], bits, order);
                arg_idx += 1;
                buf_idx += 4;
            },
            'd' => {
                // double (f64)
                const val: f64 = args[arg_idx];
                const bits: u64 = @bitCast(val);
                writeInt(u64, buffer[buf_idx..][0..8], bits, order);
                arg_idx += 1;
                buf_idx += 8;
            },
            ' ' => {}, // Skip spaces
            else => {},
        }
    }

    return buffer;
}

/// Unpack bytes into values according to format string
pub fn unpack(comptime format: []const u8, buffer: []const u8) UnpackResult(format) {
    const order = getByteOrder(format);
    var result: UnpackResult(format) = undefined;
    comptime var fmt_idx: usize = if (ByteOrder.fromChar(format[0]) != null) 1 else 0;
    comptime var field_idx: usize = 0;
    var buf_idx: usize = 0;

    inline while (fmt_idx < format.len) {
        const c = format[fmt_idx];
        fmt_idx += 1;

        switch (c) {
            'x' => {
                buf_idx += 1;
            },
            'c' => {
                result[field_idx] = buffer[buf_idx];
                field_idx += 1;
                buf_idx += 1;
            },
            'b' => {
                result[field_idx] = @bitCast(buffer[buf_idx]);
                field_idx += 1;
                buf_idx += 1;
            },
            'B' => {
                result[field_idx] = buffer[buf_idx];
                field_idx += 1;
                buf_idx += 1;
            },
            '?' => {
                result[field_idx] = buffer[buf_idx] != 0;
                field_idx += 1;
                buf_idx += 1;
            },
            'h' => {
                result[field_idx] = readInt(i16, buffer[buf_idx..][0..2], order);
                field_idx += 1;
                buf_idx += 2;
            },
            'H' => {
                result[field_idx] = readInt(u16, buffer[buf_idx..][0..2], order);
                field_idx += 1;
                buf_idx += 2;
            },
            'i', 'l' => {
                result[field_idx] = readInt(i32, buffer[buf_idx..][0..4], order);
                field_idx += 1;
                buf_idx += 4;
            },
            'I', 'L' => {
                result[field_idx] = readInt(u32, buffer[buf_idx..][0..4], order);
                field_idx += 1;
                buf_idx += 4;
            },
            'q' => {
                result[field_idx] = readInt(i64, buffer[buf_idx..][0..8], order);
                field_idx += 1;
                buf_idx += 8;
            },
            'Q' => {
                result[field_idx] = readInt(u64, buffer[buf_idx..][0..8], order);
                field_idx += 1;
                buf_idx += 8;
            },
            'f' => {
                const bits = readInt(u32, buffer[buf_idx..][0..4], order);
                result[field_idx] = @bitCast(bits);
                field_idx += 1;
                buf_idx += 4;
            },
            'd' => {
                const bits = readInt(u64, buffer[buf_idx..][0..8], order);
                result[field_idx] = @bitCast(bits);
                field_idx += 1;
                buf_idx += 8;
            },
            ' ' => {},
            else => {},
        }
    }

    return result;
}

/// Calculate the size of the struct for a format string
pub fn calcsize(comptime format: []const u8) usize {
    comptime var size: usize = 0;
    comptime var i: usize = if (format.len > 0 and ByteOrder.fromChar(format[0]) != null) 1 else 0;

    inline while (i < format.len) {
        const c = format[i];
        i += 1;
        size += switch (c) {
            'x', 'c', 'b', 'B', '?' => 1,
            'h', 'H' => 2,
            'i', 'I', 'l', 'L', 'f' => 4,
            'q', 'Q', 'd' => 8,
            ' ' => 0,
            else => 0,
        };
    }

    return size;
}

/// Generate result type for unpack
fn UnpackResult(comptime format: []const u8) type {
    comptime var count: usize = 0;
    comptime var i: usize = if (format.len > 0 and ByteOrder.fromChar(format[0]) != null) 1 else 0;

    inline while (i < format.len) {
        const c = format[i];
        i += 1;
        switch (c) {
            'x', ' ' => {},
            'c', 'b', 'B', '?', 'h', 'H', 'i', 'I', 'l', 'L', 'q', 'Q', 'f', 'd' => {
                count += 1;
            },
            else => {},
        }
    }

    var types: [count]type = undefined;
    var type_idx: usize = 0;
    i = if (format.len > 0 and ByteOrder.fromChar(format[0]) != null) 1 else 0;

    inline while (i < format.len) {
        const c = format[i];
        i += 1;
        switch (c) {
            'c', 'B' => {
                types[type_idx] = u8;
                type_idx += 1;
            },
            'b' => {
                types[type_idx] = i8;
                type_idx += 1;
            },
            '?' => {
                types[type_idx] = bool;
                type_idx += 1;
            },
            'h' => {
                types[type_idx] = i16;
                type_idx += 1;
            },
            'H' => {
                types[type_idx] = u16;
                type_idx += 1;
            },
            'i', 'l' => {
                types[type_idx] = i32;
                type_idx += 1;
            },
            'I', 'L' => {
                types[type_idx] = u32;
                type_idx += 1;
            },
            'q' => {
                types[type_idx] = i64;
                type_idx += 1;
            },
            'Q' => {
                types[type_idx] = u64;
                type_idx += 1;
            },
            'f' => {
                types[type_idx] = f32;
                type_idx += 1;
            },
            'd' => {
                types[type_idx] = f64;
                type_idx += 1;
            },
            else => {},
        }
    }

    return std.meta.Tuple(&types);
}

fn getByteOrder(comptime format: []const u8) ByteOrder {
    if (format.len > 0) {
        if (ByteOrder.fromChar(format[0])) |order| {
            return order;
        }
    }
    return .native;
}

fn writeInt(comptime T: type, buffer: *[@sizeOf(T)]u8, value: T, order: ByteOrder) void {
    const endian: std.builtin.Endian = switch (order) {
        .native => .little, // Assume little-endian for native
        .little => .little,
        .big, .network => .big,
    };
    std.mem.writeInt(T, buffer, value, endian);
}

fn readInt(comptime T: type, buffer: *const [@sizeOf(T)]u8, order: ByteOrder) T {
    const endian: std.builtin.Endian = switch (order) {
        .native => .little,
        .little => .little,
        .big, .network => .big,
    };
    return std.mem.readInt(T, buffer, endian);
}

// ============================================================================
// Struct object for repeated pack/unpack with same format
// ============================================================================

pub fn Struct(comptime format: []const u8) type {
    return struct {
        pub const size = calcsize(format);

        pub fn packValues(args: anytype) ![size]u8 {
            return pack(format, args);
        }

        pub fn unpackBytes(buffer: []const u8) UnpackResult(format) {
            return unpack(format, buffer);
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "calcsize" {
    try std.testing.expectEqual(@as(usize, 1), calcsize("b"));
    try std.testing.expectEqual(@as(usize, 2), calcsize("h"));
    try std.testing.expectEqual(@as(usize, 4), calcsize("i"));
    try std.testing.expectEqual(@as(usize, 8), calcsize("q"));
    try std.testing.expectEqual(@as(usize, 4), calcsize("f"));
    try std.testing.expectEqual(@as(usize, 8), calcsize("d"));
    try std.testing.expectEqual(@as(usize, 6), calcsize("bhi"));
    try std.testing.expectEqual(@as(usize, 6), calcsize("<bhi"));
}

test "pack and unpack integers" {
    const packed_data = try pack("<hiq", .{ @as(i16, 1234), @as(i32, 567890), @as(i64, 123456789012345) });
    try std.testing.expectEqual(@as(usize, 14), packed_data.len);

    const unpacked = unpack("<hiq", &packed_data);
    try std.testing.expectEqual(@as(i16, 1234), unpacked[0]);
    try std.testing.expectEqual(@as(i32, 567890), unpacked[1]);
    try std.testing.expectEqual(@as(i64, 123456789012345), unpacked[2]);
}

test "pack and unpack floats" {
    const packed_data = try pack("<fd", .{ @as(f32, 3.14), @as(f64, 2.71828) });
    try std.testing.expectEqual(@as(usize, 12), packed_data.len);

    const unpacked = unpack("<fd", &packed_data);
    try std.testing.expectApproxEqRel(@as(f32, 3.14), unpacked[0], 0.0001);
    try std.testing.expectApproxEqRel(@as(f64, 2.71828), unpacked[1], 0.00001);
}

test "big endian" {
    const packed_be = try pack(">H", .{@as(u16, 0x1234)});
    try std.testing.expectEqual(@as(u8, 0x12), packed_be[0]);
    try std.testing.expectEqual(@as(u8, 0x34), packed_be[1]);
}

test "little endian" {
    const packed_le = try pack("<H", .{@as(u16, 0x1234)});
    try std.testing.expectEqual(@as(u8, 0x34), packed_le[0]);
    try std.testing.expectEqual(@as(u8, 0x12), packed_le[1]);
}

test "struct object" {
    const S = Struct("<hi");
    try std.testing.expectEqual(@as(usize, 6), S.size);

    const packed_s = try S.packValues(.{ @as(i16, 100), @as(i32, 200) });
    const unpacked = S.unpackBytes(&packed_s);
    try std.testing.expectEqual(@as(i16, 100), unpacked[0]);
    try std.testing.expectEqual(@as(i32, 200), unpacked[1]);
}
