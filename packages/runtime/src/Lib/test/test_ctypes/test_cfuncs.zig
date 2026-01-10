//! test.test_ctypes.test_cfuncs - Tests for C function calls
//! Reference: cpython/Lib/test/test_ctypes/test_cfuncs.py
//!
//! Tests for calling C functions through ctypes including various
//! calling conventions, return types, and argument passing.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Function Pointer Types
// ============================================================================

/// C calling convention function pointer
pub fn CFuncPtr(comptime ReturnType: type, comptime ArgTypes: anytype) type {
    const info = @typeInfo(@TypeOf(ArgTypes));
    const args_len = if (info == .@"struct") info.@"struct".fields.len else 0;

    return struct {
        const Self = @This();
        pub const Return = ReturnType;
        pub const num_args = args_len;

        ptr: ?*const fn () callconv(.C) void = null,

        pub fn init(p: ?*const fn () callconv(.C) void) Self {
            return .{ .ptr = p };
        }

        pub fn isNull(self: Self) bool {
            return self.ptr == null;
        }

        pub fn address(self: Self) usize {
            if (self.ptr) |p| {
                return @intFromPtr(p);
            }
            return 0;
        }
    };
}

// ============================================================================
// Function Signatures
// ============================================================================

/// Describe a C function signature
pub const FuncSignature = struct {
    name: []const u8,
    return_type: TypeDesc,
    arg_types: []const TypeDesc,
    variadic: bool = false,
};

/// Type description for signatures
pub const TypeDesc = struct {
    name: []const u8,
    size: usize,
    is_pointer: bool = false,
    is_const: bool = false,
};

// Common type descriptors
pub const TYPE_VOID = TypeDesc{ .name = "void", .size = 0 };
pub const TYPE_INT = TypeDesc{ .name = "int", .size = 4 };
pub const TYPE_LONG = TypeDesc{ .name = "long", .size = 8 };
pub const TYPE_DOUBLE = TypeDesc{ .name = "double", .size = 8 };
pub const TYPE_CHAR_P = TypeDesc{ .name = "char*", .size = 8, .is_pointer = true };
pub const TYPE_VOID_P = TypeDesc{ .name = "void*", .size = 8, .is_pointer = true };

// ============================================================================
// Mock C Functions
// ============================================================================

/// Mock abs function
pub fn mock_abs(x: i32) i32 {
    return if (x < 0) -x else x;
}

/// Mock strlen function
pub fn mock_strlen(s: [*:0]const u8) usize {
    var len: usize = 0;
    while (s[len] != 0) : (len += 1) {}
    return len;
}

/// Mock atoi function
pub fn mock_atoi(s: [*:0]const u8) i32 {
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

/// Mock memcmp function
pub fn mock_memcmp(s1: [*]const u8, s2: [*]const u8, n: usize) i32 {
    for (0..n) |i| {
        if (s1[i] < s2[i]) return -1;
        if (s1[i] > s2[i]) return 1;
    }
    return 0;
}

/// Mock sqrt function
pub fn mock_sqrt(x: f64) f64 {
    return @sqrt(x);
}

/// Mock pow function
pub fn mock_pow(base: f64, exp: f64) f64 {
    return std.math.pow(f64, base, exp);
}

// ============================================================================
// Function Call Helpers
// ============================================================================

/// Result of a function call
pub const CallResult = union(enum) {
    int_val: i64,
    uint_val: u64,
    float_val: f64,
    ptr_val: ?*anyopaque,
    void_val,
    err: []const u8,
};

/// Call a function with error handling
pub fn safeCall(comptime func: anytype, args: anytype) CallResult {
    const result = @call(.auto, func, args);
    const RetType = @TypeOf(result);

    if (@typeInfo(RetType) == .int) {
        if (@typeInfo(RetType).int.signedness == .signed) {
            return .{ .int_val = result };
        } else {
            return .{ .uint_val = result };
        }
    } else if (@typeInfo(RetType) == .float) {
        return .{ .float_val = result };
    } else if (@typeInfo(RetType) == .pointer) {
        return .{ .ptr_val = @ptrCast(result) };
    } else if (@typeInfo(RetType) == .void) {
        return .void_val;
    }

    return .{ .err = "Unknown return type" };
}

// ============================================================================
// Test Cases
// ============================================================================

fn testMockAbs() !void {
    try std.testing.expectEqual(@as(i32, 42), mock_abs(42));
    try std.testing.expectEqual(@as(i32, 42), mock_abs(-42));
    try std.testing.expectEqual(@as(i32, 0), mock_abs(0));
}

fn testMockStrlen() !void {
    try std.testing.expectEqual(@as(usize, 0), mock_strlen(""));
    try std.testing.expectEqual(@as(usize, 5), mock_strlen("Hello"));
    try std.testing.expectEqual(@as(usize, 13), mock_strlen("Hello, World!"));
}

fn testMockAtoi() !void {
    try std.testing.expectEqual(@as(i32, 123), mock_atoi("123"));
    try std.testing.expectEqual(@as(i32, -456), mock_atoi("-456"));
    try std.testing.expectEqual(@as(i32, 789), mock_atoi("  789"));
    try std.testing.expectEqual(@as(i32, 42), mock_atoi("42abc"));
}

fn testMockMemcmp() !void {
    try std.testing.expectEqual(@as(i32, 0), mock_memcmp("abc", "abc", 3));
    try std.testing.expect(mock_memcmp("abc", "abd", 3) < 0);
    try std.testing.expect(mock_memcmp("abd", "abc", 3) > 0);
}

fn testMockSqrt() !void {
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), mock_sqrt(4.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), mock_sqrt(9.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.414), mock_sqrt(2.0), 0.001);
}

fn testMockPow() !void {
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), mock_pow(2.0, 3.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), mock_pow(5.0, 0.0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), mock_pow(2.0, -1.0), 0.001);
}

fn testFuncSignature() !void {
    const sig = FuncSignature{
        .name = "strlen",
        .return_type = TypeDesc{ .name = "size_t", .size = 8 },
        .arg_types = &.{TYPE_CHAR_P},
    };

    try std.testing.expectEqualStrings("strlen", sig.name);
    try std.testing.expectEqual(@as(usize, 1), sig.arg_types.len);
    try std.testing.expect(!sig.variadic);
}

fn testVariadicSignature() !void {
    const sig = FuncSignature{
        .name = "printf",
        .return_type = TYPE_INT,
        .arg_types = &.{TYPE_CHAR_P},
        .variadic = true,
    };

    try std.testing.expect(sig.variadic);
}

fn testCFuncPtr() !void {
    const FuncType = CFuncPtr(i32, .{ i32, i32 });
    const fp = FuncType.init(null);

    try std.testing.expect(fp.isNull());
    try std.testing.expectEqual(@as(usize, 0), fp.address());
    try std.testing.expectEqual(@as(usize, 2), FuncType.num_args);
}

fn testSafeCall() !void {
    const result = safeCall(mock_abs, .{-42});

    try std.testing.expect(result == .int_val);
    try std.testing.expectEqual(@as(i64, 42), result.int_val);
}

fn testSafeCallFloat() !void {
    const result = safeCall(mock_sqrt, .{16.0});

    try std.testing.expect(result == .float_val);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), result.float_val, 0.001);
}

fn testTypeDescriptors() !void {
    try std.testing.expectEqual(@as(usize, 0), TYPE_VOID.size);
    try std.testing.expectEqual(@as(usize, 4), TYPE_INT.size);
    try std.testing.expectEqual(@as(usize, 8), TYPE_DOUBLE.size);
    try std.testing.expect(TYPE_CHAR_P.is_pointer);
    try std.testing.expect(!TYPE_INT.is_pointer);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "mock_abs" {
    try testMockAbs();
}

test "mock_strlen" {
    try testMockStrlen();
}

test "mock_atoi" {
    try testMockAtoi();
}

test "mock_memcmp" {
    try testMockMemcmp();
}

test "mock_sqrt" {
    try testMockSqrt();
}

test "mock_pow" {
    try testMockPow();
}

test "func_signature" {
    try testFuncSignature();
}

test "variadic_signature" {
    try testVariadicSignature();
}

test "cfunc_ptr" {
    try testCFuncPtr();
}

test "safe_call" {
    try testSafeCall();
}

test "safe_call_float" {
    try testSafeCallFloat();
}

test "type_descriptors" {
    try testTypeDescriptors();
}
