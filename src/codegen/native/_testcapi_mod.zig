/// Python _testcapi module - CPython internal test API
/// Provides access to C limits and internal test functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "CHAR_MAX", genCHAR_MAX },
    .{ "CHAR_MIN", genCHAR_MIN },
    .{ "UCHAR_MAX", genUCHAR_MAX },
    .{ "SHRT_MAX", genSHRT_MAX },
    .{ "SHRT_MIN", genSHRT_MIN },
    .{ "USHRT_MAX", genUSHRT_MAX },
    .{ "INT_MAX", genINT_MAX },
    .{ "INT_MIN", genINT_MIN },
    .{ "UINT_MAX", genUINT_MAX },
    .{ "INT32_MAX", genINT32_MAX },
    .{ "INT32_MIN", genINT32_MIN },
    .{ "UINT32_MAX", genUINT32_MAX },
    .{ "LONG_MAX", genLONG_MAX },
    .{ "LONG_MIN", genLONG_MIN },
    .{ "ULONG_MAX", genULONG_MAX },
    .{ "LLONG_MAX", genLLONG_MAX },
    .{ "LLONG_MIN", genLLONG_MIN },
    .{ "ULLONG_MAX", genULLONG_MAX },
    .{ "INT64_MAX", genINT64_MAX },
    .{ "INT64_MIN", genINT64_MIN },
    .{ "UINT64_MAX", genUINT64_MAX },
    .{ "PY_SSIZE_T_MAX", genPY_SSIZE_T_MAX },
    .{ "PY_SSIZE_T_MIN", genPY_SSIZE_T_MIN },
    .{ "SIZE_MAX", genSIZE_MAX },
    .{ "FLT_MAX", genFLT_MAX },
    .{ "FLT_MIN", genFLT_MIN },
    .{ "DBL_MAX", genDBL_MAX },
    .{ "DBL_MIN", genDBL_MIN },
    .{ "SIZEOF_VOID_P", genSIZEOF_VOID_P },
    .{ "SIZEOF_WCHAR_T", genSIZEOF_WCHAR_T },
    .{ "SIZEOF_TIME_T", genSIZEOF_TIME_T },
    .{ "SIZEOF_PID_T", genSIZEOF_PID_T },
    .{ "Py_single_input", genPy_single_input },
    .{ "Py_file_input", genPy_file_input },
    .{ "Py_eval_input", genPy_eval_input },
    .{ "the_number_three", genthe_number_three },
    .{ "Py_Version", genPy_Version },
    .{ "_Py_STACK_GROWS_DOWN", gen_Py_STACK_GROWS_DOWN },
    .{ "test_string_to_double", gentest_string_to_double },
    .{ "test_unicode_compare_with_ascii", gentest_unicode_compare_with_ascii },
    .{ "test_empty_argparse", gentest_empty_argparse },
    .{ "get_args", genget_args },
    .{ "get_kwargs", genget_kwargs },
    .{ "MyList", genMyList },
    .{ "GenericAlias", genGenericAlias },
    .{ "Generic", genGeneric },
    .{ "instancemethod", geninstancemethod },
    .{ "error", generror },
});

// ============================================================================
// Character limits
// ============================================================================

pub fn genCHAR_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 127)");
}

pub fn genCHAR_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, -128)");
}

pub fn genUCHAR_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 255)");
}

// ============================================================================
// Short integer limits
// ============================================================================

pub fn genSHRT_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 32767)");
}

pub fn genSHRT_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, -32768)");
}

pub fn genUSHRT_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 65535)");
}

// ============================================================================
// Integer limits (32-bit)
// ============================================================================

pub fn genINT_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 2147483647)");
}

pub fn genINT_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, -2147483648)");
}

pub fn genUINT_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 4294967295)");
}

pub fn genINT32_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 2147483647)");
}

pub fn genINT32_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, -2147483648)");
}

pub fn genUINT32_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 4294967295)");
}

// ============================================================================
// Long integer limits (64-bit)
// ============================================================================

pub fn genLONG_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 9223372036854775807)");
}

pub fn genLONG_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Note: Zig literal limitation, use std.math.minInt
    try self.emit("@as(i64, std.math.minInt(i64))");
}

pub fn genULONG_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // u64 max as i128 to avoid overflow
    try self.emit("@as(i128, 18446744073709551615)");
}

pub fn genLLONG_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 9223372036854775807)");
}

pub fn genLLONG_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, std.math.minInt(i64))");
}

pub fn genULLONG_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i128, 18446744073709551615)");
}

pub fn genINT64_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 9223372036854775807)");
}

pub fn genINT64_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, std.math.minInt(i64))");
}

pub fn genUINT64_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i128, 18446744073709551615)");
}

// ============================================================================
// Python-specific limits
// ============================================================================

pub fn genPY_SSIZE_T_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 9223372036854775807)");
}

pub fn genPY_SSIZE_T_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, std.math.minInt(i64))");
}

pub fn genSIZE_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i128, 18446744073709551615)");
}

// ============================================================================
// Float limits
// ============================================================================

pub fn genFLT_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 3.4028234663852886e+38)");
}

pub fn genFLT_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 1.1754943508222875e-38)");
}

pub fn genDBL_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 1.7976931348623157e+308)");
}

pub fn genDBL_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 2.2250738585072014e-308)");
}

// ============================================================================
// Sizeof constants
// ============================================================================

pub fn genSIZEOF_VOID_P(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, @sizeOf(*anyopaque))");
}

pub fn genSIZEOF_WCHAR_T(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // On most systems wchar_t is 4 bytes
    try self.emit("@as(i64, 4)");
}

pub fn genSIZEOF_TIME_T(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Modern systems use 64-bit time_t
    try self.emit("@as(i64, 8)");
}

pub fn genSIZEOF_PID_T(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // pid_t is typically 4 bytes
    try self.emit("@as(i64, 4)");
}

// ============================================================================
// Parser input modes
// ============================================================================

pub fn genPy_single_input(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 256)");
}

pub fn genPy_file_input(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 257)");
}

pub fn genPy_eval_input(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 258)");
}

// ============================================================================
// Misc constants
// ============================================================================

pub fn genthe_number_three(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 3)");
}

pub fn genPy_Version(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Python 3.12 version hex: 0x030C0000
    try self.emit("@as(i64, 0x030C0000)");
}

pub fn gen_Py_STACK_GROWS_DOWN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Stack grows down on most architectures
    try self.emit("@as(i64, 1)");
}

// ============================================================================
// Test functions (stubs for compatibility)
// ============================================================================

pub fn gentest_string_to_double(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Stub - returns 0.0
    try self.emit("@as(f64, 0.0)");
}

pub fn gentest_unicode_compare_with_ascii(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Stub - returns true
    try self.emit("true");
}

pub fn gentest_empty_argparse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Stub - does nothing
    try self.emit("{}");
}

pub fn genget_args(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Stub - returns empty tuple
    try self.emit(".{}");
}

pub fn genget_kwargs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Stub - returns empty dict
    try self.emit("hashmap_helper.StringHashMap(i64).init(__global_allocator)");
}

// Types (stubs)
pub fn genMyList(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("std.ArrayList(i64){}");
}

pub fn genGenericAlias(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("void");
}

pub fn genGeneric(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("void");
}

pub fn geninstancemethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("void");
}

pub fn generror(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.TestCAPIError");
}
