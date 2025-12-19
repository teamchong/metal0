/// Python _weakref module - Weak reference support (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output - uses h.NativeCodegen from mod_helper
fn emitConst(self: *h.NativeCodegen, val: []const u8) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *h.NativeCodegen, comptime fmt: []const u8, args: anytype) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}



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
        try self.withInlineBlock("wref", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitFmtConst(c, "; break :{s} .{{ .ptr = @intFromPtr(&__v) }}", .{label});
            }
        }.emit);
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
