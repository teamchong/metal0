/// Python _collections module - C accelerator for collections (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _collections.deque(iterable=(), maxlen=None)
pub fn genDeque(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { var d = std.ArrayList(@TypeOf(");
        try self.genExpr(args[0]);
        try self.emit("[0])).init(__global_allocator); d.appendSlice(");
        try self.genExpr(args[0]);
        try self.emit(") catch {}; break :blk .{ .items = d.items, .maxlen = null }; }");
    } else {
        try self.emit(".{ .items = &[_]@TypeOf(0){}, .maxlen = null }");
    }
}

/// Generate _collections._deque_iterator(deque)
pub fn genDequeIterator(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const d = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .deque = d, .index = 0 }; }");
    } else {
        try self.emit(".{ .deque = null, .index = 0 }");
    }
}

/// Generate _collections._deque_reverse_iterator(deque)
pub fn genDequeReverseIterator(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const d = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk .{ .deque = d, .index = d.items.len }; }");
    } else {
        try self.emit(".{ .deque = null, .index = 0 }");
    }
}

/// Generate _collections._count_elements(mapping, iterable)
pub fn genCountElements(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}
