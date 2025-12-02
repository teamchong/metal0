/// Python _collections module - C accelerator for collections (internal)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "deque", genDeque }, .{ "_deque_iterator", genDequeIter }, .{ "_deque_reverse_iterator", genDequeRevIter }, .{ "_count_elements", h.c("{}") },
});

fn genDeque(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { var d = std.ArrayList(@TypeOf("); try self.genExpr(args[0]); try self.emit("[0])).init(__global_allocator); d.appendSlice("); try self.genExpr(args[0]); try self.emit(") catch {}; break :blk .{ .items = d.items, .maxlen = null }; }"); } else { try self.emit(".{ .items = &[_]@TypeOf(0){}, .maxlen = null }"); }
}
fn genDequeIter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const d = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .deque = d, .index = 0 }; }"); } else { try self.emit(".{ .deque = null, .index = 0 }"); }
}
fn genDequeRevIter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const d = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .deque = d, .index = d.items.len }; }"); } else { try self.emit(".{ .deque = null, .index = 0 }"); }
}
