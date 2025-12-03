/// Python _testcapi module - CPython internal test API
const std = @import("std");
const h = @import("mod_helper.zig");

// Feature macros struct - returns CPython build configuration as comptime struct
// This allows compile-time evaluation of if conditions using feature_macros['key']
const feature_macros_code =
    \\runtime.FeatureMacros{}
;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Feature macros function
    .{ "get_feature_macros", h.c(feature_macros_code) },
    // Constants
    .{ "CHAR_MAX", h.I64(127) }, .{ "CHAR_MIN", h.I64(-128) }, .{ "UCHAR_MAX", h.I64(255) },
    .{ "SHRT_MAX", h.I64(32767) }, .{ "SHRT_MIN", h.I64(-32768) }, .{ "USHRT_MAX", h.I64(65535) },
    .{ "INT_MAX", h.I64(2147483647) }, .{ "INT_MIN", h.I64(-2147483648) }, .{ "UINT_MAX", h.I64(4294967295) },
    .{ "INT32_MAX", h.I64(2147483647) }, .{ "INT32_MIN", h.I64(-2147483648) }, .{ "UINT32_MAX", h.I64(4294967295) },
    .{ "LONG_MAX", h.c("@as(i64, 9223372036854775807)") }, .{ "LONG_MIN", h.c("@as(i64, std.math.minInt(i64))") }, .{ "ULONG_MAX", h.c("@as(i128, 18446744073709551615)") },
    .{ "LLONG_MAX", h.c("@as(i64, 9223372036854775807)") }, .{ "LLONG_MIN", h.c("@as(i64, std.math.minInt(i64))") }, .{ "ULLONG_MAX", h.c("@as(i128, 18446744073709551615)") },
    .{ "INT64_MAX", h.c("@as(i64, 9223372036854775807)") }, .{ "INT64_MIN", h.c("@as(i64, std.math.minInt(i64))") }, .{ "UINT64_MAX", h.c("@as(i128, 18446744073709551615)") },
    .{ "PY_SSIZE_T_MAX", h.c("@as(i64, 9223372036854775807)") }, .{ "PY_SSIZE_T_MIN", h.c("@as(i64, std.math.minInt(i64))") }, .{ "SIZE_MAX", h.c("@as(i128, 18446744073709551615)") },
    .{ "FLT_MAX", h.c("@as(f64, 3.4028234663852886e+38)") }, .{ "FLT_MIN", h.c("@as(f64, 1.1754943508222875e-38)") },
    .{ "DBL_MAX", h.c("@as(f64, 1.7976931348623157e+308)") }, .{ "DBL_MIN", h.c("@as(f64, 2.2250738585072014e-308)") },
    .{ "SIZEOF_VOID_P", h.c("@as(i64, @sizeOf(*anyopaque))") }, .{ "SIZEOF_WCHAR_T", h.I64(4) }, .{ "SIZEOF_TIME_T", h.I64(8) }, .{ "SIZEOF_PID_T", h.I64(4) },
    .{ "Py_single_input", h.I64(256) }, .{ "Py_file_input", h.I64(257) }, .{ "Py_eval_input", h.I64(258) },
    .{ "the_number_three", h.I64(3) }, .{ "Py_Version", h.I64(0x030C0000) }, .{ "_Py_STACK_GROWS_DOWN", h.I64(1) },
    .{ "test_string_to_double", h.F64(0.0) }, .{ "test_unicode_compare_with_ascii", h.c("true") },
    .{ "test_empty_argparse", h.c("{}") }, .{ "get_args", h.c(".{}") }, .{ "get_kwargs", h.c("hashmap_helper.StringHashMap(i64).init(__global_allocator)") },
    .{ "MyList", h.c("std.ArrayList(i64){}") }, .{ "GenericAlias", h.c("void") }, .{ "Generic", h.c("void") },
    .{ "instancemethod", h.c("void") }, .{ "error", h.err("TestCAPIError") },
});
