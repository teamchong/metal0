/// Python _testcapi module - CPython internal test API
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genVoid(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "void"); }
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "true"); }
fn genF64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 0.0)"); }
fn genI64(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i64, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "CHAR_MAX", genI64(127) }, .{ "CHAR_MIN", genI64(-128) }, .{ "UCHAR_MAX", genI64(255) },
    .{ "SHRT_MAX", genI64(32767) }, .{ "SHRT_MIN", genI64(-32768) }, .{ "USHRT_MAX", genI64(65535) },
    .{ "INT_MAX", genI64(2147483647) }, .{ "INT_MIN", genI64(-2147483648) }, .{ "UINT_MAX", genI64(4294967295) },
    .{ "INT32_MAX", genI64(2147483647) }, .{ "INT32_MIN", genI64(-2147483648) }, .{ "UINT32_MAX", genI64(4294967295) },
    .{ "LONG_MAX", genI64_MAX }, .{ "LONG_MIN", genI64_MIN }, .{ "ULONG_MAX", genU64_MAX },
    .{ "LLONG_MAX", genI64_MAX }, .{ "LLONG_MIN", genI64_MIN }, .{ "ULLONG_MAX", genU64_MAX },
    .{ "INT64_MAX", genI64_MAX }, .{ "INT64_MIN", genI64_MIN }, .{ "UINT64_MAX", genU64_MAX },
    .{ "PY_SSIZE_T_MAX", genI64_MAX }, .{ "PY_SSIZE_T_MIN", genI64_MIN }, .{ "SIZE_MAX", genU64_MAX },
    .{ "FLT_MAX", genFLT_MAX }, .{ "FLT_MIN", genFLT_MIN }, .{ "DBL_MAX", genDBL_MAX }, .{ "DBL_MIN", genDBL_MIN },
    .{ "SIZEOF_VOID_P", genSIZEOF_VOID_P }, .{ "SIZEOF_WCHAR_T", genI64(4) }, .{ "SIZEOF_TIME_T", genI64(8) }, .{ "SIZEOF_PID_T", genI64(4) },
    .{ "Py_single_input", genI64(256) }, .{ "Py_file_input", genI64(257) }, .{ "Py_eval_input", genI64(258) },
    .{ "the_number_three", genI64(3) }, .{ "Py_Version", genPy_Version }, .{ "_Py_STACK_GROWS_DOWN", genI64(1) },
    .{ "test_string_to_double", genF64_0 }, .{ "test_unicode_compare_with_ascii", genTrue },
    .{ "test_empty_argparse", genUnit }, .{ "get_args", genEmpty }, .{ "get_kwargs", genEmptyDict },
    .{ "MyList", genMyList }, .{ "GenericAlias", genVoid }, .{ "Generic", genVoid },
    .{ "instancemethod", genVoid }, .{ "error", genError },
});

fn genI64_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 9223372036854775807)"); }
fn genI64_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, std.math.minInt(i64))"); }
fn genU64_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i128, 18446744073709551615)"); }
fn genFLT_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 3.4028234663852886e+38)"); }
fn genFLT_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 1.1754943508222875e-38)"); }
fn genDBL_MAX(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 1.7976931348623157e+308)"); }
fn genDBL_MIN(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(f64, 2.2250738585072014e-308)"); }
fn genSIZEOF_VOID_P(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, @sizeOf(*anyopaque))"); }
fn genPy_Version(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0x030C0000)"); }
fn genEmptyDict(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "hashmap_helper.StringHashMap(i64).init(__global_allocator)"); }
fn genMyList(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "std.ArrayList(i64){}"); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.TestCAPIError"); }
