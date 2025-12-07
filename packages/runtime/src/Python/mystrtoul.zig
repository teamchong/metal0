/// mystrtoul - String to Unsigned Long Conversion
/// Mirrors cpython/Python/mystrtoul.c
///
/// This module provides locale-independent string to integer conversion:
/// - PyOS_strtoul: convert string to unsigned long
/// - PyOS_strtol: convert string to signed long
/// - Support for bases 2-36 with auto-detection

const std = @import("std");
const pyctype = @import("pyctype.zig");

// ============================================================================
// Constants
// ============================================================================

/// Maximum values for overflow checking
pub const ULONG_MAX: u64 = std.math.maxInt(u64);
pub const LONG_MAX: i64 = std.math.maxInt(i64);
pub const LONG_MIN: i64 = std.math.minInt(i64);

/// Maximum values for each base (ULONG_MAX / base)
const smallmax: [37]u64 = init: {
    var table: [37]u64 = undefined;
    table[0] = 0;
    table[1] = 0;
    for (2..37) |base| {
        table[base] = ULONG_MAX / base;
    }
    break :init table;
};

/// Maximum safe digits for 64-bit integers
/// Calculated as floor(log_base(2^64))
const digitlimit: [37]usize = .{
    0, 0, // bases 0, 1 invalid
    64, 40, 32, 27, 24, 22, 21, 20, // bases 2-9
    19, 18, 17, 17, 16, 16, 16, 15, 15, 15, // bases 10-19
    14, 14, 14, 14, 13, 13, 13, 13, 13, 13, // bases 20-29
    13, 12, 12, 12, 12, 12, 12, // bases 30-36
};

// ============================================================================
// Errors
// ============================================================================

pub const ParseError = error{
    Overflow,
    InvalidBase,
    InvalidCharacter,
    EmptyString,
};

// ============================================================================
// Result Types
// ============================================================================

pub const StrtoResult = struct {
    value: u64,
    end_index: usize,
    overflow: bool = false,
};

pub const StrtolResult = struct {
    value: i64,
    end_index: usize,
    overflow: bool = false,
};

// ============================================================================
// Main Functions
// ============================================================================

/// Convert string to unsigned long
/// Supports bases 2-36, with auto-detection when base=0
pub fn strtoul(str: []const u8, base_arg: i32) StrtoResult {
    var idx: usize = 0;
    var base: u32 = @intCast(@max(0, base_arg));

    // Skip leading whitespace
    while (idx < str.len and pyctype.isSpace(str[idx])) {
        idx += 1;
    }

    if (idx >= str.len) {
        return .{ .value = 0, .end_index = idx };
    }

    // Handle base auto-detection and prefix skipping
    if (base == 0) {
        if (str[idx] == '0' and idx + 1 < str.len) {
            const next = str[idx + 1];
            if (next == 'x' or next == 'X') {
                // Check for valid hex digit after 0x
                if (idx + 2 < str.len and pyctype.digit_value[str[idx + 2]] < 16) {
                    idx += 2;
                    base = 16;
                } else {
                    return .{ .value = 0, .end_index = idx + 1 };
                }
            } else if (next == 'o' or next == 'O') {
                if (idx + 2 < str.len and pyctype.digit_value[str[idx + 2]] < 8) {
                    idx += 2;
                    base = 8;
                } else {
                    return .{ .value = 0, .end_index = idx + 1 };
                }
            } else if (next == 'b' or next == 'B') {
                if (idx + 2 < str.len and pyctype.digit_value[str[idx + 2]] < 2) {
                    idx += 2;
                    base = 2;
                } else {
                    return .{ .value = 0, .end_index = idx + 1 };
                }
            } else {
                // Skip leading zeros
                while (idx < str.len and str[idx] == '0') {
                    idx += 1;
                }
                // Skip whitespace after zeros
                while (idx < str.len and pyctype.isSpace(str[idx])) {
                    idx += 1;
                }
                return .{ .value = 0, .end_index = idx };
            }
        } else {
            base = 10;
        }
    } else {
        // Even with explicit base, skip prefix if present
        if (str[idx] == '0' and idx + 1 < str.len) {
            const next = str[idx + 1];
            if (base == 16 and (next == 'x' or next == 'X')) {
                if (idx + 2 < str.len and pyctype.digit_value[str[idx + 2]] < 16) {
                    idx += 2;
                }
            } else if (base == 8 and (next == 'o' or next == 'O')) {
                if (idx + 2 < str.len and pyctype.digit_value[str[idx + 2]] < 8) {
                    idx += 2;
                }
            } else if (base == 2 and (next == 'b' or next == 'B')) {
                if (idx + 2 < str.len and pyctype.digit_value[str[idx + 2]] < 2) {
                    idx += 2;
                }
            }
        }
    }

    // Validate base
    if (base < 2 or base > 36) {
        return .{ .value = 0, .end_index = idx };
    }

    // Skip leading zeros
    while (idx < str.len and str[idx] == '0') {
        idx += 1;
    }

    // Convert digits
    var result: u64 = 0;
    var ovlimit: i32 = @intCast(digitlimit[base]);
    var overflow = false;

    while (idx < str.len) {
        const digit = pyctype.digit_value[str[idx]];
        if (digit >= base) {
            break;
        }

        if (ovlimit > 0) {
            // No overflow check needed
            result = result * base + digit;
        } else if (ovlimit < 0) {
            // Guaranteed overflow
            overflow = true;
        } else {
            // Check for overflow
            if (result > smallmax[base]) {
                overflow = true;
            } else {
                const new_result = result * base;
                if (new_result > ULONG_MAX - digit) {
                    overflow = true;
                } else {
                    result = new_result + digit;
                }
            }
        }

        idx += 1;
        ovlimit -= 1;
    }

    if (overflow) {
        // Skip remaining digits
        while (idx < str.len and pyctype.digit_value[str[idx]] < base) {
            idx += 1;
        }
        return .{ .value = ULONG_MAX, .end_index = idx, .overflow = true };
    }

    return .{ .value = result, .end_index = idx };
}

/// Convert string to signed long
pub fn strtol(str: []const u8, base: i32) StrtolResult {
    var idx: usize = 0;

    // Skip leading whitespace
    while (idx < str.len and pyctype.isSpace(str[idx])) {
        idx += 1;
    }

    if (idx >= str.len) {
        return .{ .value = 0, .end_index = idx };
    }

    // Check for sign
    var negative = false;
    if (str[idx] == '+') {
        idx += 1;
    } else if (str[idx] == '-') {
        negative = true;
        idx += 1;
    }

    // Parse unsigned value
    const uresult = strtoul(str[idx..], base);

    const abs_long_min: u64 = @intCast(-@as(i128, LONG_MIN));

    if (uresult.overflow) {
        return .{
            .value = if (negative) LONG_MIN else LONG_MAX,
            .end_index = idx + uresult.end_index,
            .overflow = true,
        };
    }

    var result: i64 = undefined;
    var overflow = false;

    if (uresult.value <= @as(u64, @intCast(LONG_MAX))) {
        result = @intCast(uresult.value);
        if (negative) {
            result = -result;
        }
    } else if (negative and uresult.value == abs_long_min) {
        result = LONG_MIN;
    } else {
        overflow = true;
        result = if (negative) LONG_MIN else LONG_MAX;
    }

    return .{
        .value = result,
        .end_index = idx + uresult.end_index,
        .overflow = overflow,
    };
}

// ============================================================================
// Convenience Functions
// ============================================================================

/// Parse string as integer with auto base detection
pub fn parseInt(str: []const u8) !i64 {
    const result = strtol(str, 0);
    if (result.overflow) {
        return error.Overflow;
    }
    if (result.end_index == 0) {
        return error.InvalidCharacter;
    }
    return result.value;
}

/// Parse string as unsigned integer with auto base detection
pub fn parseUint(str: []const u8) !u64 {
    const result = strtoul(str, 0);
    if (result.overflow) {
        return error.Overflow;
    }
    if (result.end_index == 0) {
        return error.InvalidCharacter;
    }
    return result.value;
}

/// Parse hex string (without 0x prefix)
pub fn parseHex(str: []const u8) !u64 {
    const result = strtoul(str, 16);
    if (result.overflow) {
        return error.Overflow;
    }
    if (result.end_index == 0) {
        return error.InvalidCharacter;
    }
    return result.value;
}

/// Parse octal string (without 0o prefix)
pub fn parseOctal(str: []const u8) !u64 {
    const result = strtoul(str, 8);
    if (result.overflow) {
        return error.Overflow;
    }
    if (result.end_index == 0) {
        return error.InvalidCharacter;
    }
    return result.value;
}

/// Parse binary string (without 0b prefix)
pub fn parseBinary(str: []const u8) !u64 {
    const result = strtoul(str, 2);
    if (result.overflow) {
        return error.Overflow;
    }
    if (result.end_index == 0) {
        return error.InvalidCharacter;
    }
    return result.value;
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "strtoul decimal" {
    const r1 = strtoul("123", 10);
    try std.testing.expectEqual(@as(u64, 123), r1.value);
    try std.testing.expectEqual(@as(usize, 3), r1.end_index);
    try std.testing.expect(!r1.overflow);
}

test "strtoul hex" {
    const r1 = strtoul("0xff", 0);
    try std.testing.expectEqual(@as(u64, 255), r1.value);

    const r2 = strtoul("FF", 16);
    try std.testing.expectEqual(@as(u64, 255), r2.value);
}

test "strtoul octal" {
    const r1 = strtoul("0o77", 0);
    try std.testing.expectEqual(@as(u64, 63), r1.value);

    const r2 = strtoul("77", 8);
    try std.testing.expectEqual(@as(u64, 63), r2.value);
}

test "strtoul binary" {
    const r1 = strtoul("0b1010", 0);
    try std.testing.expectEqual(@as(u64, 10), r1.value);

    const r2 = strtoul("1010", 2);
    try std.testing.expectEqual(@as(u64, 10), r2.value);
}

test "strtoul leading zeros" {
    const r1 = strtoul("  0000123", 10);
    try std.testing.expectEqual(@as(u64, 123), r1.value);
}

test "strtol signed" {
    const r1 = strtol("-123", 10);
    try std.testing.expectEqual(@as(i64, -123), r1.value);
    try std.testing.expect(!r1.overflow);

    const r2 = strtol("+456", 10);
    try std.testing.expectEqual(@as(i64, 456), r2.value);
}

test "strtoul base 36" {
    const r1 = strtoul("z", 36);
    try std.testing.expectEqual(@as(u64, 35), r1.value);

    const r2 = strtoul("10", 36);
    try std.testing.expectEqual(@as(u64, 36), r2.value);
}

test "parseInt auto" {
    try std.testing.expectEqual(@as(i64, 255), try parseInt("0xff"));
    try std.testing.expectEqual(@as(i64, 63), try parseInt("0o77"));
    try std.testing.expectEqual(@as(i64, 10), try parseInt("0b1010"));
    try std.testing.expectEqual(@as(i64, 123), try parseInt("123"));
    try std.testing.expectEqual(@as(i64, -42), try parseInt("-42"));
}
