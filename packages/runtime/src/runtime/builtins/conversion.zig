/// Conversion builtins (hex, oct, bin, intWithBase, round)
const std = @import("std");
const runtime = @import("../../runtime.zig");
const PythonError = runtime.PythonError;
const PyValue = runtime.PyValue;

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
            break :blk @intCast(base);
        }
        break :blk 10;
    };

    if (base_val < 2 or base_val > 36) {
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

    // Get ndigits from args tuple
    const ndigits: i32 = blk: {
        const first = @field(args, @typeInfo(ArgsType).@"struct".fields[0].name);
        const FirstT = @TypeOf(first);
        if (@typeInfo(FirstT) == .int or @typeInfo(FirstT) == .comptime_int) {
            break :blk @intCast(first);
        }
        // Handle direct BigInt struct type
        // Check for struct with toInt method (BigInt signature)
        if (@typeInfo(FirstT) == .@"struct" and @hasDecl(FirstT, "toInt")) {
            // This is a BigInt - try to convert to i32 if it fits
            if (first.toInt(i32)) |val| {
                break :blk val;
            } else |_| {
                // BigInt is too large for ndigits, use extreme value
                // Check if negative (very small n) or positive (very large n)
                if (first.isNegative()) {
                    break :blk -1000; // Will trigger early return for 0.0
                } else {
                    break :blk 1000; // Will trigger early return for original value
                }
            }
        }
        // Handle PyValue or similar tagged union containing int or bigint
        // Use duck-typing: check if it's a tagged union with int/bigint fields
        const first_info = @typeInfo(FirstT);
        if (first_info == .@"union" and first_info.@"union".tag_type != null) {
            // Get the active tag at runtime
            const active_tag = @intFromEnum(first);

            // Find the int field index and check if active
            if (@hasField(FirstT, "int")) {
                const int_idx = @intFromEnum(@field(std.meta.FieldEnum(FirstT), "int"));
                if (active_tag == int_idx) {
                    break :blk @intCast(first.int);
                }
            }

            // Find the bigint field index and check if active
            if (@hasField(FirstT, "bigint")) {
                const bigint_idx = @intFromEnum(@field(std.meta.FieldEnum(FirstT), "bigint"));
                if (active_tag == bigint_idx) {
                    // Use pointer to avoid copying BigInt (contains allocator ref)
                    const bi_ptr = &first.bigint;
                    // For BigInt, try to convert to i32 if it fits
                    if (bi_ptr.toInt(i32)) |val| {
                        break :blk val;
                    } else |_| {
                        // BigInt is too large for ndigits, use extreme value
                        // Check if negative (very small n) or positive (very large n)
                        if (bi_ptr.isNegative()) {
                            break :blk -1000; // Will trigger early return for 0.0
                        } else {
                            break :blk 1000; // Will trigger early return for original value
                        }
                    }
                }
            }
        }
        // ndigits must be an integer type - if not, raise TypeError
        // (e.g., round(x, 0.5) or round(x, "string"))
        return PythonError.TypeError;
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
