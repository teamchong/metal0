/// Python _collections module - C accelerator for collections (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "deque", genDeque },
    .{ "_deque_iterator", genDequeIterator },
    .{ "_deque_reverse_iterator", genDequeReverseIterator },
    .{ "_count_elements", genCountElements },
});

fn genDeque(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try b.emitInlineBlockStart("deque");
        try self.emit("var d = std.ArrayListUnmanaged(@TypeOf(");
        try self.genExpr(args[0]);
        try self.emit("[0])).init(__global_allocator); d.appendSlice(");
        try self.genExpr(args[0]);
        try self.emitFmt(") catch unreachable; break :{s} .{{ .items = d.items, .maxlen = null }}; ", .{label});
        try b.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .items = &[_]@TypeOf(0){}, .maxlen = null }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genDequeIterator(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try b.emitInlineBlockStart("diter");
        try self.emit("const d = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} .{{ .deque = d, .index = 0 }}; ", .{label});
        try b.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .deque = null, .index = 0 }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genDequeReverseIterator(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try b.emitInlineBlockStart("driter");
        try self.emit("const d = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} .{{ .deque = d, .index = d.items.len }}; ", .{label});
        try b.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .deque = null, .index = 0 }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genCountElements(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}
