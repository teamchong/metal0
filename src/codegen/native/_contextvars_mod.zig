/// Python _contextvars module - Internal contextvars support (C accelerator)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "context_var", genContextVar },
    .{ "context", genContext },
    .{ "token", genToken },
    .{ "copy_context", genCopyContext },
    .{ "get", genGet },
    .{ "set", genSet },
    .{ "reset", genReset },
    .{ "run", genRun },
    .{ "copy", genCopy },
});

fn genContextVar(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .name = \"\", .default = null }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    // Generate: __m{id}_cvi: { const __v = arg; break :__m{id}_cvi .{ .name = __v, .default = null }; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_cvi: {{ const __v = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; break :__m{d}_cvi .{{ .name = __v, .default = null }}; }})", .{id});
}

fn genContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genToken(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .var = null, .old_value = null, .used = false }"), builder_mod.EmitConfig.forExpression());
}

fn genCopyContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genGet(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genSet(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .var = null, .old_value = null, .used = false }"), builder_mod.EmitConfig.forExpression());
}

fn genReset(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genRun(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genCopy(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}
