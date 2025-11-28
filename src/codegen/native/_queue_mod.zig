/// Python _queue module - Internal queue support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _queue.SimpleQueue()
pub fn genSimpleQueue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .items = &[_]@TypeOf(null){} }");
}

/// Generate SimpleQueue.put(item, block=True, timeout=None)
pub fn genPut(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate SimpleQueue.put_nowait(item)
pub fn genPutNowait(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate SimpleQueue.get(block=True, timeout=None)
pub fn genGet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate SimpleQueue.get_nowait()
pub fn genGetNowait(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate SimpleQueue.empty()
pub fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate SimpleQueue.qsize()
pub fn genQsize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}
