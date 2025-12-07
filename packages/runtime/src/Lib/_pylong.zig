/// _pylong - Python Long Integer Implementation Details
/// Mirrors cpython/Lib/_pylong.py
///
/// Pure Zig implementation of Python's arbitrary precision integer
/// internal operations. Provides fast algorithms for conversion
/// between bases, string formatting, and arithmetic.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Constants
// ============================================================================

/// Digit base (2^30 for 64-bit, 2^15 for 32-bit)
pub const DIGIT_BITS: u6 = 30;
pub const DIGIT_BASE: u64 = 1 << DIGIT_BITS;
pub const DIGIT_MASK: u64 = DIGIT_BASE - 1;

/// Maximum decimal digits per digit
pub const DECIMAL_DIGITS_PER_DIGIT: usize = 9;

/// Powers of 10
pub const POWERS_OF_10 = blk: {
    var powers: [20]u64 = undefined;
    powers[0] = 1;
    for (1..20) |i| {
        powers[i] = powers[i - 1] * 10;
    }
    break :blk powers;
};

// ============================================================================
// Digit Array Operations
// ============================================================================

/// Add two digit arrays, return carry
pub fn addDigitArrays(
    a: []const u64,
    b: []const u64,
    result: []u64,
) u64 {
    var carry: u64 = 0;
    const min_len = @min(a.len, b.len);
    const max_len = @max(a.len, b.len);

    // Add overlapping parts
    for (0..min_len) |i| {
        const sum = a[i] + b[i] + carry;
        result[i] = sum & DIGIT_MASK;
        carry = sum >> DIGIT_BITS;
    }

    // Copy remaining part with carry
    const longer = if (a.len > b.len) a else b;
    for (min_len..max_len) |i| {
        const sum = longer[i] + carry;
        result[i] = sum & DIGIT_MASK;
        carry = sum >> DIGIT_BITS;
    }

    return carry;
}

/// Subtract b from a (a >= b), return borrow (should be 0)
pub fn subDigitArrays(
    a: []const u64,
    b: []const u64,
    result: []u64,
) u64 {
    var borrow: u64 = 0;

    for (0..b.len) |i| {
        const a_digit = if (i < a.len) a[i] else 0;
        const diff = a_digit -% b[i] -% borrow;
        if (a_digit < b[i] + borrow) {
            result[i] = diff + DIGIT_BASE;
            borrow = 1;
        } else {
            result[i] = diff;
            borrow = 0;
        }
    }

    // Copy remaining with borrow
    for (b.len..a.len) |i| {
        const diff = a[i] -% borrow;
        if (a[i] < borrow) {
            result[i] = diff + DIGIT_BASE;
            borrow = 1;
        } else {
            result[i] = diff;
            borrow = 0;
        }
    }

    return borrow;
}

/// Multiply digit array by single digit
pub fn mulDigitArrayByDigit(
    a: []const u64,
    b: u64,
    result: []u64,
) u64 {
    var carry: u64 = 0;

    for (0..a.len) |i| {
        const prod = a[i] * b + carry;
        result[i] = prod & DIGIT_MASK;
        carry = prod >> DIGIT_BITS;
    }

    return carry;
}

/// Divide digit array by single digit, return remainder
pub fn divDigitArrayByDigit(
    a: []const u64,
    b: u64,
    result: []u64,
) u64 {
    var remainder: u64 = 0;

    // Process from most significant
    var i: usize = a.len;
    while (i > 0) {
        i -= 1;
        const dividend = (remainder << DIGIT_BITS) | a[i];
        result[i] = dividend / b;
        remainder = dividend % b;
    }

    return remainder;
}

// ============================================================================
// Base Conversion
// ============================================================================

/// Convert decimal string to digit array
pub fn decimalToDigits(allocator: Allocator, decimal: []const u8) !std.ArrayList(u64) {
    var digits = std.ArrayList(u64).init(allocator);

    // Skip leading sign
    var start: usize = 0;
    if (decimal.len > 0 and (decimal[0] == '+' or decimal[0] == '-')) {
        start = 1;
    }

    // Skip leading zeros
    while (start < decimal.len and decimal[start] == '0') {
        start += 1;
    }

    if (start >= decimal.len) {
        try digits.append(0);
        return digits;
    }

    // Process decimal digits
    try digits.append(0);

    for (decimal[start..]) |c| {
        if (c < '0' or c > '9') continue; // Skip non-digits

        const d: u64 = c - '0';

        // Multiply by 10 and add digit
        var carry = mulDigitArrayByDigit(digits.items, 10, digits.items);
        const sum = digits.items[0] + d;
        digits.items[0] = sum & DIGIT_MASK;
        carry += sum >> DIGIT_BITS;

        // Propagate carry
        for (1..digits.items.len) |i| {
            const new_sum = digits.items[i] + carry;
            digits.items[i] = new_sum & DIGIT_MASK;
            carry = new_sum >> DIGIT_BITS;
        }

        // Add new digit if needed
        if (carry > 0) {
            try digits.append(carry);
        }
    }

    return digits;
}

/// Convert digit array to decimal string
pub fn digitsToDecimal(allocator: Allocator, digits: []const u64) ![]u8 {
    if (digits.len == 0 or (digits.len == 1 and digits[0] == 0)) {
        return try allocator.dupe(u8, "0");
    }

    // Make a copy to modify
    var work = try allocator.alloc(u64, digits.len);
    defer allocator.free(work);
    @memcpy(work, digits);

    var result = std.ArrayList(u8).init(allocator);

    // Extract decimal digits by repeated division
    while (true) {
        // Check if all zeros
        var all_zero = true;
        for (work) |d| {
            if (d != 0) {
                all_zero = false;
                break;
            }
        }
        if (all_zero) break;

        // Divide by 10^9 to get 9 decimal digits at once
        const remainder = divDigitArrayByDigit(work, POWERS_OF_10[9], work);

        // Convert remainder to decimal digits
        var r = remainder;
        for (0..9) |_| {
            try result.append(@intCast((r % 10) + '0'));
            r /= 10;
        }
    }

    // Remove trailing zeros (which are leading zeros in reversed string)
    while (result.items.len > 1 and result.items[result.items.len - 1] == '0') {
        _ = result.pop();
    }

    // Reverse
    std.mem.reverse(u8, result.items);

    return result.toOwnedSlice();
}

/// Convert to hex string
pub fn digitsToHex(allocator: Allocator, digits: []const u64, uppercase: bool) ![]u8 {
    if (digits.len == 0 or (digits.len == 1 and digits[0] == 0)) {
        return try allocator.dupe(u8, "0");
    }

    var result = std.ArrayList(u8).init(allocator);
    const hex_chars = if (uppercase) "0123456789ABCDEF" else "0123456789abcdef";

    // Process from most significant digit
    var started = false;
    var i: usize = digits.len;
    while (i > 0) {
        i -= 1;
        const digit = digits[i];

        // Each digit contributes 8 hex chars (30 bits / 4 = 7.5, round up)
        for (0..8) |j| {
            const nibble = (digit >> @intCast((7 - j) * 4)) & 0xF;
            if (nibble != 0 or started or (i == 0 and j == 7)) {
                try result.append(hex_chars[@intCast(nibble)]);
                started = true;
            }
        }
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Comparison
// ============================================================================

/// Compare two digit arrays
pub fn compareDigitArrays(a: []const u64, b: []const u64) i2 {
    // Find effective lengths
    var a_len = a.len;
    while (a_len > 0 and a[a_len - 1] == 0) a_len -= 1;

    var b_len = b.len;
    while (b_len > 0 and b[b_len - 1] == 0) b_len -= 1;

    if (a_len != b_len) {
        return if (a_len > b_len) 1 else -1;
    }

    // Compare digit by digit from most significant
    var i: usize = a_len;
    while (i > 0) {
        i -= 1;
        if (a[i] != b[i]) {
            return if (a[i] > b[i]) 1 else -1;
        }
    }

    return 0;
}

// ============================================================================
// Bit Operations
// ============================================================================

/// Count leading zeros in digit array
pub fn countLeadingZeros(digits: []const u64) usize {
    if (digits.len == 0) return 0;

    // Find most significant non-zero digit
    var i: usize = digits.len;
    while (i > 0 and digits[i - 1] == 0) {
        i -= 1;
    }

    if (i == 0) return digits.len * DIGIT_BITS;

    // Count leading zeros in that digit
    const msb = digits[i - 1];
    const zeros_in_digit = @clz(msb) - (64 - DIGIT_BITS);
    const unused_digits = digits.len - i;

    return unused_digits * DIGIT_BITS + zeros_in_digit;
}

/// Get bit length of digit array
pub fn bitLength(digits: []const u64) usize {
    if (digits.len == 0) return 0;

    // Find most significant non-zero digit
    var i: usize = digits.len;
    while (i > 0 and digits[i - 1] == 0) {
        i -= 1;
    }

    if (i == 0) return 0;

    // Bit length = (i-1) * DIGIT_BITS + bits in msb
    const msb = digits[i - 1];
    const bits_in_msb = DIGIT_BITS - @as(usize, @clz(msb)) + (64 - DIGIT_BITS);

    return (i - 1) * DIGIT_BITS + bits_in_msb;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the _pylong module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "digit constants" {
    try std.testing.expectEqual(@as(u6, 30), DIGIT_BITS);
    try std.testing.expectEqual(@as(u64, 1 << 30), DIGIT_BASE);
}

test "powers of 10" {
    try std.testing.expectEqual(@as(u64, 1), POWERS_OF_10[0]);
    try std.testing.expectEqual(@as(u64, 10), POWERS_OF_10[1]);
    try std.testing.expectEqual(@as(u64, 100), POWERS_OF_10[2]);
    try std.testing.expectEqual(@as(u64, 1_000_000_000), POWERS_OF_10[9]);
}

test "add digit arrays" {
    var a = [_]u64{100};
    var b = [_]u64{200};
    var result = [_]u64{0};

    const carry = addDigitArrays(&a, &b, &result);
    try std.testing.expectEqual(@as(u64, 300), result[0]);
    try std.testing.expectEqual(@as(u64, 0), carry);
}

test "mul digit array by digit" {
    var a = [_]u64{1000};
    var result = [_]u64{0};

    const carry = mulDigitArrayByDigit(&a, 5, &result);
    try std.testing.expectEqual(@as(u64, 5000), result[0]);
    try std.testing.expectEqual(@as(u64, 0), carry);
}

test "div digit array by digit" {
    var a = [_]u64{100};
    var result = [_]u64{0};

    const remainder = divDigitArrayByDigit(&a, 7, &result);
    try std.testing.expectEqual(@as(u64, 14), result[0]);
    try std.testing.expectEqual(@as(u64, 2), remainder);
}

test "compare digit arrays" {
    const a = [_]u64{100};
    const b = [_]u64{200};
    const c = [_]u64{100};

    try std.testing.expectEqual(@as(i2, -1), compareDigitArrays(&a, &b));
    try std.testing.expectEqual(@as(i2, 1), compareDigitArrays(&b, &a));
    try std.testing.expectEqual(@as(i2, 0), compareDigitArrays(&a, &c));
}

test "decimal to digits" {
    const allocator = std.testing.allocator;
    var digits = try decimalToDigits(allocator, "12345");
    defer digits.deinit();

    try std.testing.expectEqual(@as(u64, 12345), digits.items[0]);
}

test "digits to decimal" {
    const allocator = std.testing.allocator;
    const digits = [_]u64{12345};
    const decimal = try digitsToDecimal(allocator, &digits);
    defer allocator.free(decimal);

    try std.testing.expectEqualStrings("12345", decimal);
}

test "bit length" {
    const a = [_]u64{0b1111}; // 4 bits
    try std.testing.expectEqual(@as(usize, 4), bitLength(&a));

    const b = [_]u64{0}; // 0 bits
    try std.testing.expectEqual(@as(usize, 0), bitLength(&b));

    const c = [_]u64{1}; // 1 bit
    try std.testing.expectEqual(@as(usize, 1), bitLength(&c));
}
