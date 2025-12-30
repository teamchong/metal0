/// Python numbers module - Numeric abstract base classes
/// Emits runtime.NumbersABC enum values for use with issubclass()
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Number", genNumber },
    .{ "Complex", genComplex },
    .{ "Real", genReal },
    .{ "Rational", genRational },
    .{ "Integral", genIntegral },
});

fn genNumber(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("runtime.NumbersABC.Number"), builder_mod.EmitConfig.forExpression());
}

fn genComplex(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("runtime.NumbersABC.Complex"), builder_mod.EmitConfig.forExpression());
}

fn genReal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("runtime.NumbersABC.Real"), builder_mod.EmitConfig.forExpression());
}

fn genRational(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("runtime.NumbersABC.Rational"), builder_mod.EmitConfig.forExpression());
}

fn genIntegral(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("runtime.NumbersABC.Integral"), builder_mod.EmitConfig.forExpression());
}
