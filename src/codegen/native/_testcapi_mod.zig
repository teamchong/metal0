/// Python _testcapi module - CPython internal test API
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

// Helper for emitting a ZigValue expression
fn emitValue(self: *h.NativeCodegen, val: builder_mod.ZigValue) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(val, builder_mod.EmitConfig.forExpression());
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "get_feature_macros", genGetFeatureMacros },
    .{ "CHAR_MAX", genCharMax },
    .{ "CHAR_MIN", genCharMin },
    .{ "UCHAR_MAX", genUcharMax },
    .{ "SHRT_MAX", genShrtMax },
    .{ "SHRT_MIN", genShrtMin },
    .{ "USHRT_MAX", genUshrtMax },
    .{ "INT_MAX", genIntMax },
    .{ "INT_MIN", genIntMin },
    .{ "UINT_MAX", genUintMax },
    .{ "INT32_MAX", genInt32Max },
    .{ "INT32_MIN", genInt32Min },
    .{ "UINT32_MAX", genUint32Max },
    .{ "LONG_MAX", genLongMax },
    .{ "LONG_MIN", genLongMin },
    .{ "ULONG_MAX", genUlongMax },
    .{ "LLONG_MAX", genLlongMax },
    .{ "LLONG_MIN", genLlongMin },
    .{ "ULLONG_MAX", genUllongMax },
    .{ "INT64_MAX", genInt64Max },
    .{ "INT64_MIN", genInt64Min },
    .{ "UINT64_MAX", genUint64Max },
    .{ "PY_SSIZE_T_MAX", genPySsizeTMax },
    .{ "PY_SSIZE_T_MIN", genPySsizeTMin },
    .{ "SIZE_MAX", genSizeMax },
    .{ "FLT_MAX", genFltMax },
    .{ "FLT_MIN", genFltMin },
    .{ "DBL_MAX", genDblMax },
    .{ "DBL_MIN", genDblMin },
    .{ "SIZEOF_VOID_P", genSizeofVoidP },
    .{ "SIZEOF_WCHAR_T", genSizeofWcharT },
    .{ "SIZEOF_TIME_T", genSizeofTimeT },
    .{ "SIZEOF_PID_T", genSizeofPidT },
    .{ "Py_single_input", genPySingleInput },
    .{ "Py_file_input", genPyFileInput },
    .{ "Py_eval_input", genPyEvalInput },
    .{ "the_number_three", genTheNumberThree },
    .{ "Py_Version", genPyVersion },
    .{ "_Py_STACK_GROWS_DOWN", genPyStackGrowsDown },
    .{ "test_string_to_double", genTestStringToDouble },
    .{ "test_unicode_compare_with_ascii", genTestUnicodeCompareWithAscii },
    .{ "test_empty_argparse", genTestEmptyArgparse },
    .{ "get_args", genGetArgs },
    .{ "get_kwargs", genGetKwargs },
    .{ "MyList", genMyList },
    .{ "GenericAlias", genGenericAlias },
    .{ "Generic", genGeneric },
    .{ "instancemethod", genInstancemethod },
    .{ "error", genError },
});

fn genGetFeatureMacros(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("runtime.FeatureMacros{}"));
}

fn genCharMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(127));
}

fn genCharMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(-128));
}

fn genUcharMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(255));
}

fn genShrtMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(32767));
}

fn genShrtMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(-32768));
}

fn genUshrtMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(65535));
}

fn genIntMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(2147483647));
}

fn genIntMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(-2147483648));
}

fn genUintMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(4294967295));
}

fn genInt32Max(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(2147483647));
}

fn genInt32Min(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(-2147483648));
}

fn genUint32Max(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(4294967295));
}

fn genLongMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(i64, 9223372036854775807)"));
}

fn genLongMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(i64, std.math.minInt(i64))"));
}

fn genUlongMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(i128, 18446744073709551615)"));
}

fn genLlongMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(i64, 9223372036854775807)"));
}

fn genLlongMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(i64, std.math.minInt(i64))"));
}

fn genUllongMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(i128, 18446744073709551615)"));
}

fn genInt64Max(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(i64, 9223372036854775807)"));
}

fn genInt64Min(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(i64, std.math.minInt(i64))"));
}

fn genUint64Max(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(i128, 18446744073709551615)"));
}

fn genPySsizeTMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(i64, 9223372036854775807)"));
}

fn genPySsizeTMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(i64, std.math.minInt(i64))"));
}

fn genSizeMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(i128, 18446744073709551615)"));
}

fn genFltMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(f64, 3.4028234663852886e+38)"));
}

fn genFltMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(f64, 1.1754943508222875e-38)"));
}

fn genDblMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(f64, 1.7976931348623157e+308)"));
}

fn genDblMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(f64, 2.2250738585072014e-308)"));
}

fn genSizeofVoidP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("@as(i64, @sizeOf(*anyopaque))"));
}

fn genSizeofWcharT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(4));
}

fn genSizeofTimeT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(8));
}

fn genSizeofPidT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(4));
}

fn genPySingleInput(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(256));
}

fn genPyFileInput(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(257));
}

fn genPyEvalInput(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(258));
}

fn genTheNumberThree(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(3));
}

fn genPyVersion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(0x030C0000));
}

fn genPyStackGrowsDown(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.int(1));
}

fn genTestStringToDouble(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.float(0.0));
}

fn genTestUnicodeCompareWithAscii(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.boolean(true));
}

fn genTestEmptyArgparse(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("{}"));
}

fn genGetArgs(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw(".{}"));
}

fn genGetKwargs(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("hashmap_helper.StringHashMap(i64).init(__global_allocator)"));
}

fn genMyList(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("std.ArrayList(i64){}"));
}

fn genGenericAlias(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("void"));
}

fn genGeneric(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("void"));
}

fn genInstancemethod(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("void"));
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitValue(self, builder_mod.ZigValue.raw("error.TestCAPIError"));
}
