/// Float formatting utilities
const std = @import("std");

// Import banker's rounding from conversion.zig
const bankersRound = @import("../../runtime/builtins/conversion.zig").bankersRound;

/// Pre-round value to precision using banker's rounding (Python semantics)
/// This ensures "%.0f" % 2.5 -> "2" (not "3")
fn bankersRoundToPrecision(value: f64, precision: u32) f64 {
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

    if (value >= 0) {
        switch (options.sign) {
            .plus => try result.append(allocator, '+'),
            .space => try result.append(allocator, ' '),
            .none => {},
        }
    }

    switch (options.format_type) {
        .repr => {
            if (@mod(value, 1.0) == 0.0 and @abs(value) < 1e15) {
                try result.writer(allocator).print("{d:.1}", .{value});
            } else {
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
            if (rounded_exp < -4 or rounded_exp >= @as(i32, @intCast(prec))) {
                // Scientific notation
                try formatGeneralScientific(allocator, &result, rounded, prec, options.alt_form, value < 0);
            } else {
                // Fixed notation
                try formatGeneralFixed(allocator, &result, rounded, prec, rounded_exp, options.alt_form, value < 0);
            }
        },
        .fixed => {
            const prec = options.precision orelse 6;
            // Pre-round using banker's rounding for Python semantics
            const rounded_value = bankersRoundToPrecision(value, prec);
            try result.writer(allocator).print("{d:.[1]}", .{ rounded_value, prec });
            // Handle alternate form for precision 0 (always include '.')
            if (options.alt_form and prec == 0) {
                try result.append(allocator, '.');
            }
        },
        .scientific => {
            const prec = options.precision orelse 6;
            // For scientific notation, precision specifies decimal places in MANTISSA
            // We need to normalize first, then apply banker's rounding to mantissa
            // e.g., %.0e % 2.5 -> 2e+00 (banker's rounds 2.5 to 2)

            const abs_val = @abs(value);
            const is_negative = value < 0;

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
                try result.append(allocator, 'e');
                if (final_exp >= 0) {
                    try result.append(allocator, '+');
                    if (final_exp < 10) try result.append(allocator, '0');
                    try result.writer(allocator).print("{d}", .{@as(u32, @intCast(final_exp))});
                } else {
                    try result.append(allocator, '-');
                    const abs_exp: u32 = @intCast(-final_exp);
                    if (abs_exp < 10) try result.append(allocator, '0');
                    try result.writer(allocator).print("{d}", .{abs_exp});
                }
            }
        },
    }

    return result.toOwnedSlice(allocator);
}

/// Format for %g in scientific notation
fn formatGeneralScientific(allocator: std.mem.Allocator, result: *std.ArrayListUnmanaged(u8), abs_val: f64, prec: u32, alt_form: bool, is_negative: bool) !void {
    _ = is_negative;
    // Format with prec-1 decimal places (prec significant figures total)
    const decimal_places = if (prec > 1) prec - 1 else 0;
    try result.writer(allocator).print("{e:.[1]}", .{ abs_val, decimal_places });

    // Convert Zig's scientific notation to Python format: 1e3 -> 1e+03
    try normalizeSciNotation(allocator, result);

    if (!alt_form) {
        // Remove trailing zeros from mantissa
        stripTrailingZeros(result);
    }
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
    _ = is_negative;
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
    }
}

/// Remove trailing zeros after decimal point
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
            const exp_part = result.items[epos..];
            const exp_len = exp_part.len;
            @memcpy(result.items[strip_to .. strip_to + exp_len], exp_part);
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
