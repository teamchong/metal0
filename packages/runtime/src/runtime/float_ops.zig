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
    OutOfMemory, // Python's MemoryError
    Exception, // Generic exception catch-all
};

/// Convert any numeric type to f64 (simple version for mixed arithmetic)
pub inline fn numToFloat(value: anytype) f64 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    if (info == .float or info == .comptime_float) {
        return @floatCast(value);
    } else if (info == .int or info == .comptime_int) {
        return @floatFromInt(value);
    } else if (T == @import("bigint").BigInt) {
        return value.toFloat();
    } else {
        @compileError("numToFloat: unsupported type " ++ @typeName(T));
    }
}

/// Subtract two numbers, handling mixed int/float types (returns f64)
pub inline fn subtractNum(a: anytype, b: anytype) f64 {
    return numToFloat(a) - numToFloat(b);
}

/// Add two numbers, handling mixed int/float types
/// If both are integers, returns i64. Otherwise returns f64.
pub inline fn addNum(a: anytype, b: anytype) AddResultType(@TypeOf(a), @TypeOf(b)) {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);

    // Both integers -> integer result
    if ((a_info == .int or a_info == .comptime_int) and (b_info == .int or b_info == .comptime_int)) {
        // Cast to i64 for consistent result
        const a_i64: i64 = if (a_info == .comptime_int) a else @intCast(a);
        const b_i64: i64 = if (b_info == .comptime_int) b else @intCast(b);
        return a_i64 + b_i64;
    }
    // Otherwise float result
    return numToFloat(a) + numToFloat(b);
}

/// Computes result type for addNum: i64 if both int, f64 otherwise
fn AddResultType(comptime A: type, comptime B: type) type {
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);
    if ((a_info == .int or a_info == .comptime_int) and (b_info == .int or b_info == .comptime_int)) {
        return i64;
    }
    return f64;
}

/// Multiply two numbers, handling mixed int/float types (returns f64)
pub inline fn mulNum(a: anytype, b: anytype) f64 {
    return numToFloat(a) * numToFloat(b);
}

/// Float division with zero check
pub fn divideFloat(a: anytype, b: anytype) PythonError!f64 {
    const a_float = numToFloat(a);
    const b_float = numToFloat(b);

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
/// Returns a tuple of two integers whose ratio equals the float exactly
/// Uses BigInt to handle extreme exponents (e.g., 10^-100 requires 2^152 denominator)
/// Raises ValueError for NaN, OverflowError for Inf
pub fn floatAsIntegerRatioBigInt(allocator: std.mem.Allocator, value: anytype) !IntegerRatioResult {
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

    // Handle special cases - Python raises for these
    if (std.math.isNan(f)) {
        return PythonError.ValueError;
    }
    if (std.math.isInf(f)) {
        return PythonError.OverflowError;
    }

    // Zero case
    if (f == 0.0) {
        var num = try BigInt.fromInt(allocator, 0);
        errdefer num.deinit();
        const den = try BigInt.fromInt(allocator, 1);
        return IntegerRatioResult{ .numerator = num, .denominator = den };
    }

    // Use IEEE 754 representation to get exact fraction
    const bits: u64 = @bitCast(f);
    const is_negative = (bits >> 63) != 0;
    const raw_exponent: i64 = @as(i64, @intCast((bits >> 52) & 0x7FF)) - 1023;
    var mantissa: u64 = bits & 0xFFFFFFFFFFFFF;

    // Handle normalized numbers (add implicit leading 1)
    if (raw_exponent > -1023) {
        mantissa |= (@as(u64, 1) << 52);
    }

    // Calculate numerator and denominator
    // Float value = mantissa * 2^(exponent - 52) for normalized numbers
    // So: value = mantissa / 2^(52 - exponent)

    // First, find how many trailing zeros are in mantissa (can divide both by 2^k)
    var trailing_zeros: usize = 0;
    var temp_mantissa = mantissa;
    while (temp_mantissa != 0 and (temp_mantissa & 1) == 0) {
        temp_mantissa >>= 1;
        trailing_zeros += 1;
    }

    // Create numerator from reduced mantissa
    var numerator = try BigInt.fromInt(allocator, @as(i64, @intCast(temp_mantissa)));
    errdefer numerator.deinit();
    if (is_negative) numerator.negate();

    // The effective power of 2 in the denominator is (52 - exponent) - trailing_zeros
    const effective_exponent = raw_exponent - 52 + @as(i64, @intCast(trailing_zeros));

    var denominator: BigInt = undefined;
    if (effective_exponent >= 0) {
        // Value = reduced_mantissa * 2^effective_exponent (large number)
        // numerator = mantissa << effective_exponent, denominator = 1
        const shifted = try numerator.shl(@intCast(effective_exponent), allocator);
        numerator.deinit();
        numerator = shifted;
        denominator = try BigInt.fromInt(allocator, 1);
    } else {
        // Value = reduced_mantissa / 2^(-effective_exponent)
        // numerator stays as is, denominator = 2^(-effective_exponent)
        const shift_amount: usize = @intCast(-effective_exponent);
        var one = try BigInt.fromInt(allocator, 1);
        errdefer one.deinit();
        denominator = try one.shl(shift_amount, allocator);
        one.deinit();
    }
    errdefer denominator.deinit();

    // The fraction is already in lowest terms since we removed all common powers of 2
    // (trailing zeros from mantissa match the reduction in denominator power)

    return IntegerRatioResult{ .numerator = numerator, .denominator = denominator };
}

/// float.as_integer_ratio() - Legacy i64 version for small values
/// Python: (0.5).as_integer_ratio() -> (1, 2)
/// Returns a tuple of two integers whose ratio equals the float
/// Raises ValueError for NaN, OverflowError for Inf
/// NOTE: Use floatAsIntegerRatioBigInt for proper handling of extreme exponents
pub fn floatAsIntegerRatio(value: anytype) PythonError!struct { i64, i64 } {
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

    // Handle special cases - Python raises for these
    if (std.math.isNan(f)) {
        return PythonError.ValueError;
    }
    if (std.math.isInf(f)) {
        return PythonError.OverflowError;
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
    // Float value = mantissa * 2^(exponent - 52) for normalized numbers
    // So: value = mantissa / 2^(52 - exponent)
    var numerator: i64 = sign * @as(i64, @intCast(mantissa));
    var denominator: i64 = undefined;

    // The effective power of 2 in the denominator is (52 - exponent)
    const power = 52 - exponent;
    if (power >= 0) {
        // Value = mantissa / 2^power
        // We need to reduce the fraction before setting denominator to avoid overflow
        // First, find how many trailing zeros are in mantissa (can divide both by 2^k)
        var trailing_zeros: i64 = 0;
        var temp_mantissa = mantissa;
        while (temp_mantissa != 0 and (temp_mantissa & 1) == 0 and trailing_zeros < power) {
            temp_mantissa >>= 1;
            trailing_zeros += 1;
        }
        // Reduce: numerator = mantissa >> trailing_zeros, denominator = 2^(power - trailing_zeros)
        const reduced_power = power - trailing_zeros;
        if (reduced_power <= 62) {
            numerator = sign * @as(i64, @intCast(temp_mantissa));
            const shift: u6 = @intCast(reduced_power);
            denominator = @as(i64, 1) << shift;
        } else {
            // Still overflows - return approximate result
            numerator = sign * @as(i64, @intCast(temp_mantissa));
            denominator = @as(i64, 1) << 62;
        }
    } else {
        // Exponent >= 52: large float, denominator = 1
        // Value = mantissa * 2^(-power)
        const shift: u6 = @intCast(@min(-power, 52));
        numerator = numerator << shift;
        denominator = 1;
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

/// float.__floor__() - Returns largest integer <= value
/// Python: (1.7).__floor__() -> 1, (1e200).__floor__() -> BigInt
/// Returns i64 for small values, raises error for NaN/Inf
pub fn floatFloor(_: std.mem.Allocator, value: f64) PythonError!i64 {
    // Python raises ValueError for NaN, OverflowError for Inf
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;
    // Apply floor then convert to i64
    const floored = @floor(value);
    // Check if it fits in i64
    if (floored >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
        floored <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
    {
        return @intFromFloat(floored);
    }
    // Too large for i64 - for now return error (BigInt support can be added later)
    return PythonError.OverflowError;
}

/// float.__ceil__() - Returns smallest integer >= value
/// Python: (1.3).__ceil__() -> 2
/// Returns i64 for small values, raises error for NaN/Inf
pub fn floatCeil(_: std.mem.Allocator, value: f64) PythonError!i64 {
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;
    const ceiled = @ceil(value);
    if (ceiled >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
        ceiled <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
    {
        return @intFromFloat(ceiled);
    }
    return PythonError.OverflowError;
}

/// float.__trunc__() - Truncate towards zero
/// Python: (-1.7).__trunc__() -> -1
/// Returns i64 for small values, raises error for NaN/Inf
pub fn floatTrunc(_: std.mem.Allocator, value: f64) PythonError!i64 {
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;
    const truncated = @trunc(value);
    if (truncated >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
        truncated <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
    {
        return @intFromFloat(truncated);
    }
    return PythonError.OverflowError;
}

/// float.__round__() - Round to nearest using Python's banker's rounding
/// Python: (0.5).__round__() -> 0, (1.5).__round__() -> 2 (round half to even)
/// Returns i64 for small values, raises error for NaN/Inf
pub fn floatRound(_: std.mem.Allocator, value: f64) PythonError!i64 {
    if (std.math.isNan(value)) return PythonError.ValueError;
    if (std.math.isInf(value)) return PythonError.OverflowError;

    // Python uses banker's rounding: round half to even
    // This is different from Zig's @round which rounds away from zero
    const floored = @floor(value);
    const frac = value - floored;

    var rounded: f64 = undefined;
    if (frac < 0.5) {
        rounded = floored;
    } else if (frac > 0.5) {
        rounded = floored + 1.0;
    } else {
        // Exactly 0.5 - round to even
        const floored_int: i64 = @intFromFloat(floored);
        if (@mod(floored_int, 2) == 0) {
            rounded = floored; // floored is even, stay there
        } else {
            rounded = floored + 1.0; // floored is odd, go to even
        }
    }

    if (rounded >= @as(f64, @floatFromInt(std.math.minInt(i64))) and
        rounded <= @as(f64, @floatFromInt(std.math.maxInt(i64))))
    {
        return @intFromFloat(rounded);
    }
    return PythonError.OverflowError;
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
        // Check if pointer points to a struct
        const child_type = first_info.pointer.child;
        const child_info = @typeInfo(child_type);
        if (child_info == .@"struct") {
            // IMPORTANT: Check __float__ FIRST - Python MRO prioritizes explicit overrides
            // over inherited __base_value__. This is critical for subclasses like:
            //   class Foo(float):
            //       def __float__(self): return 42.0  # Must be called!
            if (@hasDecl(child_type, "__float__")) {
                const result = first.__float__();
                const ResultType = @TypeOf(result);
                const result_info = @typeInfo(ResultType);
                if (result_info == .error_union) {
                    return result catch return PythonError.ValueError;
                }
                if (result_info == .float or result_info == .comptime_float) {
                    return result;
                }
                return @as(f64, @floatFromInt(result));
            }
            // Fall back to __base_value__ for float subclasses without __float__ override
            if (@hasField(child_type, "__base_value__")) {
                const base_value = first.__base_value__;
                const BaseType = @TypeOf(base_value);
                const base_info = @typeInfo(BaseType);
                if (base_info == .float or base_info == .comptime_float) {
                    return @as(f64, base_value);
                }
                if (base_info == .int or base_info == .comptime_int) {
                    return @as(f64, @floatFromInt(base_value));
                }
                if (base_info == .pointer or base_info == .array) {
                    return parseFloatWithUnicode(base_value) catch return PythonError.ValueError;
                }
            }
            // Check for __index__ method on pointed-to struct (returns int, convert to float)
            if (@hasDecl(child_type, "__index__")) {
                const result = first.__index__();
                const ResultType = @TypeOf(result);
                const result_info = @typeInfo(ResultType);
                if (result_info == .error_union) {
                    const unwrapped = result catch return PythonError.ValueError;
                    return @as(f64, @floatFromInt(unwrapped));
                }
                if (result_info == .int or result_info == .comptime_int) {
                    return @as(f64, @floatFromInt(result));
                }
            }
        }
        // Otherwise treat as string
        return parseFloatWithUnicode(first) catch return PythonError.ValueError;
    }
    // Handle custom classes - check dunder methods FIRST, then fall back to base value
    // In Python, __float__() takes precedence over inherited float value
    if (first_info == .@"struct") {
        // Check for PyBytes (has .data field with []const u8) - parse as float
        if (@hasField(FirstType, "data") and @TypeOf(@field(first, "data")) == []const u8) {
            return parseFloatWithUnicode(first.data) catch return PythonError.ValueError;
        }
        // Check for BigInt's toFloat() method (returns f64 directly)
        // BigInt.toFloat takes *const Self, so we need to take address
        if (@hasDecl(FirstType, "toFloat") and @hasField(FirstType, "managed")) {
            // BigInt has toFloat() that returns f64
            return (&first).toFloat();
        }
        // Check for __float__ method FIRST (takes precedence)
        if (@hasDecl(FirstType, "__float__")) {
            const result = first.__float__();
            // __float__ might return error union or plain value
            const ResultType = @TypeOf(result);
            const result_info = @typeInfo(ResultType);
            if (result_info == .error_union) {
                return result catch return PythonError.ValueError;
            }
            // __float__ should return f64, but handle legacy code that returns int
            if (result_info == .float or result_info == .comptime_float) {
                return result;
            }
            return @as(f64, @floatFromInt(result));
        }
        // Check for __index__ method (returns int, convert to float)
        if (@hasDecl(FirstType, "__index__")) {
            const result = first.__index__();
            const ResultType = @TypeOf(result);
            const result_info = @typeInfo(ResultType);
            if (result_info == .error_union) {
                const unwrapped = result catch return PythonError.ValueError;
                return @as(f64, @floatFromInt(unwrapped));
            }
            if (result_info == .int or result_info == .comptime_int) {
                return @as(f64, @floatFromInt(result));
            }
        }
        // Fall back to __base_value__ for classes that inherit from float/str/int
        if (@hasField(FirstType, "__base_value__")) {
            const base_value = first.__base_value__;
            const BaseType = @TypeOf(base_value);
            const base_info = @typeInfo(BaseType);
            // If base_value is already a float, return it directly
            if (base_info == .float or base_info == .comptime_float) {
                return @as(f64, base_value);
            }
            // If base_value is an int, convert to float
            if (base_info == .int or base_info == .comptime_int) {
                return @as(f64, @floatFromInt(base_value));
            }
            // If base_value is a string/slice, parse it
            if (base_info == .pointer or base_info == .array) {
                return parseFloatWithUnicode(base_value) catch return PythonError.ValueError;
            }
        }
    }
    // Handle tagged unions (like PyValue)
    if (first_info == .@"union" and first_info.@"union".tag_type != null) {
        // Check for toFloat method (PyValue has this)
        if (@hasDecl(FirstType, "toFloat")) {
            if (first.toFloat()) |val| {
                return val;
            }
        }
        // Check for toInt method and convert to float
        if (@hasDecl(FirstType, "toInt")) {
            if (first.toInt()) |val| {
                return @as(f64, @floatFromInt(val));
            }
        }
    }

    return PythonError.TypeError;
}

/// bool() builtin call wrapper for assertRaises testing
/// Handles bool(x) with proper error checking - bool() takes exactly 0 or 1 argument
pub fn boolBuiltinCall(first: anytype, rest: anytype) PythonError!bool {
    const FirstType = @TypeOf(first);
    const first_info = @typeInfo(FirstType);
    const RestType = @TypeOf(rest);
    const rest_info = @typeInfo(RestType);

    // bool() takes at most one argument
    const has_extra_args = rest_info == .@"struct" and rest_info.@"struct".fields.len > 0;
    if (has_extra_args) {
        return PythonError.TypeError;
    }

    // Handle void/empty first arg (bool() with no args returns False)
    if (FirstType == void or first_info == .@"struct" and first_info.@"struct".fields.len == 0) {
        return false;
    }

    // Convert to bool using Python truthiness rules
    if (first_info == .bool) {
        return first;
    }
    if (first_info == .int or first_info == .comptime_int) {
        return first != 0;
    }
    if (first_info == .float or first_info == .comptime_float) {
        return first != 0.0;
    }
    if (first_info == .pointer and first_info.pointer.size == .slice) {
        return first.len > 0;
    }
    // Handle pointers to arrays (string literals like "" are *const [N:0]u8)
    if (first_info == .pointer and first_info.pointer.size == .one) {
        const child_info = @typeInfo(first_info.pointer.child);
        if (child_info == .array) {
            // Array length determines truthiness - empty array is falsy
            return child_info.array.len > 0;
        }
    }
    // Handle pointers to structs (dereference and check struct)
    if (first_info == .pointer and first_info.pointer.size == .one) {
        const ChildType = first_info.pointer.child;
        const child_info = @typeInfo(ChildType);
        if (child_info == .@"struct") {
            // Check for __bool__ method FIRST - takes precedence over __base_value__
            // Python: if a class defines __bool__, it's called even if it inherits from int/bool
            if (@hasDecl(ChildType, "__bool__")) {
                // Check if __bool__ takes mutable pointer - if so, cast away const
                const bool_fn = @typeInfo(@TypeOf(ChildType.__bool__));
                const first_param = bool_fn.@"fn".params[0].type.?;
                const result = if (@typeInfo(first_param) == .pointer and !@typeInfo(first_param).pointer.is_const)
                    try @constCast(first).__bool__() // Cast away const for mutable __bool__
                else
                    try first.__bool__();
                // Python: __bool__ must return bool, not int or any other type
                // TypeError: __bool__ should return bool, returned <type>
                if (@TypeOf(result) != bool) {
                    return PythonError.TypeError;
                }
                return result;
            }
            // Check for __len__ method (containers are truthy if len > 0)
            // Python raises ValueError if __len__ returns negative
            if (@hasDecl(ChildType, "__len__")) {
                const len = try first.__len__();
                if (len < 0) return PythonError.ValueError;
                return len > 0;
            }
            // Fall back to __base_value__ for subclasses of builtin types
            if (@hasField(ChildType, "__base_value__")) {
                const base_value = first.__base_value__;
                const BaseType = @TypeOf(base_value);
                const base_info = @typeInfo(BaseType);
                if (base_info == .bool) return base_value;
                if (base_info == .int or base_info == .comptime_int) return base_value != 0;
                if (base_info == .float or base_info == .comptime_float) return base_value != 0.0;
                if (base_info == .pointer and base_info.pointer.size == .slice) return base_value.len > 0;
            }
        }
    }
    // Handle structs (user-defined classes)
    if (first_info == .@"struct") {
        // Check for __bool__ method FIRST - takes precedence over __base_value__
        // Python: if a class defines __bool__, it's called even if it inherits from int/bool
        if (@hasDecl(FirstType, "__bool__")) {
            // Check if __bool__ takes mutable pointer - if so, cast away const
            const bool_fn = @typeInfo(@TypeOf(FirstType.__bool__));
            const first_param = bool_fn.@"fn".params[0].type.?;
            const result = if (@typeInfo(first_param) == .pointer and !@typeInfo(first_param).pointer.is_const)
                try @constCast(&first).__bool__() // Need to take address and cast
            else
                try first.__bool__();
            // Python: __bool__ must return bool, not int or any other type
            // TypeError: __bool__ should return bool, returned <type>
            if (@TypeOf(result) != bool) {
                return PythonError.TypeError;
            }
            return result;
        }
        // Check for __len__ method (containers are truthy if len > 0)
        // Python raises ValueError if __len__ returns negative
        if (@hasDecl(FirstType, "__len__")) {
            const len = try first.__len__();
            if (len < 0) return PythonError.ValueError;
            return len > 0;
        }
        // Fall back to __base_value__ for subclasses of builtin types (int, str, etc.)
        if (@hasField(FirstType, "__base_value__")) {
            const base_value = first.__base_value__;
            const BaseType = @TypeOf(base_value);
            const base_info = @typeInfo(BaseType);
            if (base_info == .bool) return base_value;
            if (base_info == .int or base_info == .comptime_int) return base_value != 0;
            if (base_info == .float or base_info == .comptime_float) return base_value != 0.0;
            if (base_info == .pointer and base_info.pointer.size == .slice) return base_value.len > 0;
        }
    }

    // Default: objects are truthy
    return true;
}

/// Parse float string with Unicode digit support (Python-compatible)
/// Handles Arabic-Indic digits (\u0660-\u0669), Extended Arabic-Indic (\u06F0-\u06F9),
/// Devanagari (\u0966-\u096F), and other Unicode digit ranges
pub fn parseFloatWithUnicode(str: []const u8) !f64 {
    // Trim whitespace first (including Unicode whitespace)
    var trimmed = trimUnicodeWhitespace(str);
    if (trimmed.len == 0) return error.InvalidFloat;

    // Python's float() rejects hex literals - use float.fromhex() for that
    // Reject strings starting with 0x, 0X, -0x, -0X, +0x, +0X
    if (trimmed.len >= 2) {
        const start = if (trimmed[0] == '-' or trimmed[0] == '+') trimmed[1..] else trimmed;
        if (start.len >= 2 and start[0] == '0' and (start[1] == 'x' or start[1] == 'X')) {
            return error.InvalidFloat;
        }
        // Reject multiple signs: ++, +-, -+, --
        if ((trimmed[0] == '+' or trimmed[0] == '-') and (trimmed[1] == '+' or trimmed[1] == '-')) {
            return error.InvalidFloat;
        }
        // Reject malformed: .nan, +.inf, -.inf, +., -., just .
        if (trimmed[0] == '.' and trimmed.len > 1) {
            const next = trimmed[1];
            if (next == 'n' or next == 'N' or next == 'i' or next == 'I') {
                return error.InvalidFloat;
            }
        }
        if ((trimmed[0] == '+' or trimmed[0] == '-') and trimmed.len > 1 and trimmed[1] == '.') {
            if (trimmed.len == 2) return error.InvalidFloat; // just "+." or "-."
            const next = trimmed[2];
            if (next == 'n' or next == 'N' or next == 'i' or next == 'I') {
                return error.InvalidFloat;
            }
        }
    }
    // Just "." is invalid
    if (trimmed.len == 1 and trimmed[0] == '.') {
        return error.InvalidFloat;
    }

    // First try standard parsing (fast path for ASCII)
    if (std.fmt.parseFloat(f64, trimmed)) |val| {
        return val;
    } else |_| {}

    // Try to normalize Unicode digits to ASCII
    var buf: [256]u8 = undefined;
    var buf_len: usize = 0;
    var i: usize = 0;

    while (i < trimmed.len) {
        if (buf_len >= buf.len - 1) return error.InvalidFloat; // Buffer overflow protection

        const byte = trimmed[i];

        // ASCII characters pass through
        if (byte < 0x80) {
            buf[buf_len] = byte;
            buf_len += 1;
            i += 1;
            continue;
        }

        // Try to decode UTF-8 and convert Unicode digits
        const codepoint = decodeUtf8Codepoint(trimmed[i..]) catch {
            i += 1;
            continue;
        };
        const cp_len = utf8CodepointLen(byte);

        // Check if it's a Unicode digit and convert to ASCII
        if (unicodeDigitToAscii(codepoint)) |ascii_digit| {
            buf[buf_len] = ascii_digit;
            buf_len += 1;
        } else if (codepoint == 0x066B or codepoint == 0x066C) {
            // Arabic decimal/thousands separator - use as decimal point
            buf[buf_len] = '.';
            buf_len += 1;
        } else {
            // Skip other Unicode characters (whitespace was already trimmed)
            // This allows things like EM SPACE around the number
        }

        i += cp_len;
    }

    if (buf_len == 0) return error.InvalidFloat;

    return std.fmt.parseFloat(f64, buf[0..buf_len]) catch error.InvalidFloat;
}

/// Decode a UTF-8 codepoint from bytes
fn decodeUtf8Codepoint(bytes: []const u8) !u21 {
    if (bytes.len == 0) return error.InvalidUtf8;

    const first = bytes[0];
    if (first < 0x80) {
        return first;
    } else if (first < 0xC0) {
        return error.InvalidUtf8;
    } else if (first < 0xE0) {
        if (bytes.len < 2) return error.InvalidUtf8;
        return (@as(u21, first & 0x1F) << 6) | (bytes[1] & 0x3F);
    } else if (first < 0xF0) {
        if (bytes.len < 3) return error.InvalidUtf8;
        return (@as(u21, first & 0x0F) << 12) | (@as(u21, bytes[1] & 0x3F) << 6) | (bytes[2] & 0x3F);
    } else {
        if (bytes.len < 4) return error.InvalidUtf8;
        return (@as(u21, first & 0x07) << 18) | (@as(u21, bytes[1] & 0x3F) << 12) | (@as(u21, bytes[2] & 0x3F) << 6) | (bytes[3] & 0x3F);
    }
}

/// Get UTF-8 byte length from first byte
fn utf8CodepointLen(first_byte: u8) usize {
    if (first_byte < 0x80) return 1;
    if (first_byte < 0xE0) return 2;
    if (first_byte < 0xF0) return 3;
    return 4;
}

/// Convert Unicode digit codepoint to ASCII digit character
fn unicodeDigitToAscii(codepoint: u21) ?u8 {
    // Arabic-Indic digits (٠-٩) U+0660-U+0669
    if (codepoint >= 0x0660 and codepoint <= 0x0669) {
        return @intCast('0' + (codepoint - 0x0660));
    }
    // Extended Arabic-Indic digits (۰-۹) U+06F0-U+06F9
    if (codepoint >= 0x06F0 and codepoint <= 0x06F9) {
        return @intCast('0' + (codepoint - 0x06F0));
    }
    // Devanagari digits (०-९) U+0966-U+096F
    if (codepoint >= 0x0966 and codepoint <= 0x096F) {
        return @intCast('0' + (codepoint - 0x0966));
    }
    // Bengali digits (০-৯) U+09E6-U+09EF
    if (codepoint >= 0x09E6 and codepoint <= 0x09EF) {
        return @intCast('0' + (codepoint - 0x09E6));
    }
    // Gurmukhi digits U+0A66-U+0A6F
    if (codepoint >= 0x0A66 and codepoint <= 0x0A6F) {
        return @intCast('0' + (codepoint - 0x0A66));
    }
    // Gujarati digits U+0AE6-U+0AEF
    if (codepoint >= 0x0AE6 and codepoint <= 0x0AEF) {
        return @intCast('0' + (codepoint - 0x0AE6));
    }
    // Tamil digits U+0BE6-U+0BEF
    if (codepoint >= 0x0BE6 and codepoint <= 0x0BEF) {
        return @intCast('0' + (codepoint - 0x0BE6));
    }
    // Thai digits U+0E50-U+0E59
    if (codepoint >= 0x0E50 and codepoint <= 0x0E59) {
        return @intCast('0' + (codepoint - 0x0E50));
    }
    // Fullwidth digits (０-９) U+FF10-U+FF19
    if (codepoint >= 0xFF10 and codepoint <= 0xFF19) {
        return @intCast('0' + (codepoint - 0xFF10));
    }
    return null;
}

/// Trim Unicode whitespace from both ends
fn trimUnicodeWhitespace(str: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = str.len;

    // Trim leading whitespace
    while (start < end) {
        const byte = str[start];
        if (byte < 0x80) {
            // ASCII whitespace
            if (byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r' or byte == 0x0B or byte == 0x0C) {
                start += 1;
                continue;
            }
            break;
        }
        // Check for Unicode whitespace
        const codepoint = decodeUtf8Codepoint(str[start..]) catch break;
        if (isUnicodeWhitespace(codepoint)) {
            start += utf8CodepointLen(byte);
            continue;
        }
        break;
    }

    // Trim trailing whitespace
    while (end > start) {
        // Find start of last character
        var char_start = end - 1;
        while (char_start > start and (str[char_start] & 0xC0) == 0x80) {
            char_start -= 1;
        }

        const byte = str[char_start];
        if (byte < 0x80) {
            if (byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r' or byte == 0x0B or byte == 0x0C) {
                end = char_start;
                continue;
            }
            break;
        }
        const codepoint = decodeUtf8Codepoint(str[char_start..end]) catch break;
        if (isUnicodeWhitespace(codepoint)) {
            end = char_start;
            continue;
        }
        break;
    }

    return str[start..end];
}

/// Check if codepoint is Unicode whitespace
fn isUnicodeWhitespace(codepoint: u21) bool {
    return switch (codepoint) {
        0x0009...0x000D, // Tab, LF, VT, FF, CR
        0x0020, // Space
        0x0085, // Next Line
        0x00A0, // No-Break Space
        0x1680, // Ogham Space Mark
        0x2000...0x200A, // En Quad through Hair Space (includes En Space 0x2002, Em Space 0x2003)
        0x2028, // Line Separator
        0x2029, // Paragraph Separator
        0x202F, // Narrow No-Break Space
        0x205F, // Medium Mathematical Space
        0x3000, // Ideographic Space
        => true,
        else => false,
    };
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

    // Struct - check for toFloat, __float__ method or value field
    if (type_info == .@"struct") {
        // Check for BigInt's toFloat() method (returns f64 directly)
        // BigInt.toFloat takes *const Self, so we need to take address
        if (@hasDecl(T, "toFloat") and @hasField(T, "managed")) {
            // BigInt has toFloat() that returns f64
            return (&value).toFloat();
        }
        // First try __float__ method
        if (@hasDecl(T, "__float__")) {
            // Need to take address since __float__ might take *Self or *const Self
            const float_result = (&value).__float__();
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
        // Check for value field (passthrough pattern)
        if (@hasField(T, "value")) {
            const field_type = @TypeOf(value.value);
            const field_info = @typeInfo(field_type);
            // If value field is a tagged union (like PyValue), extract float from it
            if (field_info == .@"union") {
                if (@hasDecl(field_type, "toFloat")) {
                    // PyValue has toFloat() method
                    if (value.value.toFloat()) |f| return f;
                }
            } else {
                // Native type - recurse
                return toFloat(value.value);
            }
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

    // Tagged union (like PyValue)
    if (type_info == .@"union") {
        // Check for toFloat method (PyValue has this)
        if (@hasDecl(T, "toFloat")) {
            if (value.toFloat()) |f| return f;
        }
    }

    // Fallback
    return 0.0;
}
