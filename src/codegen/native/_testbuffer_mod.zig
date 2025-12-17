/// Python _testbuffer module - Buffer protocol test support
/// Provides ndarray and buffer flag constants for testing PEP-3118
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

// Buffer flags (from Python's buffer protocol)
// These match CPython's definitions in Include/cpython/object.h
pub const PyBUF_SIMPLE: i64 = 0;
pub const PyBUF_WRITABLE: i64 = 0x0001;
pub const PyBUF_WRITE: i64 = PyBUF_WRITABLE; // Alias
pub const PyBUF_READ: i64 = 0x100;
pub const PyBUF_FORMAT: i64 = 0x0004;
pub const PyBUF_ND: i64 = 0x0008;
pub const PyBUF_STRIDES: i64 = 0x0010 | PyBUF_ND;
pub const PyBUF_C_CONTIGUOUS: i64 = 0x0020 | PyBUF_STRIDES;
pub const PyBUF_F_CONTIGUOUS: i64 = 0x0040 | PyBUF_STRIDES;
pub const PyBUF_ANY_CONTIGUOUS: i64 = 0x0080 | PyBUF_STRIDES;
pub const PyBUF_INDIRECT: i64 = 0x0100 | PyBUF_STRIDES;
pub const PyBUF_CONTIG: i64 = PyBUF_ND | PyBUF_WRITABLE;
pub const PyBUF_CONTIG_RO: i64 = PyBUF_ND;
pub const PyBUF_STRIDED: i64 = PyBUF_STRIDES | PyBUF_WRITABLE;
pub const PyBUF_STRIDED_RO: i64 = PyBUF_STRIDES;
pub const PyBUF_RECORDS: i64 = PyBUF_STRIDES | PyBUF_WRITABLE | PyBUF_FORMAT;
pub const PyBUF_RECORDS_RO: i64 = PyBUF_STRIDES | PyBUF_FORMAT;
pub const PyBUF_FULL: i64 = PyBUF_INDIRECT | PyBUF_WRITABLE | PyBUF_FORMAT;
pub const PyBUF_FULL_RO: i64 = PyBUF_INDIRECT | PyBUF_FORMAT;

// ndarray flags from _testbuffer.c
pub const ND_MAX_NDIM: i64 = 64;
pub const ND_WRITABLE: i64 = 0x001;
pub const ND_FORTRAN: i64 = 0x002;
pub const ND_PIL: i64 = 0x004;
pub const ND_REDIRECT: i64 = 0x008;
pub const ND_GETBUF_FAIL: i64 = 0x010;
pub const ND_GETBUF_UNDEFINED: i64 = 0x020;
pub const ND_VAREXPORT: i64 = 0x040;

pub const Consts = std.StaticStringMap(h.H).initComptime(.{
    // PyBUF_* constants
    .{ "PyBUF_SIMPLE", genPyBufSimple },
    .{ "PyBUF_WRITABLE", genPyBufWritable },
    .{ "PyBUF_WRITE", genPyBufWrite },
    .{ "PyBUF_READ", genPyBufRead },
    .{ "PyBUF_FORMAT", genPyBufFormat },
    .{ "PyBUF_ND", genPyBufNd },
    .{ "PyBUF_STRIDES", genPyBufStrides },
    .{ "PyBUF_C_CONTIGUOUS", genPyBufCContiguous },
    .{ "PyBUF_F_CONTIGUOUS", genPyBufFContiguous },
    .{ "PyBUF_ANY_CONTIGUOUS", genPyBufAnyContiguous },
    .{ "PyBUF_INDIRECT", genPyBufIndirect },
    .{ "PyBUF_CONTIG", genPyBufContig },
    .{ "PyBUF_CONTIG_RO", genPyBufContigRo },
    .{ "PyBUF_STRIDED", genPyBufStrided },
    .{ "PyBUF_STRIDED_RO", genPyBufStridedRo },
    .{ "PyBUF_RECORDS", genPyBufRecords },
    .{ "PyBUF_RECORDS_RO", genPyBufRecordsRo },
    .{ "PyBUF_FULL", genPyBufFull },
    .{ "PyBUF_FULL_RO", genPyBufFullRo },
    // ND_* constants
    .{ "ND_MAX_NDIM", genNdMaxNdim },
    .{ "ND_WRITABLE", genNdWritable },
    .{ "ND_FORTRAN", genNdFortran },
    .{ "ND_PIL", genNdPil },
    .{ "ND_REDIRECT", genNdRedirect },
    .{ "ND_GETBUF_FAIL", genNdGetbufFail },
    .{ "ND_GETBUF_UNDEFINED", genNdGetbufUndefined },
    .{ "ND_VAREXPORT", genNdVarexport },
    // ndarray class - returns a stub struct
    .{ "ndarray", genNdarray },
    // staticarray for testing
    .{ "staticarray", genStaticarray },
    // get_sizeof_void_p - returns pointer size
    .{ "get_sizeof_void_p", genGetSizeofVoidP },
});

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Note: get_sizeof_void_p is a constant (in Consts), not a function
    // So calls like get_sizeof_void_p() should just use the constant value
});

fn genPyBufSimple(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufWritable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x0001)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufWrite(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x0001)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufRead(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x100)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufFormat(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x0004)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufNd(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x0008)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufStrides(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x0018)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufCContiguous(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x0038)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufFContiguous(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x0058)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufAnyContiguous(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x0098)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufIndirect(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x0118)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufContig(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x0009)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufContigRo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x0008)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufStrided(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x0019)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufStridedRo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x0018)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufRecords(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x001d)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufRecordsRo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x001c)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufFull(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x011d)"), builder_mod.EmitConfig.forExpression());
}

fn genPyBufFullRo(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x011c)"), builder_mod.EmitConfig.forExpression());
}

fn genNdMaxNdim(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(64), builder_mod.EmitConfig.forExpression());
}

fn genNdWritable(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x001)"), builder_mod.EmitConfig.forExpression());
}

fn genNdFortran(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x002)"), builder_mod.EmitConfig.forExpression());
}

fn genNdPil(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x004)"), builder_mod.EmitConfig.forExpression());
}

fn genNdRedirect(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x008)"), builder_mod.EmitConfig.forExpression());
}

fn genNdGetbufFail(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x010)"), builder_mod.EmitConfig.forExpression());
}

fn genNdGetbufUndefined(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x020)"), builder_mod.EmitConfig.forExpression());
}

fn genNdVarexport(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0x040)"), builder_mod.EmitConfig.forExpression());
}

fn genNdarray(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("runtime.TestBuffer.ndarray"), builder_mod.EmitConfig.forExpression());
}

fn genStaticarray(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("runtime.TestBuffer.staticarray"), builder_mod.EmitConfig.forExpression());
}

fn genGetSizeofVoidP(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, @sizeOf(*anyopaque))"), builder_mod.EmitConfig.forExpression());
}

