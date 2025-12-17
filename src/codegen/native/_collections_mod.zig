/// Python _collections module - C accelerator for collections (internal)
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "deque", genDeque },
    .{ "_deque_iterator", genDequeIterator },
    .{ "_deque_reverse_iterator", genDequeReverseIterator },
    .{ "_count_elements", h.c("{}") },
});

fn genDeque(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_deque: {{ var d = std.ArrayListUnmanaged(@TypeOf(", .{id});
        try self.genExpr(args[0]);
        try self.emit("[0])).init(__global_allocator); d.appendSlice(");
        try self.genExpr(args[0]);
        try self.emitFmt(") catch unreachable; break :__m{d}_deque .{{ .items = d.items, .maxlen = null }}; }}", .{id});
    } else {
        try self.emit(".{ .items = &[_]@TypeOf(0){}, .maxlen = null }");
    }
}

fn genDequeIterator(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_deque_iter: {{ const d = ", .{id});
        try self.genExpr(args[0]);
        try self.emitFmt("; break :__m{d}_deque_iter .{{ .deque = d, .index = 0 }}; }}", .{id});
    } else {
        try self.emit(".{ .deque = null, .index = 0 }");
    }
}

fn genDequeReverseIterator(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_deque_riter: {{ const d = ", .{id});
        try self.genExpr(args[0]);
        try self.emitFmt("; break :__m{d}_deque_riter .{{ .deque = d, .index = d.items.len }}; }}", .{id});
    } else {
        try self.emit(".{ .deque = null, .index = 0 }");
    }
}
