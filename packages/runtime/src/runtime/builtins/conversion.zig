/// Conversion builtins (hex, oct, bin, intWithBase, round)
const std = @import("std");
const runtime = @import("../../runtime.zig");
const PythonError = runtime.PythonError;
const PyValue = runtime.PyValue;

// ============================================================================
// Centralized Integer Extraction Helpers
// ============================================================================
// These helpers extract integer values from various types (i64, UnifiedInt,
// BigInt, PyValue) in a consistent way. Use these instead of scattered
// type-specific checks to avoid maintenance burden.

/// Extract an i32 from any integer-like type, clamping to min/max if out of range.
/// Returns null if the type is not integer-like (e.g., float, string).
///
/// Supported types:
/// - Native integers (i32, i64, comptime_int, etc.)
/// - BigInt (struct with toInt method)
/// - UnifiedInt (union with .small/.big fields)
/// - PyValue (union with .int/.bigint fields)
///
/// Usage: extractI32Clamped(value, -1000, 1000) orelse return error.TypeError
pub fn extractI32Clamped(value: anytype, clamp_min: i32, clamp_max: i32) ?i32 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Case 1: Native integer types
    if (info == .int or info == .comptime_int) {
        const v: i64 = @intCast(value);
        if (v < std.math.minInt(i32)) return clamp_min;
        if (v > std.math.maxInt(i32)) return clamp_max;
        return @intCast(v);
    }

    // Case 2: Struct with toI32Clamped method (UnifiedInt)
    if (info == .@"struct" and @hasDecl(T, "toI32Clamped")) {
        return value.toI32Clamped(clamp_min, clamp_max);
    }

    // Case 3: Struct with toInt method (BigInt)
    if (info == .@"struct" and @hasDecl(T, "toInt")) {
        if (value.toInt(i32)) |val| return val else |_| {
            return if (value.isNegative()) clamp_min else clamp_max;
        }
    }

    // Case 4: Tagged union (UnifiedInt, PyValue, etc.)
    if (info == .@"union" and info.@"union".tag_type != null) {
        const active_tag = @intFromEnum(value);

        // UnifiedInt: .small (i64)
        if (@hasField(T, "small")) {
            const small_idx = @intFromEnum(@field(std.meta.FieldEnum(T), "small"));
            if (active_tag == small_idx) {
                const v = value.small;
                if (v < std.math.minInt(i32)) return clamp_min;
                if (v > std.math.maxInt(i32)) return clamp_max;
                return @intCast(v);
            }
        }

        // UnifiedInt: .big (*BigInt)
        if (@hasField(T, "big")) {
            const big_idx = @intFromEnum(@field(std.meta.FieldEnum(T), "big"));
            if (active_tag == big_idx) {
                const bi_ptr = value.big;
                if (bi_ptr.toInt(i32)) |val| return val else |_| {
                    return if (bi_ptr.isNegative()) clamp_min else clamp_max;
                }
            }
        }

        // PyValue: .int (i64)
        if (@hasField(T, "int")) {
            const int_idx = @intFromEnum(@field(std.meta.FieldEnum(T), "int"));
            if (active_tag == int_idx) {
                const v = value.int;
                if (v < std.math.minInt(i32)) return clamp_min;
                if (v > std.math.maxInt(i32)) return clamp_max;
                return @intCast(v);
            }
        }

        // PyValue: .bigint (BigInt value, not pointer)
        if (@hasField(T, "bigint")) {
            const bigint_idx = @intFromEnum(@field(std.meta.FieldEnum(T), "bigint"));
            if (active_tag == bigint_idx) {
                const bi_ptr = &value.bigint;
                if (bi_ptr.toInt(i32)) |val| return val else |_| {
                    return if (bi_ptr.isNegative()) clamp_min else clamp_max;
                }
            }
        }
    }

    // Not an integer-like type
    return null;
}

/// Extract an i64 from any integer-like type.
/// Returns null if the type is not integer-like or value doesn't fit in i64.
pub fn extractI64(value: anytype) ?i64 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Case 1: Native integer types
    if (info == .int or info == .comptime_int) {
        return @intCast(value);
    }

    // Case 2: Struct with toI64 method (UnifiedInt)
    if (info == .@"struct" and @hasDecl(T, "toI64")) {
        return value.toI64();
    }

    // Case 3: Struct with toInt64 method (BigInt)
    if (info == .@"struct" and @hasDecl(T, "toInt64")) {
        return value.toInt64();
    }

    // Case 4: Tagged union (UnifiedInt, PyValue, etc.)
    if (info == .@"union" and info.@"union".tag_type != null) {
        const active_tag = @intFromEnum(value);

        // UnifiedInt: .small (i64)
        if (@hasField(T, "small")) {
            const small_idx = @intFromEnum(@field(std.meta.FieldEnum(T), "small"));
            if (active_tag == small_idx) return value.small;
        }

        // UnifiedInt: .big (*BigInt)
        if (@hasField(T, "big")) {
            const big_idx = @intFromEnum(@field(std.meta.FieldEnum(T), "big"));
            if (active_tag == big_idx) return value.big.toInt64();
        }

        // PyValue: .int (i64)
        if (@hasField(T, "int")) {
            const int_idx = @intFromEnum(@field(std.meta.FieldEnum(T), "int"));
            if (active_tag == int_idx) return value.int;
        }

        // PyValue: .bigint (BigInt value)
        if (@hasField(T, "bigint")) {
            const bigint_idx = @intFromEnum(@field(std.meta.FieldEnum(T), "bigint"));
            if (active_tag == bigint_idx) return value.bigint.toInt64();
        }
    }

    return null;
}

/// hex(x) - convert integer to hexadecimal string with "0x" prefix
pub fn hex(allocator: std.mem.Allocator, value: anytype) []const u8 {
    const T = @TypeOf(value);
    const int_val: i64 = blk: {
        if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
            break :blk @as(i64, @intCast(value));
        } else if (@typeInfo(T) == .@"struct" and @hasDecl(T, "toInt64")) {
            break :blk value.toInt64() orelse 0;
        }
        break :blk 0;
    };

    if (int_val >= 0) {
        return std.fmt.allocPrint(allocator, "0x{x}", .{@as(u64, @intCast(int_val))}) catch "0x0";
    } else {
        return std.fmt.allocPrint(allocator, "-0x{x}", .{@as(u64, @intCast(-int_val))}) catch "-0x0";
    }
}

/// oct(x) - convert integer to octal string with "0o" prefix
pub fn oct(allocator: std.mem.Allocator, value: anytype) []const u8 {
    const T = @TypeOf(value);
    const int_val: i64 = blk: {
        if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
            break :blk @as(i64, @intCast(value));
        } else if (@typeInfo(T) == .@"struct" and @hasDecl(T, "toInt64")) {
            break :blk value.toInt64() orelse 0;
        }
        break :blk 0;
    };

    if (int_val >= 0) {
        return std.fmt.allocPrint(allocator, "0o{o}", .{@as(u64, @intCast(int_val))}) catch "0o0";
    } else {
        return std.fmt.allocPrint(allocator, "-0o{o}", .{@as(u64, @intCast(-int_val))}) catch "-0o0";
    }
}

/// bin(x) - convert integer to binary string with "0b" prefix
pub fn bin(allocator: std.mem.Allocator, value: anytype) []const u8 {
    const T = @TypeOf(value);
    const int_val: i64 = blk: {
        if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
            break :blk @as(i64, @intCast(value));
        } else if (@typeInfo(T) == .@"struct" and @hasDecl(T, "toInt64")) {
            break :blk value.toInt64() orelse 0;
        }
        break :blk 0;
    };

    if (int_val >= 0) {
        return std.fmt.allocPrint(allocator, "0b{b}", .{@as(u64, @intCast(int_val))}) catch "0b0";
    } else {
        return std.fmt.allocPrint(allocator, "-0b{b}", .{@as(u64, @intCast(-int_val))}) catch "-0b0";
    }
}

/// int() with base argument - stub that raises error
pub fn intWithBaseOnly() PythonError!i128 {
    return PythonError.TypeError;
}

/// int(string, base) - parse string with given base
pub fn intWithBase(allocator: std.mem.Allocator, string: anytype, base: anytype) PythonError!i128 {
    _ = allocator;
    const T = @TypeOf(string);
    const str_slice: []const u8 = if (T == []const u8 or T == []u8)
        string
    else if (@typeInfo(T) == .pointer)
        string[0..]
    else
        return PythonError.TypeError;

    const base_val: u8 = blk: {
        const BaseT = @TypeOf(base);
        if (@typeInfo(BaseT) == .int or @typeInfo(BaseT) == .comptime_int) {
            // Cast to i64 first to safely compare (handles comptime_int with large/negative values)
            const base_i64: i64 = @intCast(base);
            // Validate base is in valid range before casting to u8
            // Python allows base 0 (auto-detect), 2-36
            if (base_i64 < 0 or (base_i64 != 0 and (base_i64 < 2 or base_i64 > 36))) {
                return PythonError.ValueError;
            }
            break :blk @intCast(base_i64);
        }
        break :blk 10;
    };

    // Additional validation for the parsed base value
    if (base_val != 0 and (base_val < 2 or base_val > 36)) {
        return PythonError.ValueError;
    }

    // Skip whitespace and handle sign
    var i: usize = 0;
    while (i < str_slice.len and (str_slice[i] == ' ' or str_slice[i] == '\t')) : (i += 1) {}

    var negative = false;
    if (i < str_slice.len and str_slice[i] == '-') {
        negative = true;
        i += 1;
    } else if (i < str_slice.len and str_slice[i] == '+') {
        i += 1;
    }

    // Skip base prefix if present
    if (i + 1 < str_slice.len and str_slice[i] == '0') {
        const prefix_char = std.ascii.toLower(str_slice[i + 1]);
        if ((base_val == 16 and prefix_char == 'x') or
            (base_val == 8 and prefix_char == 'o') or
            (base_val == 2 and prefix_char == 'b'))
        {
            i += 2;
        }
    }

    // Parse digits
    var result: i128 = 0;
    var has_digits = false;
    while (i < str_slice.len) : (i += 1) {
        const c = str_slice[i];
        if (c == '_') continue; // Python 3.6+ allows underscores

        const digit: u8 = if (c >= '0' and c <= '9')
            c - '0'
        else if (c >= 'a' and c <= 'z')
            c - 'a' + 10
        else if (c >= 'A' and c <= 'Z')
            c - 'A' + 10
        else
            break;

        if (digit >= base_val) break;

        result = result * base_val + digit;
        has_digits = true;
    }

    if (!has_digits) {
        return PythonError.ValueError;
    }

    return if (negative) -result else result;
}

/// Python round() with banker's rounding
pub fn round(value: anytype, args: anytype) PythonError!f64 {
    const T = @TypeOf(value);
    const ArgsType = @TypeOf(args);

    const float_val: f64 = if (@typeInfo(T) == .float or @typeInfo(T) == .comptime_float)
        value
    else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int)
        @floatFromInt(value)
    else
        return PythonError.TypeError;

    // Check if ndigits was provided (args has fields) vs round(x) with no ndigits
    const has_ndigits = @typeInfo(ArgsType) == .@"struct" and @typeInfo(ArgsType).@"struct".fields.len > 0;

    // For round(x) without ndigits, Python returns int and raises for inf/nan
    // For round(x, ndigits), Python returns float and inf/nan pass through
    if (!has_ndigits) {
        if (std.math.isNan(float_val)) {
            return PythonError.ValueError;
        }
        if (std.math.isInf(float_val)) {
            return PythonError.OverflowError;
        }
        return bankersRound(float_val);
    }

    // Get ndigits from args tuple using centralized extraction
    const ndigits: i32 = blk: {
        const first = @field(args, @typeInfo(ArgsType).@"struct".fields[0].name);
        break :blk extractI32Clamped(first, -1000, 1000) orelse return PythonError.TypeError;
    };

    if (ndigits == 0) {
        return bankersRound(float_val);
    }

    // Handle extreme ndigits that would cause underflow/overflow
    // For very negative ndigits, the result is 0.0 (or -0.0 for negative input)
    if (ndigits < -308) {
        return if (float_val < 0) -0.0 else 0.0;
    }

    // For very large positive ndigits, the multiplier overflows to inf
    // For subnormal floats, we need two-step scaling to avoid overflow
    const multiplier = std.math.pow(f64, 10.0, @floatFromInt(ndigits));

    // Guard against multiplier underflow to 0
    if (multiplier == 0.0) {
        return if (float_val < 0) -0.0 else 0.0;
    }

    // If multiplier is inf, use two-step scaling for subnormal floats
    // e.g., round(1.4e-315, 315) needs special handling
    if (std.math.isInf(multiplier)) {
        // Check if value is subnormal or very small (abs < 1e-300)
        const abs_val = @abs(float_val);
        if (abs_val > 0 and abs_val < 1e-300) {
            // Two-step scaling: first bring to normal range, then apply remaining
            const partial_scale: i32 = 307; // Safe scale that won't overflow
            const partial_mult = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(partial_scale)));
            const intermediate = float_val * partial_mult;

            const remaining_ndigits = ndigits - partial_scale;
            // Only proceed if remaining_ndigits is within safe bounds (0-308)
            // If remaining_ndigits > 308, final_mult would overflow to inf
            // and we'd get nan from inf/inf - just return original value
            if (remaining_ndigits >= 0 and remaining_ndigits <= 308) {
                const final_mult = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(remaining_ndigits)));
                const scaled_two_step = intermediate * final_mult;
                const rounded_two_step = bankersRound(scaled_two_step);
                const result_two_step = rounded_two_step / final_mult / partial_mult;

                // Preserve sign of input when result is zero
                if (result_two_step == 0.0 and std.math.signbit(float_val)) {
                    return -0.0;
                }
                return result_two_step;
            }
            // remaining_ndigits out of bounds - rounding has no effect
            return float_val;
        }
        // For normal values with very large ndigits, rounding has no effect
        return float_val;
    }

    const scaled = float_val * multiplier;

    // If scaled overflows to infinity, the original value has more precision
    // than the requested ndigits, so rounding has no effect - return original
    // e.g., round(1e150, 300) - scaling by 10^300 overflows, but 1e150 is already
    // precise at 300 decimal places (it's actually precise at all decimal places)
    if (std.math.isInf(scaled) and !std.math.isInf(float_val)) {
        return float_val;
    }

    const rounded = bankersRound(scaled);
    const result = rounded / multiplier;

    // Note: For very large numbers, floating point division may introduce small errors
    // Python uses decimal arithmetic internally for these edge cases
    // e.g., round(56294995342131.5, 3) may return 56294995342131.51 instead of .5

    // Check for overflow - Python raises OverflowError only when input was finite
    // but result is infinite (actual overflow, not just scaling overflow)
    if (std.math.isInf(result) and !std.math.isInf(float_val)) {
        return PythonError.OverflowError;
    }
    // Preserve sign of input when result is zero (Python semantics)
    if (result == 0.0 and std.math.signbit(float_val)) {
        return -0.0;
    }
    return result;
}

/// Banker's rounding (round half to even)
/// Handles floating point imprecision near 0.5
pub fn bankersRound(value: f64) f64 {
    if (std.math.isNan(value) or std.math.isInf(value)) {
        return value;
    }

    // Use @round for the basic rounding, then check for half cases
    const rounded = @round(value);
    const diff = value - rounded;

    // If we're very close to the rounded value, just use it
    // This handles cases like 2.5000000000001 which should round to 2 (even)
    const epsilon = 1e-9;

    // Check if value is close to X.5 (halfway between integers)
    const floor_val = @floor(value);
    const frac = value - floor_val;

    // Is this a "half" case? (frac is very close to 0.5)
    if (@abs(frac - 0.5) < epsilon) {
        // Apply banker's rounding - round to even
        const floor_int: i64 = @intFromFloat(floor_val);
        if (@mod(floor_int, 2) == 0) {
            return floor_val;
        } else {
            return floor_val + 1.0;
        }
    }

    // For non-half cases, just use standard rounding
    _ = diff; // unused
    if (frac < 0.5) {
        return floor_val;
    } else {
        return floor_val + 1.0;
    }
}

/// Python round() - simple version for integers
pub fn pyRound(value: anytype) i64 {
    const T = @TypeOf(value);
    if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
        return @intCast(value);
    }
    if (@typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {
        return @intFromFloat(bankersRound(value));
    }
    return 0;
}

/// Python ord(c) - returns the Unicode code point of a single character
/// Works with single-character strings or individual bytes
pub fn ord(value: anytype) PythonError!i64 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Handle single integer (already a code point or byte)
    if (info == .int or info == .comptime_int) {
        return @intCast(value);
    }

    // Handle u8 (single byte)
    if (T == u8) {
        return @intCast(value);
    }

    // Handle strings (slices or pointers)
    if ((T == []const u8 or T == []u8) or
        (info == .pointer and (@typeInfo(info.pointer.child) == .array or info.pointer.child == u8)))
    {
        const str: []const u8 = if (T == []const u8 or T == []u8)
            value
        else if (info == .pointer and @typeInfo(info.pointer.child) == .array)
            value[0..]
        else
            @as([*]const u8, @ptrCast(value))[0..1];

        if (str.len == 0) {
            return PythonError.TypeError; // Empty string
        }

        // Handle single ASCII byte
        if (str.len == 1) {
            return @intCast(str[0]);
        }

        // Handle UTF-8 encoded characters
        const cp = std.unicode.utf8Decode(str) catch |err| {
            // Try handling it as single byte if decode fails
            switch (err) {
                error.Truncated, error.InvalidStartByte, error.UnexpectedSecondByte => return PythonError.TypeError,
            }
        };
        return @intCast(cp);
    }

    return PythonError.TypeError;
}

/// Python chr(i) - returns the character for a Unicode code point
/// Returns a single-character string
pub fn chr(allocator: std.mem.Allocator, value: anytype) PythonError![]const u8 {
    const T = @TypeOf(value);
    const int_val: u21 = blk: {
        if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
            if (value < 0 or value > 0x10FFFF) {
                return PythonError.ValueError;
            }
            break :blk @intCast(value);
        }
        return PythonError.TypeError;
    };

    // Encode the code point as UTF-8
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(int_val, &buf) catch {
        return PythonError.ValueError;
    };

    const result = allocator.alloc(u8, len) catch {
        return PythonError.MemoryError;
    };
    @memcpy(result, buf[0..len]);
    return result;
}
