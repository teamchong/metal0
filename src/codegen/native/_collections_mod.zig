/// Python _collections module - C accelerator for collections (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "deque", genDeque }, .{ "_deque_iterator", genDequeIter }, .{ "_deque_reverse_iterator", genDequeRevIter }, .{ "_count_elements", genUnit },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genDeque(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { var d = std.ArrayList(@TypeOf("); try self.genExpr(args[0]); try self.emit("[0])).init(__global_allocator); d.appendSlice("); try self.genExpr(args[0]); try self.emit(") catch {}; break :blk .{ .items = d.items, .maxlen = null }; }"); } else { try self.emit(".{ .items = &[_]@TypeOf(0){}, .maxlen = null }"); }
}
fn genDequeIter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const d = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .deque = d, .index = 0 }; }"); } else { try self.emit(".{ .deque = null, .index = 0 }"); }
}
fn genDequeRevIter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const d = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .deque = d, .index = d.items.len }; }"); } else { try self.emit(".{ .deque = null, .index = 0 }"); }
}
