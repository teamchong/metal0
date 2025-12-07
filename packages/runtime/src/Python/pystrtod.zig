/// pystrtod - Python String to Double
/// Mirrors cpython/Python/pystrtod.c
///
/// This module provides locale-independent string-to-float conversion:
/// - strtod replacement that always uses '.' as decimal separator
/// - dtoa replacement for float-to-string
/// - Special handling for inf, nan

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Constants
// ============================================================================

/// Positive infinity
pub const PY_INFINITY: f64 = std.math.inf(f64);

/// Not a number
pub const PY_NAN: f64 = std.math.nan(f64);

/// Maximum significant digits for precise representation
pub const MAX_SIGNIFICANT_DIGITS: usize = 17;

// ============================================================================
// String to Double
// ============================================================================

pub const ParseFloatError = error{
    InvalidCharacter,
    Overflow,
    Empty,
};

pub const ParseFloatResult = struct {
    value: f64,
    end_index: usize,
};

/// Parse string to double (locale-independent)
/// Always uses '.' as decimal separator
pub fn PyOS_string_to_double(str: []const u8) ParseFloatError!f64 {
    const result = try strtod(str);
    return result.value;
}

/// Parse string to double, returning end position
pub fn strtod(str: []const u8) ParseFloatError!ParseFloatResult {
    if (str.len == 0) {
        return ParseFloatError.Empty;
    }

    var idx: usize = 0;

    // Skip leading whitespace
    while (idx < str.len and isSpace(str[idx])) {
        idx += 1;
    }

    if (idx >= str.len) {
        return ParseFloatError.Empty;
    }

    // Check for sign
    var negative = false;
    if (str[idx] == '+') {
        idx += 1;
    } else if (str[idx] == '-') {
        negative = true;
        idx += 1;
    }

    // Check for special values
    if (idx + 3 <= str.len) {
        const s = str[idx..][0..3];
        if (asciiEql(s, "inf")) {
            idx += 3;
            // Check for "infinity"
            if (idx + 5 <= str.len and asciiEql(str[idx..][0..5], "inity")) {
                idx += 5;
            }
            return .{
                .value = if (negative) -PY_INFINITY else PY_INFINITY,
                .end_index = idx,
            };
        }
        if (asciiEql(s, "nan")) {
            idx += 3;
            return .{
                .value = PY_NAN,
                .end_index = idx,
            };
        }
    }

    // Parse number using Zig's parser
    const result = std.fmt.parseFloat(f64, str[idx..]) catch {
        return ParseFloatError.InvalidCharacter;
    };

    // Find end of parsed number
    var end = idx;
    // Skip digits and decimal point
    while (end < str.len) {
        const c = str[end];
        if (isDigit(c) or c == '.' or c == 'e' or c == 'E' or c == '+' or c == '-') {
            end += 1;
        } else {
            break;
        }
    }

    return .{
        .value = if (negative and result >= 0) -result else result,
        .end_index = end,
    };
}

// ============================================================================
// Double to String
// ============================================================================

/// Format mode for double-to-string
pub const FormatMode = enum {
    /// Shortest representation
    shortest,
    /// Fixed decimal places
    fixed,
    /// Exponential notation
    exponential,
    /// General (shortest of fixed or exponential)
    general,
};

/// Options for double-to-string conversion
pub const FormatOptions = struct {
    mode: FormatMode = .shortest,
    precision: u8 = 6,
    uppercase: bool = false,
    always_show_sign: bool = false,
    min_exponent: i32 = -4,
    max_exponent: i32 = 16,
};

/// Convert double to string
pub fn PyOS_double_to_string(
    allocator: Allocator,
    value: f64,
    options: FormatOptions,
) ![]u8 {
    var buf: [64]u8 = undefined;
    const len = try formatDouble(&buf, value, options);
    const result = try allocator.alloc(u8, len);
    @memcpy(result, buf[0..len]);
    return result;
}

/// Format double into buffer
pub fn formatDouble(buf: []u8, value: f64, options: FormatOptions) !usize {
    // Handle special cases
    if (std.math.isNan(value)) {
        const s = "nan";
        if (buf.len < 3) return error.BufferTooSmall;
        @memcpy(buf[0..3], s);
        return 3;
    }

    if (std.math.isInf(value)) {
        if (value < 0) {
            if (buf.len < 4) return error.BufferTooSmall;
            @memcpy(buf[0..4], "-inf");
            return 4;
        } else {
            if (options.always_show_sign) {
                if (buf.len < 4) return error.BufferTooSmall;
                @memcpy(buf[0..4], "+inf");
                return 4;
            } else {
                if (buf.len < 3) return error.BufferTooSmall;
                @memcpy(buf[0..3], "inf");
                return 3;
            }
        }
    }

    // Use Zig's formatting
    const result = switch (options.mode) {
        .shortest => std.fmt.bufPrint(buf, "{d}", .{value}),
        .fixed => std.fmt.bufPrint(buf, "{d:.6}", .{value}),
        .exponential => std.fmt.bufPrint(buf, "{e}", .{value}),
        .general => std.fmt.bufPrint(buf, "{d}", .{value}),
    };

    const formatted = result catch return error.BufferTooSmall;
    return formatted.len;
}

/// Format double with repr() style (Python's repr)
pub fn formatRepr(allocator: Allocator, value: f64) ![]u8 {
    return PyOS_double_to_string(allocator, value, .{ .mode = .shortest });
}

/// Format double with str() style (Python's str)
pub fn formatStr(allocator: Allocator, value: f64) ![]u8 {
    return PyOS_double_to_string(allocator, value, .{
        .mode = .general,
        .precision = 12,
    });
}

// ============================================================================
// Helper Functions
// ============================================================================

fn isSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '\x0b' or c == '\x0c';
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn asciiEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        const la = if (ca >= 'A' and ca <= 'Z') ca + 32 else ca;
        const lb = if (cb >= 'A' and cb <= 'Z') cb + 32 else cb;
        if (la != lb) return false;
    }
    return true;
}

// ============================================================================
// Python Compatibility
// ============================================================================

/// Check if value is finite (not inf or nan)
pub fn isFinite(value: f64) bool {
    return !std.math.isNan(value) and !std.math.isInf(value);
}

/// Check if value is positive or negative infinity
pub fn isInf(value: f64) bool {
    return std.math.isInf(value);
}

/// Check if value is positive infinity
pub fn isPosInf(value: f64) bool {
    return std.math.isPositiveInf(value);
}

/// Check if value is negative infinity
pub fn isNegInf(value: f64) bool {
    return std.math.isNegativeInf(value);
}

/// Check if value is NaN
pub fn isNan(value: f64) bool {
    return std.math.isNan(value);
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "parse simple float" {
    const r1 = try PyOS_string_to_double("3.14");
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), r1, 0.001);

    const r2 = try PyOS_string_to_double("-2.5");
    try std.testing.expectApproxEqAbs(@as(f64, -2.5), r2, 0.001);

    const r3 = try PyOS_string_to_double("1e10");
    try std.testing.expectApproxEqAbs(@as(f64, 1e10), r3, 1e5);
}

test "parse special values" {
    const inf = try PyOS_string_to_double("inf");
    try std.testing.expect(std.math.isPositiveInf(inf));

    const neg_inf = try PyOS_string_to_double("-inf");
    try std.testing.expect(std.math.isNegativeInf(neg_inf));

    const infinity = try PyOS_string_to_double("infinity");
    try std.testing.expect(std.math.isPositiveInf(infinity));

    const nan = try PyOS_string_to_double("nan");
    try std.testing.expect(std.math.isNan(nan));
}

test "parse with whitespace" {
    const r = try PyOS_string_to_double("  3.14  ");
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), r, 0.001);
}

test "format double" {
    var buf: [64]u8 = undefined;

    const len1 = try formatDouble(&buf, 3.14, .{});
    try std.testing.expect(len1 > 0);

    const len2 = try formatDouble(&buf, PY_INFINITY, .{});
    try std.testing.expectEqualStrings("inf", buf[0..len2]);

    const len3 = try formatDouble(&buf, -PY_INFINITY, .{});
    try std.testing.expectEqualStrings("-inf", buf[0..len3]);

    const len4 = try formatDouble(&buf, PY_NAN, .{});
    try std.testing.expectEqualStrings("nan", buf[0..len4]);
}

test "isFinite" {
    try std.testing.expect(isFinite(1.0));
    try std.testing.expect(isFinite(-1.0));
    try std.testing.expect(isFinite(0.0));
    try std.testing.expect(!isFinite(PY_INFINITY));
    try std.testing.expect(!isFinite(-PY_INFINITY));
    try std.testing.expect(!isFinite(PY_NAN));
}
