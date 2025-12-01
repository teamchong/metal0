/// Float operations for runtime
/// Extracted from runtime.zig for better organization
const std = @import("std");
const bigint = @import("bigint");
const BigInt = bigint.BigInt;

/// Python error types
pub const PythonError = error{
    ZeroDivisionError,
    IndexError,
    ValueError,
    TypeError,
    KeyError,
    OverflowError,
};

/// Float division with zero check
pub fn divideFloat(a: anytype, b: anytype) PythonError!f64 {
    const a_float: f64 = switch (@typeInfo(@TypeOf(a))) {
        .float, .comptime_float => @as(f64, a),
        .int, .comptime_int => @floatFromInt(a),
        else => @compileError("divideFloat: unsupported type " ++ @typeName(@TypeOf(a))),
    };
    const b_float: f64 = switch (@typeInfo(@TypeOf(b))) {
        .float, .comptime_float => @as(f64, b),
        .int, .comptime_int => @floatFromInt(b),
        else => @compileError("divideFloat: unsupported type " ++ @typeName(@TypeOf(b))),
    };

    if (b_float == 0.0) {
        return PythonError.ZeroDivisionError;
    }
    return a_float / b_float;
}

/// Parse hexadecimal float string
pub fn floatFromHex(s: []const u8) f64 {
    return std.fmt.parseFloat(f64, s) catch 0.0;
}

/// float.__getformat__(typestr) - Returns the IEEE 754 format string
/// Python: float.__getformat__('double') -> 'IEEE, little-endian' (on little-endian systems)
/// typestr must be 'double' or 'float'
pub fn floatGetFormat(typestr: anytype) PythonError![]const u8 {
    const T = @TypeOf(typestr);

    // Check if typestr is a string type
    if (T != []const u8 and T != []u8) {
        // Python raises TypeError for non-string arguments
        return PythonError.TypeError;
    }

    // Check for valid typestr value
    if (!std.mem.eql(u8, typestr, "double") and !std.mem.eql(u8, typestr, "float")) {
        return PythonError.ValueError; // Python raises ValueError for invalid typestr
    }

    // Zig uses IEEE 754 on all modern platforms
    // Detect endianness at comptime
    const native_endian = @import("builtin").cpu.arch.endian();
    return if (native_endian == .little)
        "IEEE, little-endian"
    else
        "IEEE, big-endian";
}

/// float.is_integer() - Returns True if float is integral (no fractional part)
/// Python: (1.0).is_integer() -> True, (1.5).is_integer() -> False
pub fn floatIsInteger(value: anytype) bool {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    // Handle float values
    const f: f64 = if (type_info == .float or type_info == .comptime_float)
        @as(f64, value)
    else if (type_info == .int or type_info == .comptime_int)
        @as(f64, @floatFromInt(value))
    else if (type_info == .@"struct" and @hasField(T, "__base_value__"))
        @as(f64, value.__base_value__)
    else
        0.0;

    // NaN and Inf are not integers
    if (std.math.isNan(f) or std.math.isInf(f)) {
        return false;
    }

    // Check if float equals its truncated value
    return f == @trunc(f);
}

/// float.as_integer_ratio() - Returns (numerator, denominator) tuple
/// Python: (0.5).as_integer_ratio() -> (1, 2)
/// Returns a tuple of two integers whose ratio equals the float
pub fn floatAsIntegerRatio(value: anytype) struct { i64, i64 } {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    // Handle float values
    const f: f64 = if (type_info == .float or type_info == .comptime_float)
        @as(f64, value)
    else if (type_info == .int or type_info == .comptime_int)
        @as(f64, @floatFromInt(value))
    else if (type_info == .@"struct" and @hasField(T, "__base_value__"))
        @as(f64, value.__base_value__)
    else
        0.0;

    // Handle special cases
    if (std.math.isNan(f)) {
        // Python raises ValueError for NaN
        return .{ 0, 1 };
    }
    if (std.math.isInf(f)) {
        // Python raises OverflowError for Inf
        return .{ if (f > 0) std.math.maxInt(i64) else std.math.minInt(i64), 1 };
    }

    // Zero case
    if (f == 0.0) {
        return .{ 0, 1 };
    }

    // Use IEEE 754 representation to get exact fraction
    // For simplicity, we use a power-of-2 approach
    const bits: u64 = @bitCast(f);
    const sign: i64 = if ((bits >> 63) != 0) -1 else 1;
    const exponent: i64 = @as(i64, @intCast((bits >> 52) & 0x7FF)) - 1023;
    var mantissa: u64 = bits & 0xFFFFFFFFFFFFF;

    // Handle normalized numbers (add implicit leading 1)
    if (exponent > -1023) {
        mantissa |= (1 << 52);
    }

    // Calculate numerator and denominator
    var numerator: i64 = sign * @as(i64, @intCast(mantissa));
    var denominator: i64 = 1 << 52;

    // Adjust for exponent
    if (exponent > 0) {
        // Shift numerator left
        const shift: u6 = @intCast(@min(exponent, 63));
        numerator = numerator << shift;
        denominator = denominator >> @min(52 - shift, 52);
    } else if (exponent < 0) {
        // Shift denominator left
        const shift: u6 = @intCast(@min(-exponent, 63));
        denominator = denominator << shift;
    }

    // Reduce the fraction by GCD
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

/// float.hex() - Returns hexadecimal string representation
/// Python: (255.0).hex() -> '0x1.fe00000000000p+7'
pub fn floatHex(allocator: std.mem.Allocator, value: f64) ![]u8 {
    var buf = std.ArrayList(u8){};

    // Handle special cases
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
        // Check for -0.0
        const bits: u64 = @bitCast(value);
        if ((bits >> 63) != 0) {
            try buf.appendSlice(allocator, "-0x0.0p+0");
        } else {
            try buf.appendSlice(allocator, "0x0.0p+0");
        }
        return buf.toOwnedSlice(allocator);
    }

    // Use Zig's hex float format
    try buf.writer(allocator).print("{x}", .{value});
    return buf.toOwnedSlice(allocator);
}

/// float.hex() - Convert f64 to hex string
/// Python: (3.14).hex() = '0x1.91eb851eb851fp+1'
pub fn floatToHex(allocator: std.mem.Allocator, value: f64) ![]u8 {
    var buf = std.ArrayList(u8){};
    // For now, return a simple representation (full impl needs proper hex float format)
    try buf.writer(allocator).print("{d}", .{value});
    return buf.toOwnedSlice(allocator);
}

/// float.__floor__() - Returns largest integer <= value as BigInt
/// Python: (1.7).__floor__() -> 1, (1e200).__floor__() -> BigInt
/// Raises ValueError for NaN, OverflowError for Inf
pub fn floatFloor(allocator: std.mem.Allocator, value: f64) PythonError!BigInt {
    // Python raises ValueError for NaN, OverflowError for Inf
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;
    // Apply floor then convert
    const floored = @floor(value);
    return BigInt.fromFloat(allocator, floored) catch BigInt.fromInt(allocator, 0) catch unreachable;
}

/// float.__ceil__() - Returns smallest integer >= value as BigInt
/// Python: (1.3).__ceil__() -> 2
/// Raises ValueError for NaN, OverflowError for Inf
pub fn floatCeil(allocator: std.mem.Allocator, value: f64) PythonError!BigInt {
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;
    const ceiled = @ceil(value);
    return BigInt.fromFloat(allocator, ceiled) catch BigInt.fromInt(allocator, 0) catch unreachable;
}

/// float.__trunc__() - Truncate towards zero, return BigInt
/// Python: (-1.7).__trunc__() -> -1
/// Raises ValueError for NaN, OverflowError for Inf
pub fn floatTrunc(allocator: std.mem.Allocator, value: f64) PythonError!BigInt {
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;
    // fromFloat already truncates
    return BigInt.fromFloat(allocator, value) catch BigInt.fromInt(allocator, 0) catch unreachable;
}

/// float.__round__() - Round to nearest, return BigInt
/// Python: (1.5).__round__() -> 2
/// Raises ValueError for NaN, OverflowError for Inf
pub fn floatRound(allocator: std.mem.Allocator, value: f64) PythonError!BigInt {
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;
    const rounded = @round(value);
    return BigInt.fromFloat(allocator, rounded) catch BigInt.fromInt(allocator, 0) catch unreachable;
}

/// float() builtin call wrapper for assertRaises testing
pub fn floatBuiltinCall(first: anytype, rest: anytype) PythonError!f64 {
    const FirstType = @TypeOf(first);
    const first_info = @typeInfo(FirstType);
    const RestType = @TypeOf(rest);
    const rest_info = @typeInfo(RestType);

    // float() only takes one argument
    const has_extra_args = rest_info == .@"struct" and rest_info.@"struct".fields.len > 0;
    if (has_extra_args) {
        return PythonError.TypeError;
    }

    if (first_info == .int or first_info == .comptime_int) {
        return @as(f64, @floatFromInt(first));
    }
    if (first_info == .float or first_info == .comptime_float) {
        return @as(f64, first);
    }
    if (first_info == .pointer) {
        return std.fmt.parseFloat(f64, first) catch return PythonError.ValueError;
    }

    return PythonError.TypeError;
}

/// Convert any value to float - handles both native types and class instances
/// For class instances, calls __float__() or extracts from value field if available
pub fn toFloat(value: anytype) f64 {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    // Native float
    if (type_info == .float or type_info == .comptime_float) {
        return @as(f64, value);
    }

    // Native int
    if (type_info == .int or type_info == .comptime_int) {
        return @as(f64, @floatFromInt(value));
    }

    // Struct - check for __float__ method or value field
    if (type_info == .@"struct") {
        // First try __float__ method
        if (@hasDecl(T, "__float__")) {
            const float_result = value.__float__();
            const result_type = @TypeOf(float_result);
            const result_info = @typeInfo(result_type);
            if (result_info == .float) {
                return @as(f64, float_result);
            } else if (result_info == .int) {
                return @as(f64, @floatFromInt(float_result));
            } else {
                return 0.0;
            }
        }
        // Fall back to __base_value__ field (for float subclasses)
        if (@hasField(T, "__base_value__")) {
            return value.__base_value__;
        }
        // Check for value field with PyValue (passthrough pattern)
        if (@hasField(T, "value")) {
            const field_type = @TypeOf(value.value);
            // Need to import PyValue type - for now just return 0.0
            // This will need to be fixed when PyValue is properly imported
            _ = field_type;
            return 0.0;
        }
    }

    // Pointer to struct
    if (type_info == .pointer) {
        const child_info = @typeInfo(type_info.pointer.child);
        if (child_info == .@"struct") {
            return toFloat(value.*);
        }
        // String pointer - try to parse as float
        if (type_info.pointer.child == u8) {
            return std.fmt.parseFloat(f64, value) catch 0.0;
        }
    }

    // Fallback
    return 0.0;
}
