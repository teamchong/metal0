//! test.test_ctypes.test_libc - Tests for libc integration
//! Reference: cpython/Lib/test/test_ctypes/test_libc.py
//!
//! Tests for loading and calling libc functions through ctypes
//! including common functions and platform-specific behavior.

const std = @import("std");
const builtin = @import("builtin");
const _support = @import("_support.zig");

// ============================================================================
// LibC Wrapper
// ============================================================================

/// Mock libc wrapper for testing
pub const LibC = struct {
    const Self = @This();

    loaded: bool = false,

    pub fn init() Self {
        return .{ .loaded = true };
    }

    /// strlen - string length
    pub fn strlen(s: [*:0]const u8) usize {
        var len: usize = 0;
        while (s[len] != 0) : (len += 1) {}
        return len;
    }

    /// strcmp - string compare
    pub fn strcmp(s1: [*:0]const u8, s2: [*:0]const u8) i32 {
        var i: usize = 0;
        while (s1[i] != 0 and s2[i] != 0) : (i += 1) {
            if (s1[i] < s2[i]) return -1;
            if (s1[i] > s2[i]) return 1;
        }
        if (s1[i] != 0) return 1;
        if (s2[i] != 0) return -1;
        return 0;
    }

    /// abs - absolute value
    pub fn abs(n: i32) i32 {
        return if (n < 0) -n else n;
    }

    /// toupper - convert to uppercase
    pub fn toupper(c: i32) i32 {
        if (c >= 'a' and c <= 'z') {
            return c - ('a' - 'A');
        }
        return c;
    }

    /// tolower - convert to lowercase
    pub fn tolower(c: i32) i32 {
        if (c >= 'A' and c <= 'Z') {
            return c + ('a' - 'A');
        }
        return c;
    }

    /// isdigit - check if digit
    pub fn isdigit(c: i32) i32 {
        return if (c >= '0' and c <= '9') 1 else 0;
    }

    /// isalpha - check if alphabetic
    pub fn isalpha(c: i32) i32 {
        return if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')) 1 else 0;
    }

    /// atoi - string to integer
    pub fn atoi(s: [*:0]const u8) i32 {
        var result: i32 = 0;
        var negative = false;
        var i: usize = 0;

        // Skip whitespace
        while (s[i] == ' ' or s[i] == '\t') : (i += 1) {}

        // Handle sign
        if (s[i] == '-') {
            negative = true;
            i += 1;
        } else if (s[i] == '+') {
            i += 1;
        }

        // Parse digits
        while (s[i] >= '0' and s[i] <= '9') {
            result = result * 10 + @as(i32, s[i] - '0');
            i += 1;
        }

        return if (negative) -result else result;
    }
};

// ============================================================================
// Math Library Wrapper
// ============================================================================

pub const LibM = struct {
    /// sqrt - square root
    pub fn sqrt(x: f64) f64 {
        return @sqrt(x);
    }

    /// sin - sine
    pub fn sin(x: f64) f64 {
        return @sin(x);
    }

    /// cos - cosine
    pub fn cos(x: f64) f64 {
        return @cos(x);
    }

    /// pow - power
    pub fn pow(base: f64, exp: f64) f64 {
        return std.math.pow(f64, base, exp);
    }

    /// floor - floor
    pub fn floor(x: f64) f64 {
        return @floor(x);
    }

    /// ceil - ceiling
    pub fn ceil(x: f64) f64 {
        return @ceil(x);
    }

    /// fabs - absolute value
    pub fn fabs(x: f64) f64 {
        return @abs(x);
    }

    /// log - natural logarithm
    pub fn log(x: f64) f64 {
        return @log(x);
    }

    /// exp - exponential
    pub fn exp(x: f64) f64 {
        return @exp(x);
    }
};

// ============================================================================
// Memory Functions
// ============================================================================

/// memset wrapper
pub fn memset(dest: [*]u8, c: i32, n: usize) [*]u8 {
    @memset(dest[0..n], @intCast(c));
    return dest;
}

/// memcpy wrapper
pub fn memcpy(dest: [*]u8, src: [*]const u8, n: usize) [*]u8 {
    @memcpy(dest[0..n], src[0..n]);
    return dest;
}

/// memcmp wrapper
pub fn memcmp(s1: [*]const u8, s2: [*]const u8, n: usize) i32 {
    for (0..n) |i| {
        if (s1[i] < s2[i]) return -1;
        if (s1[i] > s2[i]) return 1;
    }
    return 0;
}

// ============================================================================
// Test Cases
// ============================================================================

fn testStrlen() !void {
    try std.testing.expectEqual(@as(usize, 0), LibC.strlen(""));
    try std.testing.expectEqual(@as(usize, 5), LibC.strlen("Hello"));
    try std.testing.expectEqual(@as(usize, 13), LibC.strlen("Hello, World!"));
}

fn testStrcmp() !void {
    try std.testing.expectEqual(@as(i32, 0), LibC.strcmp("abc", "abc"));
    try std.testing.expect(LibC.strcmp("abc", "abd") < 0);
    try std.testing.expect(LibC.strcmp("abd", "abc") > 0);
    try std.testing.expect(LibC.strcmp("abc", "ab") > 0);
    try std.testing.expect(LibC.strcmp("ab", "abc") < 0);
}

fn testAbs() !void {
    try std.testing.expectEqual(@as(i32, 42), LibC.abs(42));
    try std.testing.expectEqual(@as(i32, 42), LibC.abs(-42));
    try std.testing.expectEqual(@as(i32, 0), LibC.abs(0));
}

fn testToupper() !void {
    try std.testing.expectEqual(@as(i32, 'A'), LibC.toupper('a'));
    try std.testing.expectEqual(@as(i32, 'Z'), LibC.toupper('z'));
    try std.testing.expectEqual(@as(i32, 'A'), LibC.toupper('A'));
    try std.testing.expectEqual(@as(i32, '1'), LibC.toupper('1'));
}

fn testTolower() !void {
    try std.testing.expectEqual(@as(i32, 'a'), LibC.tolower('A'));
    try std.testing.expectEqual(@as(i32, 'z'), LibC.tolower('Z'));
    try std.testing.expectEqual(@as(i32, 'a'), LibC.tolower('a'));
    try std.testing.expectEqual(@as(i32, '1'), LibC.tolower('1'));
}

fn testIsdigit() !void {
    try std.testing.expectEqual(@as(i32, 1), LibC.isdigit('0'));
    try std.testing.expectEqual(@as(i32, 1), LibC.isdigit('9'));
    try std.testing.expectEqual(@as(i32, 0), LibC.isdigit('a'));
    try std.testing.expectEqual(@as(i32, 0), LibC.isdigit(' '));
}

fn testIsalpha() !void {
    try std.testing.expectEqual(@as(i32, 1), LibC.isalpha('a'));
    try std.testing.expectEqual(@as(i32, 1), LibC.isalpha('Z'));
    try std.testing.expectEqual(@as(i32, 0), LibC.isalpha('1'));
    try std.testing.expectEqual(@as(i32, 0), LibC.isalpha(' '));
}

fn testAtoi() !void {
    try std.testing.expectEqual(@as(i32, 123), LibC.atoi("123"));
    try std.testing.expectEqual(@as(i32, -456), LibC.atoi("-456"));
    try std.testing.expectEqual(@as(i32, 789), LibC.atoi("  789"));
    try std.testing.expectEqual(@as(i32, 42), LibC.atoi("42abc"));
    try std.testing.expectEqual(@as(i32, 0), LibC.atoi("abc"));
}

fn testSqrt() !void {
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), LibM.sqrt(4.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), LibM.sqrt(9.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), LibM.sqrt(100.0), 0.001);
}

fn testSinCos() !void {
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), LibM.sin(0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), LibM.cos(0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), LibM.sin(std.math.pi / 2.0), 0.001);
}

fn testPow() !void {
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), LibM.pow(2.0, 3.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), LibM.pow(5.0, 0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), LibM.pow(10.0, 2.0), 0.001);
}

fn testFloorCeil() !void {
    try std.testing.expectEqual(@as(f64, 3.0), LibM.floor(3.7));
    try std.testing.expectEqual(@as(f64, 4.0), LibM.ceil(3.1));
    try std.testing.expectEqual(@as(f64, -4.0), LibM.floor(-3.1));
    try std.testing.expectEqual(@as(f64, -3.0), LibM.ceil(-3.7));
}

fn testMemset() !void {
    var buf: [10]u8 = undefined;
    _ = memset(&buf, 0xAA, 10);
    for (buf) |b| {
        try std.testing.expectEqual(@as(u8, 0xAA), b);
    }
}

fn testMemcpy() !void {
    var src = [_]u8{ 1, 2, 3, 4, 5 };
    var dest: [5]u8 = undefined;
    _ = memcpy(&dest, &src, 5);
    try std.testing.expectEqualSlices(u8, &src, &dest);
}

fn testMemcmp() !void {
    const a = [_]u8{ 1, 2, 3 };
    const b = [_]u8{ 1, 2, 3 };
    const c = [_]u8{ 1, 2, 4 };

    try std.testing.expectEqual(@as(i32, 0), memcmp(&a, &b, 3));
    try std.testing.expect(memcmp(&a, &c, 3) < 0);
    try std.testing.expect(memcmp(&c, &a, 3) > 0);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "strlen" {
    try testStrlen();
}

test "strcmp" {
    try testStrcmp();
}

test "abs" {
    try testAbs();
}

test "toupper" {
    try testToupper();
}

test "tolower" {
    try testTolower();
}

test "isdigit" {
    try testIsdigit();
}

test "isalpha" {
    try testIsalpha();
}

test "atoi" {
    try testAtoi();
}

test "sqrt" {
    try testSqrt();
}

test "sin_cos" {
    try testSinCos();
}

test "pow" {
    try testPow();
}

test "floor_ceil" {
    try testFloorCeil();
}

test "memset" {
    try testMemset();
}

test "memcpy" {
    try testMemcpy();
}

test "memcmp" {
    try testMemcmp();
}
