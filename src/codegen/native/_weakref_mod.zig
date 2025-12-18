/// Python _weakref module - Weak reference support (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ref", genRef },
    .{ "proxy", genProxy },
    .{ "getweakrefcount", genGetweakrefcount },
    .{ "getweakrefs", genGetweakrefs },
    .{ "CallableProxyType", genCallableProxyType },
    .{ "ProxyType", genProxyType },
    .{ "ReferenceType", genReferenceType },
});

fn genRef(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try b.emitInlineBlockStart("wref");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} .{{ .ptr = @intFromPtr(&__v) }}; ", .{label});
        try b.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .ptr = 0 }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genProxy(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
    }
}

fn genGetweakrefcount(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genGetweakrefs(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(.{}){}"), builder_mod.EmitConfig.forExpression());
}

fn genCallableProxyType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@TypeOf(.{})"), builder_mod.EmitConfig.forExpression());
}

fn genProxyType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@TypeOf(.{})"), builder_mod.EmitConfig.forExpression());
}

fn genReferenceType(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@TypeOf(.{})"), builder_mod.EmitConfig.forExpression());
}
