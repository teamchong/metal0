/// Python _typing module - Internal typing support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "_idfunc", genIdfunc },
    .{ "TypeVar", genTypeVar },
    .{ "ParamSpec", genParamSpec },
    .{ "TypeVarTuple", genTypeVarTuple },
    .{ "ParamSpecArgs", genParamSpecArgs },
    .{ "ParamSpecKwargs", genParamSpecKwargs },
    .{ "Generic", genGeneric },
});

fn genIdfunc(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
    }
}

fn genTypeVar(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .__name__ = \"\", .__bound__ = null, .__constraints__ = &[_]type{}, .__covariant__ = false, .__contravariant__ = false }"), builder_mod.EmitConfig.forExpression());
}

fn genParamSpec(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .__name__ = \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genTypeVarTuple(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .__name__ = \"\" }"), builder_mod.EmitConfig.forExpression());
}

fn genParamSpecArgs(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .__origin__ = null }"), builder_mod.EmitConfig.forExpression());
}

fn genParamSpecKwargs(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .__origin__ = null }"), builder_mod.EmitConfig.forExpression());
}

fn genGeneric(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}
