/// Python _abc module - Internal ABC support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "get_cache_token", genGetCacheToken },
    .{ "_abc_init", genAbcInit },
    .{ "_abc_register", genAbcRegister },
    .{ "_abc_instancecheck", genAbcInstancecheck },
    .{ "_abc_subclasscheck", genAbcSubclasscheck },
    .{ "_get_dump", genGetDump },
    .{ "_reset_registry", genResetRegistry },
    .{ "_reset_caches", genResetCaches },
});

fn genGetCacheToken(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(u64, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genAbcInit(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genAbcRegister(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        const b = try self.getBuilder();
        try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
    }
}

fn genAbcInstancecheck(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genAbcSubclasscheck(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genGetDump(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ &[_]type{}, &[_]type{}, &[_]type{} }"), builder_mod.EmitConfig.forExpression());
}

fn genResetRegistry(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genResetCaches(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}
