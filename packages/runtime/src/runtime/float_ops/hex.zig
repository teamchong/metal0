/// Float hex formatting operations
const std = @import("std");

/// Parse hexadecimal float string
pub fn floatFromHex(s: []const u8) f64 {
    return std.fmt.parseFloat(f64, s) catch 0.0;
}

/// float.hex() - Returns hexadecimal string representation
/// Python: (255.0).hex() -> '0x1.fe00000000000p+7'
pub fn floatHex(allocator: std.mem.Allocator, value: f64) ![]u8 {
    var buf = std.ArrayList(u8){};

    if (std.math.isNan(value)) {
        try buf.appendSlice(allocator, "nan");
        return buf.toOwnedSlice(allocator);
    }
    if (std.math.isInf(value)) {
        if (value < 0) {
            try buf.appendSlice(allocator, "-inf");
        } else {
            try buf.appendSlice(allocator, "inf");
        }
        return buf.toOwnedSlice(allocator);
    }
    if (value == 0.0) {
        const bits: u64 = @bitCast(value);
        if ((bits >> 63) != 0) {
            try buf.appendSlice(allocator, "-0x0.0p+0");
        } else {
            try buf.appendSlice(allocator, "0x0.0p+0");
        }
        return buf.toOwnedSlice(allocator);
    }

    try buf.writer(allocator).print("{x}", .{value});
    return buf.toOwnedSlice(allocator);
}

/// float.hex() - Convert f64 to hex string in Python format
/// Python: (3.14).hex() = '0x1.91eb851eb851fp+1'
/// Format: 0x[+-]h.hhhhhhhhhhhhhhp[+-]d
pub fn floatToHex(allocator: std.mem.Allocator, value: f64) ![]u8 {
    var buf = std.ArrayList(u8){};

    if (std.math.isNan(value)) {
        try buf.appendSlice(allocator, "nan");
        return buf.toOwnedSlice(allocator);
    }
    if (std.math.isInf(value)) {
        if (value < 0) {
            try buf.appendSlice(allocator, "-inf");
        } else {
            try buf.appendSlice(allocator, "inf");
        }
        return buf.toOwnedSlice(allocator);
    }
    if (value == 0.0) {
        if (@as(u64, @bitCast(value)) >> 63 == 1) {
            try buf.appendSlice(allocator, "-0x0.0p+0");
        } else {
            try buf.appendSlice(allocator, "0x0.0p+0");
        }
        return buf.toOwnedSlice(allocator);
    }

    const bits: u64 = @bitCast(value);
    const sign: u1 = @intCast((bits >> 63) & 1);
    const exp_bits: u11 = @intCast((bits >> 52) & 0x7FF);
    const mantissa: u52 = @intCast(bits & 0xFFFFFFFFFFFFF);

    if (sign == 1) {
        try buf.append(allocator, '-');
    }

    try buf.appendSlice(allocator, "0x");

    const exponent: i64 = if (exp_bits == 0)
        -1022
    else
        @as(i64, @intCast(exp_bits)) - 1023;

    const leading: u8 = if (exp_bits == 0) '0' else '1';
    try buf.append(allocator, leading);
    try buf.append(allocator, '.');

    var hex_digits: [13]u8 = undefined;
    var digit_count: usize = 0;

    for (0..13) |i| {
        const shift: u6 = @intCast(52 - (i + 1) * 4);
        const digit: u4 = @intCast((mantissa >> shift) & 0xF);
        hex_digits[i] = "0123456789abcdef"[digit];
        if (digit != 0 or digit_count > 0) {
            digit_count = i + 1;
        }
    }

    const digits_to_write = if (digit_count == 0) 1 else digit_count;
    try buf.appendSlice(allocator, hex_digits[0..digits_to_write]);

    try buf.append(allocator, 'p');
    if (exponent >= 0) {
        try buf.append(allocator, '+');
    }
    try buf.writer(allocator).print("{d}", .{exponent});

    return buf.toOwnedSlice(allocator);
}
