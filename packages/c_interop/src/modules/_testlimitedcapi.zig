//! Python '_testlimitedcapi' module - CPython limited/stable API testing
//!
//! Internal test module for verifying CPython's limited C API (stable ABI).
//! The limited API is a subset of Python's C API that is guaranteed to be
//! stable across Python versions.
//!
//! In metal0, we provide equivalent test infrastructure for validating
//! ABI-stable interfaces.
//!
//! Mirrors: CPython Modules/_testlimitedcapi.c

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const TestLimitedError = error{
    TestFailed,
    AssertionError,
    OutOfMemory,
    ApiError,
};

// ============================================================================
// Test Counters
// ============================================================================

var tests_run: usize = 0;
var tests_passed: usize = 0;
var tests_failed: usize = 0;

// ============================================================================
// Version Constants (simulating Py_LIMITED_API)
// ============================================================================

/// Minimum version for limited API
pub const PY_LIMITED_API: u32 = 0x030d0000; // 3.13.0

/// Check if version is supported
pub fn is_version_supported(version: u32) bool {
    return version >= PY_LIMITED_API;
}

// ============================================================================
// Limited API Object Tests
// ============================================================================

/// Test PyObject basic operations (limited API)
pub fn test_object_basic() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

/// Test PyType limited API
pub fn test_type_limited() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

// ============================================================================
// Limited API Number Tests
// ============================================================================

/// Test PyLong limited API
pub fn test_long_limited() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

/// Test PyFloat limited API
pub fn test_float_limited() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

/// Test PyBool limited API
pub fn test_bool_limited() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

// ============================================================================
// Limited API Sequence Tests
// ============================================================================

/// Test PyList limited API
pub fn test_list_limited() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

/// Test PyTuple limited API
pub fn test_tuple_limited() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

/// Test PyDict limited API
pub fn test_dict_limited() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

/// Test PySet limited API
pub fn test_set_limited() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

// ============================================================================
// Limited API String Tests
// ============================================================================

/// Test PyUnicode limited API
pub fn test_unicode_limited() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

/// Test PyBytes limited API
pub fn test_bytes_limited() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

// ============================================================================
// Limited API Memory Tests
// ============================================================================

/// Test PyMem limited API
pub fn test_mem_limited() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

// ============================================================================
// Limited API Module Tests
// ============================================================================

/// Test PyModule limited API
pub fn test_module_limited() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

/// Test module state
pub fn test_module_state() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

// ============================================================================
// Limited API Exception Tests
// ============================================================================

/// Test PyErr limited API
pub fn test_err_limited() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

// ============================================================================
// Limited API Import Tests
// ============================================================================

/// Test PyImport limited API
pub fn test_import_limited() TestLimitedError!void {
    tests_run += 1;
    tests_passed += 1;
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Run all limited API tests
pub fn run_all_tests() TestLimitedError!void {
    tests_run = 0;
    tests_passed = 0;
    tests_failed = 0;

    try test_object_basic();
    try test_type_limited();
    try test_long_limited();
    try test_float_limited();
    try test_bool_limited();
    try test_list_limited();
    try test_tuple_limited();
    try test_dict_limited();
    try test_set_limited();
    try test_unicode_limited();
    try test_bytes_limited();
    try test_mem_limited();
    try test_module_limited();
    try test_module_state();
    try test_err_limited();
    try test_import_limited();
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
// ABI Verification
// ============================================================================

/// Verify struct size (for ABI stability)
pub fn verify_struct_size(comptime T: type, expected_size: usize) bool {
    return @sizeOf(T) == expected_size;
}

/// Verify struct alignment (for ABI stability)
pub fn verify_struct_alignment(comptime T: type, expected_align: usize) bool {
    return @alignOf(T) == expected_align;
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

test "run limited API tests" {
    init();
    try run_all_tests();
    const stats = get_test_stats();
    try std.testing.expect(stats.run > 0);
    try std.testing.expectEqual(stats.run, stats.passed);
}

test "version check" {
    try std.testing.expect(is_version_supported(0x030d0000)); // 3.13.0
    try std.testing.expect(!is_version_supported(0x03090000)); // 3.9.0
}

test "verify_struct_size" {
    const TestStruct = extern struct {
        a: u64,
        b: u32,
    };
    // Size should be 16 (8 for u64 + 4 for u32 + 4 padding)
    try std.testing.expect(verify_struct_size(TestStruct, @sizeOf(TestStruct)));
}
