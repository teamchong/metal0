//! CPython C API Test Module
//!
//! This module provides test functions and constants to verify our Python C API
//! implementation (packages/runtime/src/Python/*). We've rewritten 415 files of
//! CPython's C API in Zig - this module helps ensure correctness.
//!
//! Unlike CPython's _testcapi (4186 lines testing CPython internals), we focus on:
//! 1. Constants needed by tests (INT_MAX, FLT_MAX, etc.)
//! 2. Functions that test our Zig C API implementation
//! 3. Only what's actually used in our test suite

const std = @import("std");

// ============================================================================
// CONSTANTS - Platform limits exposed to Python tests
// ============================================================================

// Integer limits (most commonly used)
pub const INT_MAX: i32 = std.math.maxInt(i32);
pub const INT_MIN: i32 = std.math.minInt(i32);
pub const UINT_MAX: u32 = std.math.maxInt(u32);

pub const LONG_MAX: i64 = std.math.maxInt(c_long);
pub const LONG_MIN: i64 = std.math.minInt(c_long);
pub const ULONG_MAX: u64 = std.math.maxInt(c_ulong);

pub const LLONG_MAX: i64 = std.math.maxInt(i64);
pub const LLONG_MIN: i64 = std.math.minInt(i64);
pub const ULLONG_MAX: u64 = std.math.maxInt(u64);

// Float limits
pub const FLT_MAX: f32 = std.math.floatMax(f32);
pub const FLT_MIN: f32 = std.math.floatMin(f32);
pub const DBL_MAX: f64 = std.math.floatMax(f64);
pub const DBL_MIN: f64 = std.math.floatMin(f64);

// Short limits
pub const SHRT_MAX: i16 = std.math.maxInt(i16);
pub const SHRT_MIN: i16 = std.math.minInt(i16);
pub const USHRT_MAX: u16 = std.math.maxInt(u16);

// Char limits
pub const CHAR_MAX: i8 = std.math.maxInt(i8);
pub const CHAR_MIN: i8 = std.math.minInt(i8);
pub const UCHAR_MAX: u8 = std.math.maxInt(u8);

// Size limits
pub const PY_SSIZE_T_MAX: isize = std.math.maxInt(isize);
pub const PY_SSIZE_T_MIN: isize = std.math.minInt(isize);
pub const SIZE_MAX: usize = std.math.maxInt(usize);

// sizeof() equivalents
pub const SIZEOF_VOID_P: usize = @sizeOf(*anyopaque);
pub const SIZEOF_TIME_T: usize = @sizeOf(i64); // time_t
pub const SIZEOF_PID_T: usize = @sizeOf(i32); // pid_t
pub const SIZEOF_WCHAR_T: usize = @sizeOf(u32); // wchar_t

// Python version
pub const Py_Version: u32 = 0x030d0000; // Python 3.13 equivalent

// ============================================================================
// TEST FUNCTIONS - Implemented as needed by tests
// ============================================================================

// TODO: Implement these as tests require them
// - has_vectorcall_flag
// - pyobject_vectorcall
// - set_nomemory
// - buffer_fill_info
// - make_vectorcall_class
// - frame_getvar
// - with_tp_del
// - dict_get_version
// - etc.

// For now, stub functions can be added here as:
// pub fn functionName(args...) !ReturnType {
//     @panic("_testcapi.functionName not yet implemented - add when test needs it");
// }
