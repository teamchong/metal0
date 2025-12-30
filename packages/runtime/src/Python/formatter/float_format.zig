/// Float formatting utilities for Python-compatible output
///
/// BANKER'S ROUNDING: All float formatting in metal0 uses banker's rounding
/// (IEEE 754 round-half-to-even) for Python compatibility.
///
/// The source of truth for banker's rounding is:
///   - bankersRound() in runtime/builtins/conversion.zig
///   - bankersRoundToPrecision() in THIS FILE (calls bankersRound)
///
/// EXACT DECIMAL EXPANSION: For large numbers (>= 1e15), we use BigInt.fromFloat()
/// to extract the exact IEEE 754 representation instead of Zig's std.fmt (Ryu).
/// This fixes cases like "%.0f" % 1e49 which should output the exact integer
/// representation (9999999999999999464902769475481793196872414789632), not a
/// rounded value (10000000000000000000000000000000000000000000000000).
///
/// DO NOT use Zig's @round for Python output - it uses round-half-away-from-zero.
const std = @import("std");
const BigInt = @import("bigint").BigInt;

// Import banker's rounding from conversion.zig - THE source of truth
const bankersRound = @import("../../runtime/builtins/conversion.zig").bankersRound;

/// Apply banker's rounding to a specific decimal precision.
///
/// Examples (Python semantics):
///   bankersRoundToPrecision(2.5, 0) -> 2.0   (round to even)
///   bankersRoundToPrecision(3.5, 0) -> 4.0   (round to even)
///   bankersRoundToPrecision(0.125, 2) -> 0.12 (round to even)
///
/// Used by py_format.zig for:
///   - "%.Nf" % value  (fixed-point formatting)
///   - "%.Ne" % value  (scientific notation)
///   - format(value, ".Nf")
///   - format(value, ".Ne")
pub fn bankersRoundToPrecision(value: f64, precision: u32) f64 {
    if (std.math.isNan(value) or std.math.isInf(value)) return value;
    const multiplier = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(precision)));
    const scaled = value * multiplier;
    const rounded = bankersRound(scaled);
    return rounded / multiplier;
}

/// Round to N significant digits using banker's rounding
fn bankersRoundSigFigs(value: f64, sig_figs: u32) f64 {
    if (std.math.isNan(value) or std.math.isInf(value) or value == 0) return value;
    const abs_val = @abs(value);
    const sign: f64 = if (value < 0) -1.0 else 1.0;

    // Calculate the order of magnitude
    const log_val = @log10(abs_val);
    const exponent: i32 = @intFromFloat(@floor(log_val));

    // Scale to get sig_figs digits before decimal point
    const scale_exp = @as(i32, @intCast(sig_figs)) - 1 - exponent;
    const multiplier = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(scale_exp)));
    const scaled = abs_val * multiplier;
    const rounded = bankersRound(scaled);
    return sign * rounded / multiplier;
}

/// Sign handling for float formatting
pub const FloatSignOption = enum { none, plus, space };

/// Format type for float formatting
pub const FloatFormatType = enum { general, fixed, scientific, repr };

/// Options for Python float formatting
pub const PyFloatFormatOptions = struct {
    sign: FloatSignOption = .none,
    precision: ?u32 = null,
    format_type: FloatFormatType = .general,
    alt_form: bool = false, // '#' flag - always include decimal point
};

// ============================================================================
// Shared Helpers (used by py_format.zig and this file)
// ============================================================================

/// Emit sign character based on value's sign bit and sign option.
/// Handles negative zero correctly via std.math.signbit().
pub fn emitFloatSign(
    result: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,
    value: f64,
    sign: FloatSignOption,
) !void {
    if (std.math.signbit(value)) {
        try result.append(allocator, '-');
    } else {
        switch (sign) {
            .plus => try result.append(allocator, '+'),
            .space => try result.append(allocator, ' '),
            .none => {},
        }
    }
}

/// Emit Python-style exponent (e+05, e-03, E+05, E-03).
/// Always uses 2-digit exponent with leading zero if needed.
pub fn emitExponent(
    result: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,
    exp: i32,
    exp_char: u8,
) !void {
    try result.append(allocator, exp_char);
    try result.append(allocator, if (exp >= 0) '+' else '-');
    const abs_exp: u32 = @intCast(@abs(exp));
    if (abs_exp < 10) try result.append(allocator, '0');
    try result.writer(allocator).print("{d}", .{abs_exp});
}

/// Format a large float (>= 1e15) using BigInt for exact decimal representation.
/// This is essential for Python compatibility where "%.0f" % 1e49 must output
/// the exact IEEE 754 representation, not a rounded value.
fn formatFixedBigInt(
    allocator: std.mem.Allocator,
    result: *std.ArrayListUnmanaged(u8),
    abs_val: f64,
    prec: u32,
    is_negative: bool,
    alt_form: bool,
) !void {
    // Add negative sign if needed
    if (is_negative) {
        try result.append(allocator, '-');
    }

    // Get the integer part using BigInt.fromFloat()
    // This extracts the exact value from IEEE 754 representation:
    // For 1e49, this gives 9999999999999999464902769475481793196872414789632
    // Note: NaN/Inf are already handled by caller, so InvalidFloat should not occur
    // Note: InvalidBase won't occur since we always use base 10
    var integer_big = BigInt.fromFloat(allocator, @floor(abs_val)) catch |err| switch (err) {
        error.InvalidFloat => return error.OutOfMemory, // Should not happen - NaN/Inf handled earlier
        error.OutOfMemory => return error.OutOfMemory,
    };
    defer integer_big.deinit();
    const int_str = integer_big.toDecimalString(allocator) catch |err| switch (err) {
        error.InvalidBase => return error.OutOfMemory, // Should not happen - we use base 10
        error.OutOfMemory => return error.OutOfMemory,
    };
    defer allocator.free(int_str);

    // Append integer part
    try result.appendSlice(allocator, int_str);

    // Handle fractional part
    if (prec > 0 or alt_form) {
        try result.append(allocator, '.');
        if (prec > 0) {
            // For very large floats, the fractional part is always 0
            // because the float precision is exhausted
            const frac = abs_val - @floor(abs_val);
            if (frac == 0) {
                try result.appendNTimes(allocator, '0', prec);
            } else {
                // Round fractional part using banker's rounding
                const multiplier = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(prec)));
                const scaled = frac * multiplier;
                const rounded: u64 = @intFromFloat(bankersRound(scaled));

                // Format with leading zeros if needed
                var buf: [64]u8 = undefined;
                const digits = std.fmt.bufPrint(&buf, "{d}", .{rounded}) catch return error.OutOfMemory;
                if (digits.len < prec) {
                    try result.appendNTimes(allocator, '0', prec - @as(u32, @intCast(digits.len)));
                }
                try result.appendSlice(allocator, digits);
            }
        }
    }
}

/// Canonical Python float formatter
pub fn formatPythonFloat(allocator: std.mem.Allocator, value: f64, options: PyFloatFormatOptions) ![]const u8 {
    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);

    if (std.math.isNan(value)) {
        switch (options.sign) {
            .plus => try result.append(allocator, '+'),
            .space => try result.append(allocator, ' '),
            .none => {},
        }
        try result.appendSlice(allocator, "nan");
        return result.toOwnedSlice(allocator);
    }

    if (std.math.isInf(value)) {
        if (value < 0) {
            try result.appendSlice(allocator, "-inf");
        } else {
            switch (options.sign) {
                .plus => try result.append(allocator, '+'),
                .space => try result.append(allocator, ' '),
                .none => {},
            }
            try result.appendSlice(allocator, "inf");
        }
        return result.toOwnedSlice(allocator);
    }

    // Use signbit to detect negative zero: -0.0 >= 0 is true, but signbit(-0.0) is true
    // We handle sign in individual format types for scientific, but need it here for repr
    if (!std.math.signbit(value)) {
        switch (options.sign) {
            .plus => try result.append(allocator, '+'),
            .space => try result.append(allocator, ' '),
            .none => {},
        }
    }

    switch (options.format_type) {
        .repr => {
            const abs_val = @abs(value);
            const is_negative = std.math.signbit(value);
            if (abs_val >= 1e16) {
                // Large numbers use scientific notation
                // Python format: 1e+16 (not 1.0e+16)
                if (is_negative) try result.append(allocator, '-');
                const log_val = @log10(abs_val);
                const exp: i32 = @intFromFloat(@floor(log_val));
                const mantissa = abs_val / std.math.pow(f64, 10.0, @as(f64, @floatFromInt(exp)));

                // Format mantissa - strip trailing zeros
                if (@mod(mantissa, 1.0) == 0.0) {
                    // Integer mantissa
                    try result.writer(allocator).print("{d}e", .{@as(u64, @intFromFloat(mantissa))});
                } else {
                    try result.writer(allocator).print("{d}e", .{mantissa});
                }
                try result.append(allocator, if (exp >= 0) '+' else '-');
                const abs_exp: u32 = @intCast(@abs(exp));
                if (abs_exp < 10) try result.append(allocator, '0');
                try result.writer(allocator).print("{d}", .{abs_exp});
            } else if (abs_val > 0 and abs_val < 1e-4) {
                // Small numbers use scientific notation
                // Use Zig's {e} formatter (Ryu algorithm) for correct mantissa,
                // then reformat exponent to Python's style (e-05 not e-5)
                var buf: [64]u8 = undefined;
                const zig_str = std.fmt.bufPrint(&buf, "{e}", .{abs_val}) catch return error.OutOfMemory;

                // Find 'e' position
                var e_pos: usize = 0;
                for (zig_str, 0..) |c, idx| {
                    if (c == 'e') {
                        e_pos = idx;
                        break;
                    }
                }

                // Add sign for original value
                if (is_negative) try result.append(allocator, '-');

                // Add mantissa (before 'e')
                try result.appendSlice(allocator, zig_str[0..e_pos]);
                try result.append(allocator, 'e');

                // Parse and reformat exponent with Python-style: always 2 digits, with sign
                const exp_str = zig_str[e_pos + 1 ..];
                const exp_sign: u8 = if (exp_str[0] == '-') '-' else '+';
                const exp_digits = if (exp_str[0] == '-' or exp_str[0] == '+') exp_str[1..] else exp_str;
                const exp = std.fmt.parseInt(i32, exp_digits, 10) catch 0;

                try result.append(allocator, exp_sign);
                const abs_exp: u32 = @intCast(@abs(exp));
                if (abs_exp < 10) try result.append(allocator, '0');
                try result.writer(allocator).print("{d}", .{abs_exp});
            } else if (@mod(value, 1.0) == 0.0 and abs_val < 1e16) {
                // Integer values: always show .0
                try result.writer(allocator).print("{d:.1}", .{value});
            } else {
                // Default representation
                try result.writer(allocator).print("{d}", .{value});
            }
        },
        .general => {
            // Python %g: uses precision as number of significant digits
            // Switches to scientific if exponent < -4 or >= precision
            // Removes trailing zeros unless alt_form
            const prec = if (options.precision) |p| (if (p == 0) @as(u32, 1) else p) else 6;
            const abs_val = @abs(value);

            // Round to significant figures
            const rounded = bankersRoundSigFigs(abs_val, prec);

            // Calculate exponent after rounding (may have changed, e.g. 9.5 -> 10)
            const rounded_exp: i32 = if (rounded == 0) 0 else @intFromFloat(@floor(@log10(rounded)));

            // Python uses scientific if exponent < -4 or >= precision
            // Use signbit to detect negative zero: -0.0 < 0 is false, but signbit(-0.0) is true
            const is_negative = std.math.signbit(value);
            if (rounded_exp < -4 or rounded_exp >= @as(i32, @intCast(prec))) {
                // Scientific notation
                try formatGeneralScientific(allocator, &result, rounded, prec, options.alt_form, is_negative);
            } else {
                // Fixed notation
                try formatGeneralFixed(allocator, &result, rounded, prec, rounded_exp, options.alt_form, is_negative);
            }
        },
        .fixed => {
            const prec = options.precision orelse 6;
            // Python preserves the sign even when rounding to 0
            // e.g., "%.0f" % -0.1 gives "-0", not "0"
            const is_negative = std.math.signbit(value);
            const abs_val = @abs(value);

            // For large numbers (>= 1e15), use BigInt for exact decimal expansion
            // This fixes cases like "%.0f" % 1e49 which should output the exact
            // IEEE 754 integer representation, not a rounded value
            if (abs_val >= 1e15) {
                try formatFixedBigInt(allocator, &result, abs_val, prec, is_negative, options.alt_form);
            } else {
                // Fast path for normal numbers - use standard formatting
                // Pre-round using banker's rounding for Python semantics
                const rounded_value = bankersRoundToPrecision(abs_val, prec);
                // Add negative sign if original was negative (even if rounded to 0)
                if (is_negative) {
                    try result.append(allocator, '-');
                }
                try result.writer(allocator).print("{d:.[1]}", .{ rounded_value, prec });
                // Handle alternate form for precision 0 (always include '.')
                if (options.alt_form and prec == 0) {
                    try result.append(allocator, '.');
                }
            }
        },
        .scientific => {
            const prec = options.precision orelse 6;
            // For scientific notation, precision specifies decimal places in MANTISSA
            // We need to normalize first, then apply banker's rounding to mantissa
            // e.g., %.0e % 2.5 -> 2e+00 (banker's rounds 2.5 to 2)

            const abs_val = @abs(value);
            // Use signbit to detect negative zero: -0.0 < 0 is false, but signbit(-0.0) is true
            const is_negative = std.math.signbit(value);

            // Add negative sign if needed
            if (is_negative) {
                try result.append(allocator, '-');
            }

            if (abs_val == 0) {
                // Special case: 0
                try result.append(allocator, '0');
                if (prec > 0 or options.alt_form) {
                    try result.append(allocator, '.');
                    try result.appendNTimes(allocator, '0', prec);
                }
                try result.appendSlice(allocator, "e+00");
            } else {
                // Calculate exponent
                const log_val = @log10(abs_val);
                const exp: i32 = @intFromFloat(@floor(log_val));

                // Normalize mantissa to 1.xxx
                var mantissa = abs_val;
                if (abs_val >= 10.0) {
                    const divisor = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(exp)));
                    mantissa = abs_val / divisor;
                } else if (abs_val < 1.0) {
                    const multiplier = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(-exp)));
                    mantissa = abs_val * multiplier;
                }

                // Apply banker's rounding to mantissa at the specified precision
                const rounded_mantissa = bankersRoundToPrecision(mantissa, prec);

                // Check if rounding caused mantissa to reach 10 (e.g., 9.95 -> 10.0 at prec=1)
                var final_mantissa = rounded_mantissa;
                var final_exp = exp;
                if (rounded_mantissa >= 10.0) {
                    final_mantissa = rounded_mantissa / 10.0;
                    final_exp += 1;
                }

                // Format mantissa
                try result.writer(allocator).print("{d:.[1]}", .{ final_mantissa, prec });

                // Handle alternate form for precision 0 (always include '.')
                if (options.alt_form and prec == 0) {
                    try result.append(allocator, '.');
                }

                // Add exponent
                try emitExponent(result, allocator, final_exp, 'e');
            }
        },
    }

    return result.toOwnedSlice(allocator);
}

/// Format for %g in scientific notation
fn formatGeneralScientific(allocator: std.mem.Allocator, result: *std.ArrayListUnmanaged(u8), abs_val: f64, prec: u32, alt_form: bool, is_negative: bool) !void {
    // Add negative sign if needed (for -0.0 which has signbit set)
    if (is_negative) {
        try result.append(allocator, '-');
    }

    if (abs_val == 0) {
        // Special case: 0
        if (alt_form) {
            try result.append(allocator, '0');
            try result.append(allocator, '.');
            // For alt_form with precision N, add N-1 zeros after decimal
            if (prec > 1) {
                try result.appendNTimes(allocator, '0', prec - 1);
            }
            try result.appendSlice(allocator, "e+00");
        } else {
            try result.appendSlice(allocator, "0e+00");
        }
        return;
    }

    // Calculate exponent
    const log_val = @log10(abs_val);
    const exp: i32 = @intFromFloat(@floor(log_val));

    // Normalize mantissa to 1.xxx
    var mantissa = abs_val;
    if (abs_val >= 10.0) {
        const divisor = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(exp)));
        mantissa = abs_val / divisor;
    } else if (abs_val < 1.0) {
        const multiplier = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(-exp)));
        mantissa = abs_val * multiplier;
    }

    // For %g, precision means total significant figures, so mantissa gets prec-1 decimal places
    const decimal_places = if (prec > 1) prec - 1 else 0;

    // Apply banker's rounding to mantissa at the specified precision
    const rounded_mantissa = bankersRoundToPrecision(mantissa, decimal_places);

    // Check if rounding caused mantissa to reach 10 (e.g., 9.95 -> 10.0 at prec=1)
    var final_mantissa = rounded_mantissa;
    var final_exp = exp;
    if (rounded_mantissa >= 10.0) {
        final_mantissa = rounded_mantissa / 10.0;
        final_exp += 1;
    }

    // Format mantissa
    try result.writer(allocator).print("{d:.[1]}", .{ final_mantissa, decimal_places });

    if (!alt_form) {
        // Remove trailing zeros from mantissa (before adding exponent)
        stripTrailingZerosBeforeExp(result);
        // Also remove trailing decimal point if not alt_form
        if (result.items.len > 0 and result.items[result.items.len - 1] == '.') {
            result.items.len -= 1;
        }
    } else {
        // alt_form: ensure there's a decimal point
        var has_dot = false;
        for (result.items) |c| {
            if (c == '.') {
                has_dot = true;
                break;
            }
        }
        if (!has_dot) {
            try result.append(allocator, '.');
        }
    }

    // Add exponent
    try emitExponent(result, allocator, final_exp, 'e');
}

/// Convert Zig's scientific notation to Python format
/// 1e3 -> 1e+03, 1e-5 -> 1e-05
fn normalizeSciNotation(allocator: std.mem.Allocator, result: *std.ArrayListUnmanaged(u8)) !void {
    // Find 'e' position
    var e_pos: ?usize = null;
    for (result.items, 0..) |c, idx| {
        if (c == 'e' or c == 'E') {
            e_pos = idx;
            break;
        }
    }

    if (e_pos) |pos| {
        if (pos + 1 >= result.items.len) return;

        const exp_start = pos + 1;
        var sign: u8 = '+';
        var exp_digits_start = exp_start;

        // Check for existing sign
        if (result.items[exp_start] == '+' or result.items[exp_start] == '-') {
            sign = result.items[exp_start];
            exp_digits_start = exp_start + 1;
        }

        // Extract exponent digits
        const exp_str = result.items[exp_digits_start..];
        var exp_val: i32 = 0;
        for (exp_str) |c| {
            if (c >= '0' and c <= '9') {
                exp_val = exp_val * 10 + @as(i32, c - '0');
            }
        }

        // Remove everything after 'e' and rebuild
        result.items.len = pos + 1;

        // Add sign (always for Python compatibility)
        try result.append(allocator, sign);

        // Add exponent with at least 2 digits
        if (exp_val < 10) {
            try result.append(allocator, '0');
        }
        try result.writer(allocator).print("{d}", .{exp_val});
    }
}

/// Format for %g in fixed notation
fn formatGeneralFixed(allocator: std.mem.Allocator, result: *std.ArrayListUnmanaged(u8), abs_val: f64, prec: u32, exponent: i32, alt_form: bool, is_negative: bool) !void {
    // Add negative sign if needed (for -0.0 which has signbit set)
    if (is_negative) {
        try result.append(allocator, '-');
    }
    // Calculate how many decimal places we need
    // sig_figs = prec, exp gives position of first significant digit
    // decimal_places = max(0, prec - 1 - exp) for positive exp
    // For exp >= 0: decimal_places = prec - 1 - exp (but >= 0)
    // For exp < 0: decimal_places = prec - 1 - exp (e.g., exp=-1, prec=1: 1-1-(-1) = 1)
    const decimal_places: u32 = if (exponent >= @as(i32, @intCast(prec)) - 1)
        0
    else if (exponent < 0)
        @intCast(@as(i32, @intCast(prec)) - 1 - exponent)
    else
        @intCast(@as(i32, @intCast(prec)) - 1 - exponent);

    try result.writer(allocator).print("{d:.[1]}", .{ abs_val, decimal_places });

    if (!alt_form) {
        // Remove trailing zeros (but keep at least one digit after '.' if alt_form)
        stripTrailingZeros(result);
        // Also remove trailing '.' unless alt_form
        if (result.items.len > 0 and result.items[result.items.len - 1] == '.') {
            _ = result.pop();
        }
    } else {
        // alt_form: always include decimal point
        // Check if there's already a decimal point
        var has_dot = false;
        for (result.items) |c| {
            if (c == '.') {
                has_dot = true;
                break;
            }
        }
        if (!has_dot) {
            try result.append(allocator, '.');
        }
    }
}

/// Remove trailing zeros from mantissa BEFORE exponent is added
/// This version does not handle 'e' parts since they haven't been added yet
fn stripTrailingZerosBeforeExp(result: *std.ArrayListUnmanaged(u8)) void {
    // Check if there's a decimal point
    var has_dot = false;
    for (result.items) |c| {
        if (c == '.') {
            has_dot = true;
            break;
        }
    }
    if (!has_dot) return;

    // Strip trailing zeros
    while (result.items.len > 0 and result.items[result.items.len - 1] == '0') {
        result.items.len -= 1;
    }
}

/// Remove trailing zeros after decimal point (handling existing exponent)
fn stripTrailingZeros(result: *std.ArrayListUnmanaged(u8)) void {
    // Find 'e' position if exists
    var e_pos: ?usize = null;
    for (result.items, 0..) |c, idx| {
        if (c == 'e') {
            e_pos = idx;
            break;
        }
    }

    const end_pos = e_pos orelse result.items.len;

    // Check if there's a decimal point
    var has_dot = false;
    for (result.items[0..end_pos]) |c| {
        if (c == '.') {
            has_dot = true;
            break;
        }
    }
    if (!has_dot) return;

    // Strip trailing zeros before 'e' (or end)
    var strip_to = end_pos;
    while (strip_to > 0 and result.items[strip_to - 1] == '0') {
        strip_to -= 1;
    }

    if (strip_to < end_pos) {
        // Move 'e...' part (if any) left
        if (e_pos) |epos| {
            const exp_len = result.items.len - epos;
            // Use std.mem.copyBackwards to handle overlapping memory safely
            std.mem.copyBackwards(u8, result.items[strip_to .. strip_to + exp_len], result.items[epos..]);
            result.items.len = strip_to + exp_len;
        } else {
            result.items.len = strip_to;
        }
    }
}

/// Format float value for str() and format(x, '') - uses repr format (full precision)
pub fn formatFloat(value: f64, allocator: std.mem.Allocator) ![]const u8 {
    return formatPythonFloat(allocator, value, .{ .format_type = .repr });
}

/// Python-style floored modulo
pub fn pyFloatMod(a: f64, b: f64) f64 {
    const result = @mod(a, b);
    if ((result < 0 and b > 0) or (result > 0 and b < 0)) {
        return result + b;
    }
    return result;
}

/// Python-style floor division
pub fn pyFloatFloorDiv(a: f64, b: f64) f64 {
    return @floor(a / b);
}
