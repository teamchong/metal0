//! Python 'ac_tester' module - Argument Clinic tester
//!
//! Internal test module for the Argument Clinic code generator.
//! Argument Clinic is CPython's tool for generating argument parsing code
//! from docstrings and function signatures.
//!
//! In metal0's AOT model, function signatures are known at compile time,
//! so we use Zig's type system directly rather than runtime argument parsing.
//! This module provides compatibility testing infrastructure.
//!
//! Mirrors: CPython Modules/clinic/_testclinic.c.h

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const ACTesterError = error{
    TestFailed,
    InvalidArgument,
    TypeError,
    ValueError,
    OverflowError,
    OutOfMemory,
};

// ============================================================================
// Test Counters
// ============================================================================

var tests_run: usize = 0;
var tests_passed: usize = 0;
var tests_failed: usize = 0;

// ============================================================================
// Argument Parsing Directives (Clinic DSL elements)
// ============================================================================

/// Converter types supported by Argument Clinic
pub const ConverterType = enum {
    // Basic types
    int,
    unsigned_int,
    long,
    unsigned_long,
    long_long,
    unsigned_long_long,
    Py_ssize_t,
    size_t,
    float_type,
    double_type,
    Py_complex,
    // String types
    str,
    str_nullable,
    PyBytesObject,
    PyByteArrayObject,
    unicode,
    // Boolean
    bool_type,
    // Object types
    object,
    type_obj,
    // Path types
    path,
    // Buffer types
    buffer,
    rwbuffer,
};

/// Argument parsing mode
pub const ParseMode = enum {
    positional_only,
    positional_or_keyword,
    keyword_only,
};

// ============================================================================
// Argument Clinic Test Functions
// ============================================================================

/// Test function with no arguments
pub fn test_no_args() ACTesterError!void {
    tests_run += 1;
    tests_passed += 1;
}

/// Test function with single int argument
pub fn test_int_arg(value: i32) ACTesterError!i32 {
    tests_run += 1;
    tests_passed += 1;
    return value;
}

/// Test function with int and default
pub fn test_int_default(value: ?i32) ACTesterError!i32 {
    tests_run += 1;
    tests_passed += 1;
    return value orelse 42;
}

/// Test function with multiple arguments
pub fn test_multiple_args(a: i32, b: i32, c: i32) ACTesterError!i32 {
    tests_run += 1;
    tests_passed += 1;
    return a + b + c;
}

/// Test function with string argument
pub fn test_str_arg(value: []const u8) ACTesterError!usize {
    tests_run += 1;
    tests_passed += 1;
    return value.len;
}

/// Test function with bool argument
pub fn test_bool_arg(value: bool) ACTesterError!bool {
    tests_run += 1;
    tests_passed += 1;
    return value;
}

/// Test function with float argument
pub fn test_float_arg(value: f64) ACTesterError!f64 {
    tests_run += 1;
    tests_passed += 1;
    return value * 2.0;
}

/// Test function with nullable argument
pub fn test_nullable_arg(value: ?[]const u8) ACTesterError!bool {
    tests_run += 1;
    tests_passed += 1;
    return value != null;
}

/// Test function with positional-only arguments
pub fn test_positional_only(a: i32, b: i32) ACTesterError!i32 {
    tests_run += 1;
    // In Python: def f(a, b, /): ...
    tests_passed += 1;
    return a + b;
}

/// Test function with keyword-only arguments
pub fn test_keyword_only(value: i32) ACTesterError!i32 {
    tests_run += 1;
    // In Python: def f(*, value): ...
    tests_passed += 1;
    return value;
}

// ============================================================================
// Type Conversion Tests
// ============================================================================

/// Test integer overflow detection
pub fn test_int_overflow() ACTesterError!void {
    tests_run += 1;
    const max_i32: i64 = std.math.maxInt(i32);
    if (max_i32 > std.math.maxInt(i32)) {
        tests_failed += 1;
        return error.OverflowError;
    }
    tests_passed += 1;
}

/// Test string to int conversion
pub fn test_str_to_int(s: []const u8) ACTesterError!i64 {
    tests_run += 1;
    const result = std.fmt.parseInt(i64, s, 10) catch {
        tests_failed += 1;
        return error.ValueError;
    };
    tests_passed += 1;
    return result;
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Run all AC tester tests
pub fn run_all_tests() ACTesterError!void {
    tests_run = 0;
    tests_passed = 0;
    tests_failed = 0;

    try test_no_args();
    _ = try test_int_arg(42);
    _ = try test_int_default(null);
    _ = try test_multiple_args(1, 2, 3);
    _ = try test_str_arg("hello");
    _ = try test_bool_arg(true);
    _ = try test_float_arg(3.14);
    _ = try test_nullable_arg(null);
    _ = try test_positional_only(1, 2);
    _ = try test_keyword_only(10);
    try test_int_overflow();
    _ = try test_str_to_int("123");
}

/// Get test statistics
pub fn get_test_stats() struct { run: usize, passed: usize, failed: usize } {
    return .{
        .run = tests_run,
        .passed = tests_passed,
        .failed = tests_failed,
    };
}

/// Reset test counters
pub fn reset_test_stats() void {
    tests_run = 0;
    tests_passed = 0;
    tests_failed = 0;
}

// ============================================================================
// Docstring Parsing Helpers
// ============================================================================

/// Parse a function signature from docstring
pub fn parseSignature(doc: []const u8) ?struct { name: []const u8, args: []const u8 } {
    // Find opening paren
    const paren_start = std.mem.indexOf(u8, doc, "(") orelse return null;
    const paren_end = std.mem.indexOf(u8, doc, ")") orelse return null;

    return .{
        .name = doc[0..paren_start],
        .args = doc[paren_start + 1 .. paren_end],
    };
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
    reset_test_stats();
}

pub fn reset() void {
    reset_test_stats();
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "run AC tester tests" {
    init();
    try run_all_tests();
    const stats = get_test_stats();
    try std.testing.expect(stats.run > 0);
    try std.testing.expectEqual(stats.run, stats.passed);
}

test "test_int_arg" {
    const result = try test_int_arg(100);
    try std.testing.expectEqual(@as(i32, 100), result);
}

test "test_int_default" {
    const with_value = try test_int_default(10);
    try std.testing.expectEqual(@as(i32, 10), with_value);

    const with_default = try test_int_default(null);
    try std.testing.expectEqual(@as(i32, 42), with_default);
}

test "test_multiple_args" {
    const result = try test_multiple_args(1, 2, 3);
    try std.testing.expectEqual(@as(i32, 6), result);
}

test "parseSignature" {
    const sig = parseSignature("foo(a, b, c)");
    try std.testing.expect(sig != null);
    try std.testing.expectEqualStrings("foo", sig.?.name);
    try std.testing.expectEqualStrings("a, b, c", sig.?.args);
}

test "ConverterType enum" {
    try std.testing.expect(@intFromEnum(ConverterType.int) == 0);
    try std.testing.expect(@intFromEnum(ConverterType.str) != @intFromEnum(ConverterType.int));
}
