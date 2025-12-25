/// Unified Format Dispatcher
///
/// ALL formatting in metal0 goes through this module.
/// This mirrors Python's format protocol where every type has
/// __str__, __repr__, and __format__ methods.
///
/// Usage:
///   pyFormatDispatch(alloc, value, .str, null)     // str(value)
///   pyFormatDispatch(alloc, value, .repr, null)    // repr(value)
///   pyFormatDispatch(alloc, value, .format, ".2f") // format(value, ".2f")
///
/// DO NOT bypass this module. All user-visible output must go through here.

const std = @import("std");
const BigInt = @import("bigint").BigInt;
const format_spec = @import("formatter/format_spec.zig");
const FormatSpec = format_spec.FormatSpec;

/// Format mode - mirrors Python's __str__, __repr__, __format__
pub const FormatMode = enum {
    str, // Human-readable (Python's __str__)
    repr, // Unambiguous, eval-able (Python's __repr__)
    format, // With format spec (Python's __format__)
};

/// Sign handling options
pub const SignMode = enum {
    none, // Only show '-' for negative
    plus, // Show '+' for positive, '-' for negative
    space, // Show ' ' for positive, '-' for negative
};

/// THE single entry point for all formatting
/// All str(), repr(), format(), print(), % formatting must call this
pub fn pyFormatDispatch(
    allocator: std.mem.Allocator,
    value: anytype,
    mode: FormatMode,
    spec_str: ?[]const u8,
) ![]const u8 {
    const T = @TypeOf(value);
    const spec = if (spec_str) |s| format_spec.parseFormatSpec(s) else FormatSpec{};

    // Check for invalid format spec
    if (spec.invalid) {
        return error.ValueError;
    }

    // Dispatch by type at comptime (zero runtime overhead)
    const type_info = @typeInfo(T);
    return switch (type_info) {
        .int, .comptime_int => formatInt(allocator, value, mode, spec),
        .float, .comptime_float => formatFloat(allocator, @as(f64, @floatCast(value)), mode, spec),
        .bool => formatBool(allocator, value, mode, spec),
        .pointer => |ptr| blk: {
            // Handle []const u8 (strings)
            if (ptr.size == .slice and ptr.child == u8) {
                break :blk formatString(allocator, value, mode, spec);
            }
            // Handle single-item pointers to arrays of u8 (string literals)
            if (ptr.size == .one) {
                const child_info = @typeInfo(ptr.child);
                if (child_info == .array and child_info.array.child == u8) {
                    break :blk formatString(allocator, value, mode, spec);
                }
            }
            // Other pointers
            break :blk formatPointer(allocator, value, mode);
        },
        .array => |arr| blk: {
            if (arr.child == u8) {
                break :blk formatString(allocator, &value, mode, spec);
            }
            break :blk formatArray(allocator, value, mode);
        },
        .@"struct" => formatStruct(allocator, value, mode, spec),
        .optional => formatOptional(allocator, value, mode, spec_str),
        .@"enum" => formatEnum(allocator, value, mode),
        .null => formatNone(allocator),
        else => formatFallback(allocator, value, mode),
    };
}

// =============================================================================
// FLOAT FORMATTING - Uses BigInt for exact decimal of large numbers
// =============================================================================

/// Banker's rounding (IEEE 754 round-half-to-even)
/// Source of truth for all Python rounding
fn bankersRound(value: f64) f64 {
    if (std.math.isNan(value) or std.math.isInf(value)) return value;

    const floor_val = @floor(value);
    const frac = value - floor_val;

    // Check if exactly at 0.5
    if (@abs(frac - 0.5) < 1e-9) {
        // Round to nearest even
        const floor_int: i64 = @intFromFloat(floor_val);
        if (@mod(floor_int, 2) == 0) {
            return floor_val; // Even floor, round down
        } else {
            return floor_val + 1.0; // Odd floor, round up
        }
    }

    return @round(value);
}

/// Apply banker's rounding at specified precision
fn bankersRoundToPrecision(value: f64, precision: u32) f64 {
    if (std.math.isNan(value) or std.math.isInf(value)) return value;
    const multiplier = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(precision)));
    const scaled = value * multiplier;
    const rounded = bankersRound(scaled);
    return rounded / multiplier;
}

/// Float formatting with exact decimal expansion for large numbers
fn formatFloat(allocator: std.mem.Allocator, value: f64, mode: FormatMode, spec: FormatSpec) ![]const u8 {
    // Handle special values first
    if (std.math.isNan(value)) {
        const nan_str = if (spec.fmt_type == 'F' or spec.fmt_type == 'E' or spec.fmt_type == 'G') "NAN" else "nan";
        return applyPadding(allocator, nan_str, spec);
    }
    if (std.math.isInf(value)) {
        const inf_str = if (std.math.signbit(value))
            (if (spec.fmt_type == 'F' or spec.fmt_type == 'E' or spec.fmt_type == 'G') "-INF" else "-inf")
        else switch (spec.sign) {
            .always => if (spec.fmt_type == 'F' or spec.fmt_type == 'E' or spec.fmt_type == 'G') "+INF" else "+inf",
            .space => if (spec.fmt_type == 'F' or spec.fmt_type == 'E' or spec.fmt_type == 'G') " INF" else " inf",
            else => if (spec.fmt_type == 'F' or spec.fmt_type == 'E' or spec.fmt_type == 'G') "INF" else "inf",
        };
        return applyPadding(allocator, inf_str, spec);
    }

    // Dispatch by format type
    const fmt_type = if (spec.fmt_type != 0) spec.fmt_type else 'g';

    const formatted = switch (fmt_type) {
        'f', 'F' => try formatFloatFixed(allocator, value, spec),
        'e', 'E' => try formatFloatScientific(allocator, value, spec),
        'g', 'G' => try formatFloatGeneral(allocator, value, spec),
        '%' => try formatFloatPercent(allocator, value, spec),
        'r' => try formatFloatRepr(allocator, value), // For %r
        else => switch (mode) {
            .repr, .str => try formatFloatRepr(allocator, value),
            .format => try formatFloatGeneral(allocator, value, spec),
        },
    };

    return applyPadding(allocator, formatted, spec);
}

/// Fixed-point format with EXACT decimal expansion using BigInt for large numbers
fn formatFloatFixed(allocator: std.mem.Allocator, value: f64, spec: FormatSpec) ![]const u8 {
    const precision: u32 = @intCast(spec.precision orelse 6);
    const is_negative = std.math.signbit(value);
    const abs_val = @abs(value);

    // For very large numbers (>= 1e15), use BigInt for exact representation
    // This fixes the 1e49 issue - Zig's Ryu rounds to 1e49 but the actual f64
    // represents 9999999999999999464902769475481793196872414789632
    if (abs_val >= 1e15) {
        return formatFloatFixedBigInt(allocator, value, precision, is_negative, spec);
    }

    // Fast path for normal numbers
    return formatFloatFixedFast(allocator, value, precision, is_negative, spec);
}

/// Use BigInt.fromFloat() for exact decimal representation of large floats
fn formatFloatFixedBigInt(
    allocator: std.mem.Allocator,
    value: f64,
    precision: u32,
    is_negative: bool,
    spec: FormatSpec,
) ![]const u8 {
    const abs_val = @abs(value);

    // Get exact integer part using BigInt (handles 1e49 correctly)
    // BigInt.fromFloat() extracts the exact IEEE 754 representation
    var integer_big = try BigInt.fromFloat(allocator, @floor(abs_val));
    defer integer_big.deinit();
    const int_str = try integer_big.toDecimalString(allocator);
    defer allocator.free(int_str);

    // Build result
    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    // Sign
    if (is_negative) {
        try result.append(allocator, '-');
    } else {
        switch (spec.sign) {
            .always => try result.append(allocator, '+'),
            .space => try result.append(allocator, ' '),
            else => {},
        }
    }

    // Integer part (with grouping if requested)
    if (spec.grouping_char) |sep| {
        try appendWithGrouping(allocator, &result, int_str, sep);
    } else {
        try result.appendSlice(allocator, int_str);
    }

    // Fractional part
    if (precision > 0 or spec.alternate) {
        try result.append(allocator, '.');
        if (precision > 0) {
            // For very large floats, fractional part is always 0
            const frac = abs_val - @floor(abs_val);
            if (frac == 0) {
                try result.appendNTimes(allocator, '0', precision);
            } else {
                try appendFractionalDigits(allocator, &result, frac, precision);
            }
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Fast path for normal-sized floats
fn formatFloatFixedFast(
    allocator: std.mem.Allocator,
    value: f64,
    precision: u32,
    is_negative: bool,
    spec: FormatSpec,
) ![]const u8 {
    const abs_val = @abs(value);

    // Apply banker's rounding
    const rounded = bankersRoundToPrecision(abs_val, precision);

    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    // Sign - use signbit to handle -0.0 correctly
    if (is_negative) {
        try result.append(allocator, '-');
    } else {
        switch (spec.sign) {
            .always => try result.append(allocator, '+'),
            .space => try result.append(allocator, ' '),
            else => {},
        }
    }

    // Format the rounded value
    var buf: [64]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buf, "{d:.[1]}", .{ rounded, precision }) catch return error.FormatError;

    // Apply grouping if needed
    if (spec.grouping_char) |sep| {
        // Split into integer and fractional parts
        if (std.mem.indexOf(u8, formatted, ".")) |dot_pos| {
            try appendWithGrouping(allocator, &result, formatted[0..dot_pos], sep);
            try result.appendSlice(allocator, formatted[dot_pos..]);
        } else {
            try appendWithGrouping(allocator, &result, formatted, sep);
        }
    } else {
        try result.appendSlice(allocator, formatted);
    }

    // Handle alternate form (ensure . is present)
    if (spec.alternate and std.mem.indexOf(u8, result.items, ".") == null) {
        try result.append(allocator, '.');
    }

    return result.toOwnedSlice(allocator);
}

/// Scientific notation format
fn formatFloatScientific(allocator: std.mem.Allocator, value: f64, spec: FormatSpec) ![]const u8 {
    const precision: u32 = @intCast(spec.precision orelse 6);
    const is_negative = std.math.signbit(value);
    const abs_val = @abs(value);
    const uppercase = spec.fmt_type == 'E';

    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    // Sign
    if (is_negative) {
        try result.append(allocator, '-');
    } else {
        switch (spec.sign) {
            .always => try result.append(allocator, '+'),
            .space => try result.append(allocator, ' '),
            else => {},
        }
    }

    if (abs_val == 0) {
        // Handle zero specially
        try result.append(allocator, '0');
        if (precision > 0 or spec.alternate) {
            try result.append(allocator, '.');
            try result.appendNTimes(allocator, '0', precision);
        }
        try result.append(allocator, if (uppercase) 'E' else 'e');
        try result.appendSlice(allocator, "+00");
    } else {
        // Get exponent
        const exp = @floor(std.math.log10(abs_val));
        const exp_int: i32 = @intFromFloat(exp);

        // Normalize mantissa
        const mantissa = abs_val / std.math.pow(f64, 10.0, exp);

        // Apply banker's rounding to mantissa
        const rounded_mantissa = bankersRoundToPrecision(mantissa, precision);

        // Check if rounding caused overflow (1.999... -> 10.0)
        var final_mantissa = rounded_mantissa;
        var final_exp = exp_int;
        if (rounded_mantissa >= 10.0) {
            final_mantissa = rounded_mantissa / 10.0;
            final_exp += 1;
        }

        // Format mantissa
        var buf: [32]u8 = undefined;
        const mantissa_str = std.fmt.bufPrint(&buf, "{d:.[1]}", .{ final_mantissa, precision }) catch return error.FormatError;
        try result.appendSlice(allocator, mantissa_str);

        // Format exponent
        try result.append(allocator, if (uppercase) 'E' else 'e');
        try result.append(allocator, if (final_exp >= 0) '+' else '-');
        const abs_exp: u32 = @intCast(@abs(final_exp));
        if (abs_exp < 10) {
            try result.append(allocator, '0');
        }
        var exp_buf: [16]u8 = undefined;
        const exp_str = std.fmt.bufPrint(&exp_buf, "{d}", .{abs_exp}) catch return error.FormatError;
        try result.appendSlice(allocator, exp_str);
    }

    return result.toOwnedSlice(allocator);
}

/// General format (like %g) - chooses between fixed and scientific
fn formatFloatGeneral(allocator: std.mem.Allocator, value: f64, spec: FormatSpec) ![]const u8 {
    const precision: u32 = @intCast(spec.precision orelse 6);
    const sig_figs = if (precision == 0) 1 else precision;
    const abs_val = @abs(value);

    if (abs_val == 0) {
        return formatFloatFixed(allocator, value, spec);
    }

    const exp = @floor(std.math.log10(abs_val));
    const exp_int: i32 = @intFromFloat(exp);

    // Python's %g: use scientific if exp < -4 or exp >= precision
    if (exp_int < -4 or exp_int >= @as(i32, @intCast(sig_figs))) {
        var sci_spec = spec;
        sci_spec.precision = if (sig_figs > 1) sig_figs - 1 else 0;
        const result = try formatFloatScientific(allocator, value, sci_spec);
        if (!spec.alternate) {
            return stripTrailingZeros(allocator, result);
        }
        return result;
    } else {
        // Use fixed format
        const fixed_precision = if (sig_figs > @as(u32, @intCast(@max(0, exp_int + 1))))
            sig_figs - @as(u32, @intCast(exp_int + 1))
        else
            0;
        var fixed_spec = spec;
        fixed_spec.precision = fixed_precision;
        const result = try formatFloatFixed(allocator, value, fixed_spec);
        if (!spec.alternate) {
            return stripTrailingZeros(allocator, result);
        }
        return result;
    }
}

/// Percentage format
fn formatFloatPercent(allocator: std.mem.Allocator, value: f64, spec: FormatSpec) ![]const u8 {
    var percent_spec = spec;
    percent_spec.precision = spec.precision orelse 6;
    const formatted = try formatFloatFixed(allocator, value * 100.0, percent_spec);

    var result: std.ArrayListUnmanaged(u8) = .{};
    try result.appendSlice(allocator, formatted);
    allocator.free(formatted);
    try result.append(allocator, '%');
    return result.toOwnedSlice(allocator);
}

/// Repr format for floats (shortest representation)
fn formatFloatRepr(allocator: std.mem.Allocator, value: f64) ![]const u8 {
    const is_negative = std.math.signbit(value);
    const abs_val = @abs(value);

    // Determine if we need scientific notation
    const use_scientific = abs_val != 0 and (abs_val >= 1e16 or abs_val < 1e-4);

    var buf: [64]u8 = undefined;
    const formatted = if (use_scientific)
        std.fmt.bufPrint(&buf, "{e}", .{abs_val}) catch return error.FormatError
    else
        std.fmt.bufPrint(&buf, "{d}", .{abs_val}) catch return error.FormatError;

    var result: std.ArrayListUnmanaged(u8) = .{};
    if (is_negative) {
        try result.append(allocator, '-');
    }
    try result.appendSlice(allocator, formatted);

    // Ensure .0 for integer-valued floats
    if (std.mem.indexOf(u8, result.items, ".") == null and
        std.mem.indexOf(u8, result.items, "e") == null)
    {
        try result.appendSlice(allocator, ".0");
    }

    return result.toOwnedSlice(allocator);
}

// =============================================================================
// INTEGER FORMATTING
// =============================================================================

fn formatInt(allocator: std.mem.Allocator, value: anytype, mode: FormatMode, spec: FormatSpec) ![]const u8 {
    _ = mode;

    const fmt_type = if (spec.fmt_type != 0) spec.fmt_type else 'd';

    // Determine base
    const base: u8 = switch (fmt_type) {
        'b' => 2,
        'o' => 8,
        'x', 'X' => 16,
        else => 10,
    };

    const T = @TypeOf(value);
    const is_negative = if (@typeInfo(T) == .int and @typeInfo(T).int.signedness == .signed)
        value < 0
    else
        false;

    var buf: [128]u8 = undefined;
    const abs_value = if (is_negative) -%@as(@TypeOf(value), value) else value;

    const formatted = std.fmt.bufPrint(&buf, switch (base) {
        2 => "{b}",
        8 => "{o}",
        16 => if (fmt_type == 'X') "{X}" else "{x}",
        else => "{d}",
    }, .{abs_value}) catch return error.FormatError;

    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    // Sign
    if (is_negative) {
        try result.append(allocator, '-');
    } else {
        switch (spec.sign) {
            .always => try result.append(allocator, '+'),
            .space => try result.append(allocator, ' '),
            else => {},
        }
    }

    // Alternate form prefix
    if (spec.alternate) {
        switch (base) {
            2 => try result.appendSlice(allocator, "0b"),
            8 => try result.appendSlice(allocator, "0o"),
            16 => try result.appendSlice(allocator, if (fmt_type == 'X') "0X" else "0x"),
            else => {},
        }
    }

    // Number with grouping
    if (spec.grouping_char) |sep| {
        try appendWithGrouping(allocator, &result, formatted, sep);
    } else {
        try result.appendSlice(allocator, formatted);
    }

    return applyPadding(allocator, try result.toOwnedSlice(allocator), spec);
}

// =============================================================================
// STRING FORMATTING
// =============================================================================

fn formatString(allocator: std.mem.Allocator, value: []const u8, mode: FormatMode, spec: FormatSpec) ![]const u8 {
    return switch (mode) {
        .str => blk: {
            // Apply precision (truncation) and width
            const truncated = if (spec.precision) |p|
                value[0..@min(p, value.len)]
            else
                value;
            const result = try allocator.dupe(u8, truncated);
            break :blk applyPadding(allocator, result, spec);
        },
        .repr => formatStringRepr(allocator, value),
        .format => blk: {
            const truncated = if (spec.precision) |p|
                value[0..@min(p, value.len)]
            else
                value;
            const result = try allocator.dupe(u8, truncated);
            break :blk applyPadding(allocator, result, spec);
        },
    };
}

/// Format string for repr() - adds quotes and escapes
fn formatStringRepr(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    try result.append(allocator, '\'');

    for (value) |c| {
        switch (c) {
            '\'' => try result.appendSlice(allocator, "\\'"),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            '\n' => try result.appendSlice(allocator, "\\n"),
            '\r' => try result.appendSlice(allocator, "\\r"),
            '\t' => try result.appendSlice(allocator, "\\t"),
            else => if (c < 32 or c >= 127) {
                var buf: [4]u8 = undefined;
                const hex = std.fmt.bufPrint(&buf, "\\x{x:0>2}", .{c}) catch unreachable;
                try result.appendSlice(allocator, hex);
            } else {
                try result.append(allocator, c);
            },
        }
    }

    try result.append(allocator, '\'');

    return result.toOwnedSlice(allocator);
}

// =============================================================================
// BOOL FORMATTING
// =============================================================================

fn formatBool(allocator: std.mem.Allocator, value: bool, mode: FormatMode, spec: FormatSpec) ![]const u8 {
    _ = mode;
    const str = if (value) "True" else "False";
    return applyPadding(allocator, try allocator.dupe(u8, str), spec);
}

// =============================================================================
// OTHER TYPE FORMATTING
// =============================================================================

fn formatStruct(allocator: std.mem.Allocator, value: anytype, mode: FormatMode, spec: FormatSpec) ![]const u8 {
    _ = spec;
    const T = @TypeOf(value);

    // Check for __str__ or __repr__ methods
    if (mode == .str and @hasDecl(T, "__str__")) {
        return value.__str__();
    }
    if (@hasDecl(T, "__repr__")) {
        return value.__repr__();
    }

    // Check if it's a tuple-like struct (all numeric field names)
    const fields = @typeInfo(T).@"struct".fields;
    var is_tuple = true;
    for (fields) |f| {
        if (f.name.len == 0 or f.name[0] < '0' or f.name[0] > '9') {
            is_tuple = false;
            break;
        }
    }

    if (is_tuple) {
        return formatTuple(allocator, value);
    }

    // Generic struct formatting
    var result: std.ArrayListUnmanaged(u8) = .{};
    try result.appendSlice(allocator, @typeName(T));
    try result.append(allocator, '(');

    inline for (fields, 0..) |f, i| {
        if (i > 0) try result.appendSlice(allocator, ", ");
        try result.appendSlice(allocator, f.name);
        try result.append(allocator, '=');
        const field_str = try pyFormatDispatch(allocator, @field(value, f.name), .repr, null);
        defer allocator.free(field_str);
        try result.appendSlice(allocator, field_str);
    }

    try result.append(allocator, ')');
    return result.toOwnedSlice(allocator);
}

fn formatTuple(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    const T = @TypeOf(value);
    const fields = @typeInfo(T).@"struct".fields;

    var result: std.ArrayListUnmanaged(u8) = .{};
    try result.append(allocator, '(');

    inline for (fields, 0..) |f, i| {
        if (i > 0) try result.appendSlice(allocator, ", ");
        const field_str = try pyFormatDispatch(allocator, @field(value, f.name), .repr, null);
        defer allocator.free(field_str);
        try result.appendSlice(allocator, field_str);
    }

    // Single-element tuple needs trailing comma
    if (fields.len == 1) {
        try result.append(allocator, ',');
    }

    try result.append(allocator, ')');
    return result.toOwnedSlice(allocator);
}

fn formatArray(allocator: std.mem.Allocator, value: anytype, mode: FormatMode) ![]const u8 {
    _ = mode;
    var result: std.ArrayListUnmanaged(u8) = .{};
    try result.append(allocator, '[');

    for (value, 0..) |item, i| {
        if (i > 0) try result.appendSlice(allocator, ", ");
        const item_str = try pyFormatDispatch(allocator, item, .repr, null);
        defer allocator.free(item_str);
        try result.appendSlice(allocator, item_str);
    }

    try result.append(allocator, ']');
    return result.toOwnedSlice(allocator);
}

fn formatOptional(allocator: std.mem.Allocator, value: anytype, mode: FormatMode, spec_str: ?[]const u8) ![]const u8 {
    if (value) |v| {
        return pyFormatDispatch(allocator, v, mode, spec_str);
    } else {
        return formatNone(allocator);
    }
}

fn formatEnum(allocator: std.mem.Allocator, value: anytype, mode: FormatMode) ![]const u8 {
    _ = mode;
    return allocator.dupe(u8, @tagName(value));
}

fn formatPointer(allocator: std.mem.Allocator, value: anytype, mode: FormatMode) ![]const u8 {
    _ = mode;
    var buf: [32]u8 = undefined;
    const ptr_int = @intFromPtr(value);
    const formatted = std.fmt.bufPrint(&buf, "0x{x}", .{ptr_int}) catch return error.FormatError;
    return allocator.dupe(u8, formatted);
}

fn formatNone(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, "None");
}

fn formatFallback(allocator: std.mem.Allocator, value: anytype, mode: FormatMode) ![]const u8 {
    _ = mode;
    return std.fmt.allocPrint(allocator, "{any}", .{value});
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/// Add thousands grouping to a number string
fn appendWithGrouping(allocator: std.mem.Allocator, result: *std.ArrayListUnmanaged(u8), digits: []const u8, sep: u8) !void {
    const len = digits.len;
    var i: usize = 0;

    // Add digits with separators every 3 digits from the right
    while (i < len) {
        const remaining = len - i;
        const group_size = if (remaining > 3 and remaining % 3 != 0) remaining % 3 else if (remaining > 3) 3 else remaining;

        try result.appendSlice(allocator, digits[i .. i + group_size]);
        i += group_size;

        if (i < len) {
            try result.append(allocator, sep);
        }
    }
}

/// Append fractional digits with banker's rounding
fn appendFractionalDigits(allocator: std.mem.Allocator, result: *std.ArrayListUnmanaged(u8), frac: f64, precision: u32) !void {
    const multiplier = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(precision)));
    const scaled = frac * multiplier;
    const rounded: u64 = @intFromFloat(bankersRound(scaled));

    // Format with leading zeros
    var buf: [64]u8 = undefined;
    const digits = std.fmt.bufPrint(&buf, "{d}", .{rounded}) catch return error.FormatError;

    // Add leading zeros if needed
    if (digits.len < precision) {
        try result.appendNTimes(allocator, '0', precision - @as(u32, @intCast(digits.len)));
    }
    try result.appendSlice(allocator, digits);
}

/// Strip trailing zeros from a formatted number
fn stripTrailingZeros(allocator: std.mem.Allocator, formatted: []const u8) ![]const u8 {
    defer allocator.free(formatted);

    // Find the dot position
    const dot_pos = std.mem.indexOf(u8, formatted, ".") orelse return allocator.dupe(u8, formatted);

    // Find the exponent position if any
    const exp_pos = std.mem.indexOfAny(u8, formatted, "eE");

    // Find where to trim
    const end_pos = exp_pos orelse formatted.len;
    var trim_pos = end_pos;

    // Walk backwards from end, stripping zeros
    while (trim_pos > dot_pos + 1 and formatted[trim_pos - 1] == '0') {
        trim_pos -= 1;
    }

    // Also strip trailing dot if all decimals were zeros
    if (trim_pos == dot_pos + 1 and trim_pos > 0 and formatted[trim_pos - 1] == '.') {
        trim_pos -= 1;
    }

    // Reconstruct with exponent if present
    if (exp_pos) |ep| {
        var result: std.ArrayListUnmanaged(u8) = .{};
        try result.appendSlice(allocator, formatted[0..trim_pos]);
        try result.appendSlice(allocator, formatted[ep..]);
        return result.toOwnedSlice(allocator);
    } else {
        return allocator.dupe(u8, formatted[0..trim_pos]);
    }
}

/// Apply width and alignment padding
fn applyPadding(allocator: std.mem.Allocator, formatted: []const u8, spec: FormatSpec) ![]const u8 {
    const width = spec.width orelse return formatted;
    if (formatted.len >= width) return formatted;

    defer allocator.free(formatted);

    const padding = width - formatted.len;
    var result: std.ArrayListUnmanaged(u8) = .{};
    errdefer result.deinit(allocator);

    switch (spec.alignment) {
        .left => {
            try result.appendSlice(allocator, formatted);
            try result.appendNTimes(allocator, spec.fill, padding);
        },
        .right => {
            try result.appendNTimes(allocator, spec.fill, padding);
            try result.appendSlice(allocator, formatted);
        },
        .center => {
            const left_pad = padding / 2;
            const right_pad = padding - left_pad;
            try result.appendNTimes(allocator, spec.fill, left_pad);
            try result.appendSlice(allocator, formatted);
            try result.appendNTimes(allocator, spec.fill, right_pad);
        },
        .sign_aware => {
            // Insert padding after the sign
            if (formatted.len > 0 and (formatted[0] == '-' or formatted[0] == '+' or formatted[0] == ' ')) {
                try result.append(allocator, formatted[0]);
                try result.appendNTimes(allocator, spec.fill, padding);
                try result.appendSlice(allocator, formatted[1..]);
            } else {
                try result.appendNTimes(allocator, spec.fill, padding);
                try result.appendSlice(allocator, formatted);
            }
        },
    }

    return result.toOwnedSlice(allocator);
}

// =============================================================================
// TESTS
// =============================================================================

test "formatFloat fixed large number 1e49" {
    const allocator = std.testing.allocator;

    // This is the key test case that was failing
    // 1e49 as f64 is actually 9999999999999999464902769475481793196872414789632
    // NOT 10000000000000000000000000000000000000000000000000
    const result = try pyFormatDispatch(allocator, @as(f64, 1e49), .format, ".0f");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("9999999999999999464902769475481793196872414789632", result);
}

test "formatFloat negative zero" {
    const allocator = std.testing.allocator;

    const result = try pyFormatDispatch(allocator, @as(f64, -0.0), .format, ".0f");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("-0", result);
}

test "formatFloat banker's rounding" {
    const allocator = std.testing.allocator;

    // 2.5 rounds to 2 (round to even)
    const r1 = try pyFormatDispatch(allocator, @as(f64, 2.5), .format, ".0f");
    defer allocator.free(r1);
    try std.testing.expectEqualStrings("2", r1);

    // 3.5 rounds to 4 (round to even)
    const r2 = try pyFormatDispatch(allocator, @as(f64, 3.5), .format, ".0f");
    defer allocator.free(r2);
    try std.testing.expectEqualStrings("4", r2);
}

test "formatBool" {
    const allocator = std.testing.allocator;

    const t = try pyFormatDispatch(allocator, true, .str, null);
    defer allocator.free(t);
    try std.testing.expectEqualStrings("True", t);

    const f = try pyFormatDispatch(allocator, false, .str, null);
    defer allocator.free(f);
    try std.testing.expectEqualStrings("False", f);
}

test "formatStringRepr" {
    const allocator = std.testing.allocator;

    const result = try pyFormatDispatch(allocator, "hello", .repr, null);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("'hello'", result);
}
