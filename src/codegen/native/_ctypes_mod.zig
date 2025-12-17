/// Python _ctypes module - Internal ctypes support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "CDLL", genCDLL },
    .{ "PyDLL", genPyDLL },
    .{ "WinDLL", genWinDLL },
    .{ "OleDLL", genOleDLL },
    .{ "dlopen", genDlopen },
    .{ "dlclose", genDlclose },
    .{ "dlsym", genDlsym },
    .{ "FUNCFLAG_CDECL", genFuncflagCdecl },
    .{ "FUNCFLAG_USE_ERRNO", genFuncflagUseErrno },
    .{ "FUNCFLAG_USE_LASTERROR", genFuncflagUseLasterror },
    .{ "FUNCFLAG_PYTHONAPI", genFuncflagPythonapi },
    .{ "sizeof", genSizeof },
    .{ "alignment", genAlignment },
    .{ "byref", genByref },
    .{ "addressof", genAddressof },
    .{ "POINTER", genPointer },
    .{ "pointer", genPointerVal },
    .{ "cast", genCast },
    .{ "set_errno", genSetErrno },
    .{ "get_errno", genGetErrno },
    .{ "resize", genResize },
    .{ "c_void_p", genCVoidP },
    .{ "c_char_p", genCCharP },
    .{ "c_wchar_p", genCWcharP },
    .{ "c_bool", genCBool },
    .{ "c_char", genCChar },
    .{ "c_wchar", genCWchar },
    .{ "c_byte", genCByte },
    .{ "c_ubyte", genCUbyte },
    .{ "c_short", genCShort },
    .{ "c_ushort", genCUshort },
    .{ "c_int", genCInt },
    .{ "c_uint", genCUint },
    .{ "c_long", genCLong },
    .{ "c_ulong", genCUlong },
    .{ "c_longlong", genCLonglong },
    .{ "c_ulonglong", genCUlonglong },
    .{ "c_size_t", genCSizeT },
    .{ "c_ssize_t", genCSsizeT },
    .{ "c_float", genCFloat },
    .{ "c_double", genCDouble },
    .{ "c_longdouble", genCLongdouble },
    .{ "Structure", genStructure },
    .{ "Union", genUnion },
    .{ "Array", genArray },
    .{ "ArgumentError", genArgumentError },
});

fn genCDLL(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .handle = null, .name = null }"), builder_mod.EmitConfig.forExpression());
}

fn genPyDLL(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .handle = null, .name = null }"), builder_mod.EmitConfig.forExpression());
}

fn genWinDLL(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .handle = null, .name = null }"), builder_mod.EmitConfig.forExpression());
}

fn genOleDLL(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .handle = null, .name = null }"), builder_mod.EmitConfig.forExpression());
}

fn genDlopen(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genDlclose(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genDlsym(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genFuncflagCdecl(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(1), builder_mod.EmitConfig.forExpression());
}

fn genFuncflagUseErrno(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(8), builder_mod.EmitConfig.forExpression());
}

fn genFuncflagUseLasterror(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(16), builder_mod.EmitConfig.forExpression());
}

fn genFuncflagPythonapi(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genSizeof(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(usize, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genAlignment(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(usize, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genByref(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genAddressof(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(usize, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genPointer(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@TypeOf(.{})"), builder_mod.EmitConfig.forExpression());
}

fn genPointerVal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genCast(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genSetErrno(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genGetErrno(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genResize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genCVoidP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genCCharP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?[*:0]const u8, null)"), builder_mod.EmitConfig.forExpression());
}

fn genCWcharP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?[*:0]const u16, null)"), builder_mod.EmitConfig.forExpression());
}

fn genCBool(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(bool, false)"), builder_mod.EmitConfig.forExpression());
}

fn genCChar(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genCWchar(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u16, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genCByte(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i8, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genCUbyte(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u8, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genCShort(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i16, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genCUshort(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u16, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genCInt(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genCUint(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u32, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genCLong(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genCUlong(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u64, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genCLonglong(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(0), builder_mod.EmitConfig.forExpression());
}

fn genCUlonglong(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u64, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genCSizeT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(usize, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genCSsizeT(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(isize, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genCFloat(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(f32, 0.0)"), builder_mod.EmitConfig.forExpression());
}

fn genCDouble(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.float(0.0), builder_mod.EmitConfig.forExpression());
}

fn genCLongdouble(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.float(0.0), builder_mod.EmitConfig.forExpression());
}

fn genStructure(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genUnion(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genArray(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genArgumentError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.ArgumentError"), builder_mod.EmitConfig.forExpression());
}

