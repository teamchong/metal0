/// Python contextvars module - Context Variables
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ContextVar", genContextVar },
    .{ "Token", genToken },
    .{ "Context", genContext },
    .{ "copy_context", genCopyContext },
});

fn genContextVar(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const default = ".{ .name = \"\", .value = null }";
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw(default), builder_mod.EmitConfig.forExpression());
        return;
    }
    const label = try self.emitInlineBlockStart("cv");
    try self.emit("const __v = ");
    try self.genExpr(args[0]);
    try self.emitFmt("; break :{s} .{{ .name = __v, .value = null }}; ", .{label});
    try self.emitInlineBlockEnd();
}

fn genToken(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .var = null, .old_value = null }"), builder_mod.EmitConfig.forExpression());
}

fn genContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .data = hashmap_helper.StringHashMap(?*anyopaque).init(__global_allocator) }"), builder_mod.EmitConfig.forExpression());
}

fn genCopyContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .data = hashmap_helper.StringHashMap(?*anyopaque).init(__global_allocator) }"), builder_mod.EmitConfig.forExpression());
}
