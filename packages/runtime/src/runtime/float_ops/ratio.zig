/// Float as_integer_ratio operations
const std = @import("std");
const bigint = @import("bigint");
const BigInt = bigint.BigInt;
const type_predicates = @import("../type_predicates.zig");

/// Python error types
pub const PythonError = error{
    ZeroDivisionError,
    IndexError,
    ValueError,
    TypeError,
    KeyError,
    OverflowError,
    OutOfMemory,
    Exception,
};

/// Result type for as_integer_ratio with BigInt support
pub const IntegerRatioResult = struct {
    numerator: BigInt,
    denominator: BigInt,

    pub fn deinit(self: *IntegerRatioResult) void {
        self.numerator.deinit();
        self.denominator.deinit();
    }
};

/// float.as_integer_ratio() - Returns (numerator, denominator) tuple with BigInt
/// Python: (0.5).as_integer_ratio() -> (1, 2)
/// Uses BigInt to handle extreme exponents (e.g., 10^-100 requires 2^152 denominator)
pub fn floatAsIntegerRatioBigInt(allocator: std.mem.Allocator, value: anytype) !IntegerRatioResult {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    const f: f64 = if (type_predicates.isFloatInfo(type_info))
        @as(f64, value)
    else if (type_predicates.isIntInfo(type_info))
        @as(f64, @floatFromInt(value))
    else if (type_info == .@"struct" and @hasField(T, "__base_value__"))
        @as(f64, value.__base_value__)
    else
        0.0;

    if (std.math.isNan(f)) {
        return PythonError.ValueError;
    }
    if (std.math.isInf(f)) {
        return PythonError.OverflowError;
    }

    if (f == 0.0) {
        var num = try BigInt.fromInt(allocator, 0);
        errdefer num.deinit();
        const den = try BigInt.fromInt(allocator, 1);
        return IntegerRatioResult{ .numerator = num, .denominator = den };
    }

    const bits: u64 = @bitCast(f);
    const is_negative = (bits >> 63) != 0;
    const raw_exponent: i64 = @as(i64, @intCast((bits >> 52) & 0x7FF)) - 1023;
    var mantissa: u64 = bits & 0xFFFFFFFFFFFFF;

    if (raw_exponent > -1023) {
        mantissa |= (@as(u64, 1) << 52);
    }

    var trailing_zeros: usize = 0;
    var temp_mantissa = mantissa;
    while (temp_mantissa != 0 and (temp_mantissa & 1) == 0) {
        temp_mantissa >>= 1;
        trailing_zeros += 1;
    }

    var numerator = try BigInt.fromInt(allocator, @as(i64, @intCast(temp_mantissa)));
    errdefer numerator.deinit();
    if (is_negative) numerator.negate();

    const effective_exponent = raw_exponent - 52 + @as(i64, @intCast(trailing_zeros));

    var denominator: BigInt = undefined;
    if (effective_exponent >= 0) {
        const shifted = try numerator.shl(@intCast(effective_exponent), allocator);
        numerator.deinit();
        numerator = shifted;
        denominator = try BigInt.fromInt(allocator, 1);
    } else {
        const shift_amount: usize = @intCast(-effective_exponent);
        var one = try BigInt.fromInt(allocator, 1);
        errdefer one.deinit();
        denominator = try one.shl(shift_amount, allocator);
        one.deinit();
    }
    errdefer denominator.deinit();

    return IntegerRatioResult{ .numerator = numerator, .denominator = denominator };
}

/// float.as_integer_ratio() - Legacy i64 version for small values
/// NOTE: Use floatAsIntegerRatioBigInt for proper handling of extreme exponents
pub fn floatAsIntegerRatio(value: anytype) PythonError!struct { i64, i64 } {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    const f: f64 = if (type_predicates.isFloatInfo(type_info))
        @as(f64, value)
    else if (type_predicates.isIntInfo(type_info))
        @as(f64, @floatFromInt(value))
    else if (type_info == .@"struct" and @hasField(T, "__base_value__"))
        @as(f64, value.__base_value__)
    else
        0.0;

    if (std.math.isNan(f)) {
        return PythonError.ValueError;
    }
    if (std.math.isInf(f)) {
        return PythonError.OverflowError;
    }

    if (f == 0.0) {
        return .{ 0, 1 };
    }

    const bits: u64 = @bitCast(f);
    const sign: i64 = if ((bits >> 63) != 0) -1 else 1;
    const exponent: i64 = @as(i64, @intCast((bits >> 52) & 0x7FF)) - 1023;
    var mantissa: u64 = bits & 0xFFFFFFFFFFFFF;

    if (exponent > -1023) {
        mantissa |= (1 << 52);
    }

    var numerator: i64 = sign * @as(i64, @intCast(mantissa));
    var denominator: i64 = undefined;

    const power = 52 - exponent;
    if (power >= 0) {
        var trailing_zeros: i64 = 0;
        var temp_mantissa = mantissa;
        while (temp_mantissa != 0 and (temp_mantissa & 1) == 0 and trailing_zeros < power) {
            temp_mantissa >>= 1;
            trailing_zeros += 1;
        }
        const reduced_power = power - trailing_zeros;
        if (reduced_power <= 62) {
            numerator = sign * @as(i64, @intCast(temp_mantissa));
            const shift: u6 = @intCast(reduced_power);
            denominator = @as(i64, 1) << shift;
        } else {
            numerator = sign * @as(i64, @intCast(temp_mantissa));
            denominator = @as(i64, 1) << 62;
        }
    } else {
        const shift: u6 = @intCast(@min(-power, 52));
        numerator = numerator << shift;
        denominator = 1;
    }

    var a: i64 = if (numerator < 0) -numerator else numerator;
    var b: i64 = denominator;
    while (b != 0) {
        const t = b;
        b = @mod(a, b);
        a = t;
    }
    if (a > 0) {
        numerator = @divTrunc(numerator, a);
        denominator = @divTrunc(denominator, a);
    }

    return .{ numerator, denominator };
}
