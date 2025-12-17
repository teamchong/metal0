/// Python _testcapi module - CPython internal test API
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

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
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("runtime.FeatureMacros{}"), builder_mod.EmitConfig.forExpression());
}

fn genCharMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(127), builder_mod.EmitConfig.forExpression());
}

fn genCharMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(-128), builder_mod.EmitConfig.forExpression());
}

fn genUcharMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(255), builder_mod.EmitConfig.forExpression());
}

fn genShrtMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(32767), builder_mod.EmitConfig.forExpression());
}

fn genShrtMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(-32768), builder_mod.EmitConfig.forExpression());
}

fn genUshrtMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(65535), builder_mod.EmitConfig.forExpression());
}

fn genIntMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2147483647), builder_mod.EmitConfig.forExpression());
}

fn genIntMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(-2147483648), builder_mod.EmitConfig.forExpression());
}

fn genUintMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4294967295), builder_mod.EmitConfig.forExpression());
}

fn genInt32Max(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(2147483647), builder_mod.EmitConfig.forExpression());
}

fn genInt32Min(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(-2147483648), builder_mod.EmitConfig.forExpression());
}

fn genUint32Max(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4294967295), builder_mod.EmitConfig.forExpression());
}

fn genLongMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 9223372036854775807)"), builder_mod.EmitConfig.forExpression());
}

fn genLongMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, std.math.minInt(i64))"), builder_mod.EmitConfig.forExpression());
}

fn genUlongMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i128, 18446744073709551615)"), builder_mod.EmitConfig.forExpression());
}

fn genLlongMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 9223372036854775807)"), builder_mod.EmitConfig.forExpression());
}

fn genLlongMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, std.math.minInt(i64))"), builder_mod.EmitConfig.forExpression());
}

fn genUllongMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i128, 18446744073709551615)"), builder_mod.EmitConfig.forExpression());
}

fn genInt64Max(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 9223372036854775807)"), builder_mod.EmitConfig.forExpression());
}

fn genInt64Min(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, std.math.minInt(i64))"), builder_mod.EmitConfig.forExpression());
}

fn genUint64Max(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i128, 18446744073709551615)"), builder_mod.EmitConfig.forExpression());
}

fn genPySsizeTMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 9223372036854775807)"), builder_mod.EmitConfig.forExpression());
}

fn genPySsizeTMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, std.math.minInt(i64))"), builder_mod.EmitConfig.forExpression());
}

fn genSizeMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i128, 18446744073709551615)"), builder_mod.EmitConfig.forExpression());
}

fn genFltMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(f64, 3.4028234663852886e+38)"), builder_mod.EmitConfig.forExpression());
}

fn genFltMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(f64, 1.1754943508222875e-38)"), builder_mod.EmitConfig.forExpression());
}

fn genDblMax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(f64, 1.7976931348623157e+308)"), builder_mod.EmitConfig.forExpression());
}

fn genDblMin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(f64, 2.2250738585072014e-308)"), builder_mod.EmitConfig.forExpression());
}

fn genSizeofVoidP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, @sizeOf(*anyopaque))"), builder_mod.EmitConfig.forExpression());
}

fn genSizeofWcharT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genSizeofTimeT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(8), builder_mod.EmitConfig.forExpression());
}

fn genSizeofPidT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genPySingleInput(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(256), builder_mod.EmitConfig.forExpression());
}

fn genPyFileInput(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(257), builder_mod.EmitConfig.forExpression());
}

fn genPyEvalInput(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(258), builder_mod.EmitConfig.forExpression());
}

fn genTheNumberThree(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(3), builder_mod.EmitConfig.forExpression());
}

fn genPyVersion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0x030C0000), builder_mod.EmitConfig.forExpression());
}

fn genPyStackGrowsDown(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genTestStringToDouble(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.float(0.0), builder_mod.EmitConfig.forExpression());
}

fn genTestUnicodeCompareWithAscii(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(true), builder_mod.EmitConfig.forExpression());
}

fn genTestEmptyArgparse(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetArgs(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetKwargs(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("hashmap_helper.StringHashMap(i64).init(__global_allocator)"), builder_mod.EmitConfig.forExpression());
}

fn genMyList(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("std.ArrayList(i64){}"), builder_mod.EmitConfig.forExpression());
}

fn genGenericAlias(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("void"), builder_mod.EmitConfig.forExpression());
}

fn genGeneric(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("void"), builder_mod.EmitConfig.forExpression());
}

fn genInstancemethod(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("void"), builder_mod.EmitConfig.forExpression());
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.TestCAPIError"), builder_mod.EmitConfig.forExpression());
}

