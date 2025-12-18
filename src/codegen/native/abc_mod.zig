/// Python abc module - Abstract Base Classes
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ABC", genABC },
    .{ "ABCMeta", genABCMeta },
    .{ "abstractmethod", genAbstractmethod },
    .{ "abstractclassmethod", genAbstractmethod },
    .{ "abstractstaticmethod", genAbstractmethod },
    .{ "abstractproperty", genAbstractmethod },
    .{ "get_cache_token", genGetCacheToken },
    .{ "update_abstractmethods", genUpdateAbstractmethods },
});

fn genABC(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { _is_abc: bool = true }{}"), builder_mod.EmitConfig.forExpression());
}

fn genABCMeta(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("ABCMeta"), builder_mod.EmitConfig.forExpression());
}

fn genAbstractmethod(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("struct { _is_abstract: bool = true }{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genGetCacheToken(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genUpdateAbstractmethods(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("void{}"), builder_mod.EmitConfig.forExpression());
    }
}
