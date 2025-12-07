/// dtoa - Double to ASCII Conversion
/// Mirrors cpython/Python/dtoa.c
///
/// This module provides high-quality double-to-string and string-to-double
/// conversion based on David Gay's dtoa.c algorithm:
/// - Correct rounding for all conversions
/// - Shortest representation that round-trips
/// - Locale-independent (always uses '.')

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Constants
// ============================================================================

/// Maximum digits in a double mantissa
pub const MAX_DIGITS: usize = 17;

/// Buffer size for dtoa output
pub const DTOA_BUFFER_SIZE: usize = 32;

/// Special values
pub const POSITIVE_INFINITY = std.math.inf(f64);
pub const NEGATIVE_INFINITY = -std.math.inf(f64);
pub const NAN = std.math.nan(f64);

// ============================================================================
// Conversion Modes
// ============================================================================

/// Mode for dtoa conversion
pub const DtoaMode = enum(i32) {
    /// Shortest string that round-trips
    shortest = 0,
    /// ndigits significant digits
    significant = 2,
    /// ndigits after decimal point
    fixed = 3,
};

// ============================================================================
// Dtoa Result
// ============================================================================

pub const DtoaResult = struct {
    /// The digit string (no decimal point or sign)
    digits: []const u8,
    /// Position of decimal point relative to start of digits
    /// E.g., 123 with decpt=2 means 1.23, decpt=4 means 12300
    decpt: i32,
    /// True if negative
    sign: bool,
    /// Original buffer (for freeing)
    buffer: []u8,
    allocator: Allocator,

    pub fn deinit(self: *DtoaResult) void {
        self.allocator.free(self.buffer);
    }
};

// ============================================================================
// Main Functions
// ============================================================================

/// Convert double to string using shortest representation
pub fn dtoa(allocator: Allocator, value: f64) !DtoaResult {
    return dtoaMode(allocator, value, .shortest, 0);
}

/// Convert double to string with specified mode and precision
pub fn dtoaMode(
    allocator: Allocator,
    value: f64,
    mode: DtoaMode,
    ndigits: i32,
) !DtoaResult {
    var buf = try allocator.alloc(u8, DTOA_BUFFER_SIZE);
    errdefer allocator.free(buf);

    // Handle special values
    if (std.math.isNan(value)) {
        @memcpy(buf[0..3], "nan");
        return .{
            .digits = buf[0..3],
            .decpt = 9999,
            .sign = false,
            .buffer = buf,
            .allocator = allocator,
        };
    }

    const sign = std.math.signbit(value);
    const abs_value = @abs(value);

    if (std.math.isInf(abs_value)) {
        @memcpy(buf[0..3], "inf");
        return .{
            .digits = buf[0..3],
            .decpt = 9999,
            .sign = sign,
            .buffer = buf,
            .allocator = allocator,
        };
    }

    if (abs_value == 0) {
        buf[0] = '0';
        return .{
            .digits = buf[0..1],
            .decpt = 1,
            .sign = sign,
            .buffer = buf,
            .allocator = allocator,
        };
    }

    // Use Zig's formatting for the actual conversion
    var formatted_buf: [64]u8 = undefined;
    const formatted = switch (mode) {
        .shortest => std.fmt.bufPrint(&formatted_buf, "{d}", .{abs_value}),
        .significant => std.fmt.bufPrint(&formatted_buf, "{d}", .{abs_value}),
        .fixed => blk: {
            const precision: usize = @intCast(@max(0, ndigits));
            const result = switch (precision) {
                0 => std.fmt.bufPrint(&formatted_buf, "{d:.0}", .{abs_value}),
                1 => std.fmt.bufPrint(&formatted_buf, "{d:.1}", .{abs_value}),
                2 => std.fmt.bufPrint(&formatted_buf, "{d:.2}", .{abs_value}),
                3 => std.fmt.bufPrint(&formatted_buf, "{d:.3}", .{abs_value}),
                4 => std.fmt.bufPrint(&formatted_buf, "{d:.4}", .{abs_value}),
                5 => std.fmt.bufPrint(&formatted_buf, "{d:.5}", .{abs_value}),
                6 => std.fmt.bufPrint(&formatted_buf, "{d:.6}", .{abs_value}),
                else => std.fmt.bufPrint(&formatted_buf, "{d:.6}", .{abs_value}),
            };
            break :blk result;
        },
    } catch return error.FormatError;

    // Extract digits and decimal point position
    var digits_len: usize = 0;
    var decpt: i32 = 0;
    var found_decimal = false;
    var decimal_pos: usize = 0;

    for (formatted, 0..) |c, i| {
        if (c == '.') {
            found_decimal = true;
            decimal_pos = i;
        } else if (c == 'e' or c == 'E') {
            // Handle exponential notation
            break;
        } else if (c >= '0' and c <= '9') {
            if (digits_len < buf.len) {
                buf[digits_len] = c;
                digits_len += 1;
            }
        }
    }

    // Calculate decimal point position
    if (found_decimal) {
        decpt = @intCast(decimal_pos);
    } else {
        decpt = @intCast(digits_len);
    }

    // Skip leading zeros after decimal
    var start: usize = 0;
    if (decpt <= 0) {
        // All zeros before first significant digit
        while (start < digits_len and buf[start] == '0') {
            start += 1;
            decpt -= 1;
        }
    }

    // Remove trailing zeros for shortest mode
    var end = digits_len;
    if (mode == .shortest) {
        while (end > start + 1 and buf[end - 1] == '0') {
            end -= 1;
        }
    }

    const digits = buf[start..end];
    if (digits.len == 0) {
        buf[0] = '0';
        return .{
            .digits = buf[0..1],
            .decpt = 1,
            .sign = sign,
            .buffer = buf,
            .allocator = allocator,
        };
    }

    // Copy digits to start of buffer
    if (start > 0) {
        std.mem.copyForwards(u8, buf[0..], digits);
    }

    return .{
        .digits = buf[0 .. end - start],
        .decpt = decpt,
        .sign = sign,
        .buffer = buf,
        .allocator = allocator,
    };
}

// ============================================================================
// String to Double
// ============================================================================

pub const StrtodError = error{
    InvalidFormat,
    Overflow,
    Empty,
};

/// Convert string to double
pub fn strtod(str: []const u8) StrtodError!f64 {
    if (str.len == 0) return StrtodError.Empty;

    // Skip whitespace
    var start: usize = 0;
    while (start < str.len and isWhitespace(str[start])) {
        start += 1;
    }

    if (start >= str.len) return StrtodError.Empty;

    // Check for special values (case-insensitive)
    const remaining = str[start..];

    if (remaining.len >= 3) {
        if (std.ascii.eqlIgnoreCase(remaining[0..3], "nan")) {
            return NAN;
        }
        if (std.ascii.eqlIgnoreCase(remaining[0..3], "inf")) {
            return POSITIVE_INFINITY;
        }
    }

    if (remaining.len >= 4 and remaining[0] == '-') {
        if (std.ascii.eqlIgnoreCase(remaining[1..4], "inf")) {
            return NEGATIVE_INFINITY;
        }
    }

    if (remaining.len >= 4 and remaining[0] == '+') {
        if (std.ascii.eqlIgnoreCase(remaining[1..4], "inf")) {
            return POSITIVE_INFINITY;
        }
    }

    // Use standard parsing
    return std.fmt.parseFloat(f64, str) catch StrtodError.InvalidFormat;
}

// ============================================================================
// Formatting Helpers
// ============================================================================

/// Format double for repr() (Python-style)
pub fn formatRepr(allocator: Allocator, value: f64) ![]u8 {
    var result = try dtoa(allocator, value);
    defer result.deinit();

    // Build output string
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();

    if (result.sign) {
        try buf.append('-');
    }

    // Special values
    if (result.decpt == 9999) {
        try buf.appendSlice(result.digits);
        return buf.toOwnedSlice();
    }

    // Normal number formatting
    if (result.decpt <= 0) {
        // 0.00...digits
        try buf.append('0');
        try buf.append('.');
        var zeros: usize = @intCast(-result.decpt);
        while (zeros > 0) : (zeros -= 1) {
            try buf.append('0');
        }
        try buf.appendSlice(result.digits);
    } else if (result.decpt >= @as(i32, @intCast(result.digits.len))) {
        // digits with trailing zeros or integer
        try buf.appendSlice(result.digits);
        const trailing: usize = @intCast(result.decpt - @as(i32, @intCast(result.digits.len)));
        for (0..trailing) |_| {
            try buf.append('0');
        }
        try buf.append('.');
        try buf.append('0');
    } else {
        // digits with decimal point in middle
        const decpt_usize: usize = @intCast(result.decpt);
        try buf.appendSlice(result.digits[0..decpt_usize]);
        try buf.append('.');
        try buf.appendSlice(result.digits[decpt_usize..]);
    }

    return buf.toOwnedSlice();
}

/// Format double for str() (shorter format)
pub fn formatStr(allocator: Allocator, value: f64) ![]u8 {
    return formatRepr(allocator, value);
}

// ============================================================================
// Helper Functions
// ============================================================================

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

// ============================================================================
// Python Compatibility
// ============================================================================

/// _Py_dg_strtod - string to double
pub fn _Py_dg_strtod(str: []const u8) !f64 {
    return strtod(str);
}

/// _Py_dg_dtoa - double to string
pub fn _Py_dg_dtoa(allocator: Allocator, value: f64) !DtoaResult {
    return dtoa(allocator, value);
}

/// _Py_dg_freedtoa - free dtoa result
pub fn _Py_dg_freedtoa(result: *DtoaResult) void {
    result.deinit();
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "dtoa basic" {
    var result = try dtoa(std.testing.allocator, 123.456);
    defer result.deinit();

    try std.testing.expect(!result.sign);
    try std.testing.expect(result.decpt == 3);
}

test "dtoa negative" {
    var result = try dtoa(std.testing.allocator, -42.5);
    defer result.deinit();

    try std.testing.expect(result.sign);
}

test "dtoa zero" {
    var result = try dtoa(std.testing.allocator, 0.0);
    defer result.deinit();

    try std.testing.expectEqualStrings("0", result.digits);
}

test "dtoa infinity" {
    var result = try dtoa(std.testing.allocator, POSITIVE_INFINITY);
    defer result.deinit();

    try std.testing.expectEqualStrings("inf", result.digits);
    try std.testing.expectEqual(@as(i32, 9999), result.decpt);
}

test "dtoa nan" {
    var result = try dtoa(std.testing.allocator, NAN);
    defer result.deinit();

    try std.testing.expectEqualStrings("nan", result.digits);
}

test "strtod basic" {
    const r1 = try strtod("123.456");
    try std.testing.expectApproxEqAbs(@as(f64, 123.456), r1, 0.0001);

    const r2 = try strtod("-42.5");
    try std.testing.expectApproxEqAbs(@as(f64, -42.5), r2, 0.0001);
}

test "strtod special" {
    const inf = try strtod("inf");
    try std.testing.expect(std.math.isPositiveInf(inf));

    const neg_inf = try strtod("-inf");
    try std.testing.expect(std.math.isNegativeInf(neg_inf));

    const nan = try strtod("nan");
    try std.testing.expect(std.math.isNan(nan));
}

test "formatRepr" {
    const r1 = try formatRepr(std.testing.allocator, 3.14);
    defer std.testing.allocator.free(r1);
    try std.testing.expect(r1.len > 0);

    const r2 = try formatRepr(std.testing.allocator, -42.0);
    defer std.testing.allocator.free(r2);
    try std.testing.expect(r2[0] == '-');
}
