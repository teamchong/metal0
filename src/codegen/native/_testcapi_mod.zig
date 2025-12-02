/// Python _testcapi module - CPython internal test API
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genI64(comptime n: comptime_int) ModuleHandler { return genConst(std.fmt.comptimePrint("@as(i64, {})", .{n})); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "CHAR_MAX", genI64(127) }, .{ "CHAR_MIN", genI64(-128) }, .{ "UCHAR_MAX", genI64(255) },
    .{ "SHRT_MAX", genI64(32767) }, .{ "SHRT_MIN", genI64(-32768) }, .{ "USHRT_MAX", genI64(65535) },
    .{ "INT_MAX", genI64(2147483647) }, .{ "INT_MIN", genI64(-2147483648) }, .{ "UINT_MAX", genI64(4294967295) },
    .{ "INT32_MAX", genI64(2147483647) }, .{ "INT32_MIN", genI64(-2147483648) }, .{ "UINT32_MAX", genI64(4294967295) },
    .{ "LONG_MAX", genConst("@as(i64, 9223372036854775807)") }, .{ "LONG_MIN", genConst("@as(i64, std.math.minInt(i64))") }, .{ "ULONG_MAX", genConst("@as(i128, 18446744073709551615)") },
    .{ "LLONG_MAX", genConst("@as(i64, 9223372036854775807)") }, .{ "LLONG_MIN", genConst("@as(i64, std.math.minInt(i64))") }, .{ "ULLONG_MAX", genConst("@as(i128, 18446744073709551615)") },
    .{ "INT64_MAX", genConst("@as(i64, 9223372036854775807)") }, .{ "INT64_MIN", genConst("@as(i64, std.math.minInt(i64))") }, .{ "UINT64_MAX", genConst("@as(i128, 18446744073709551615)") },
    .{ "PY_SSIZE_T_MAX", genConst("@as(i64, 9223372036854775807)") }, .{ "PY_SSIZE_T_MIN", genConst("@as(i64, std.math.minInt(i64))") }, .{ "SIZE_MAX", genConst("@as(i128, 18446744073709551615)") },
    .{ "FLT_MAX", genConst("@as(f64, 3.4028234663852886e+38)") }, .{ "FLT_MIN", genConst("@as(f64, 1.1754943508222875e-38)") },
    .{ "DBL_MAX", genConst("@as(f64, 1.7976931348623157e+308)") }, .{ "DBL_MIN", genConst("@as(f64, 2.2250738585072014e-308)") },
    .{ "SIZEOF_VOID_P", genConst("@as(i64, @sizeOf(*anyopaque))") }, .{ "SIZEOF_WCHAR_T", genI64(4) }, .{ "SIZEOF_TIME_T", genI64(8) }, .{ "SIZEOF_PID_T", genI64(4) },
    .{ "Py_single_input", genI64(256) }, .{ "Py_file_input", genI64(257) }, .{ "Py_eval_input", genI64(258) },
    .{ "the_number_three", genI64(3) }, .{ "Py_Version", genConst("@as(i64, 0x030C0000)") }, .{ "_Py_STACK_GROWS_DOWN", genI64(1) },
    .{ "test_string_to_double", genConst("@as(f64, 0.0)") }, .{ "test_unicode_compare_with_ascii", genConst("true") },
    .{ "test_empty_argparse", genConst("{}") }, .{ "get_args", genConst(".{}") }, .{ "get_kwargs", genConst("hashmap_helper.StringHashMap(i64).init(__global_allocator)") },
    .{ "MyList", genConst("std.ArrayList(i64){}") }, .{ "GenericAlias", genConst("void") }, .{ "Generic", genConst("void") },
    .{ "instancemethod", genConst("void") }, .{ "error", genConst("error.TestCAPIError") },
});
