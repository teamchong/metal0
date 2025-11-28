/// Python _tracemalloc module - Internal tracemalloc support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _tracemalloc.start(nframe=1)
pub fn genStart(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _tracemalloc.stop()
pub fn genStop(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _tracemalloc.is_tracing()
pub fn genIsTracing(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

/// Generate _tracemalloc.clear_traces()
pub fn genClearTraces(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _tracemalloc.get_traceback_limit()
pub fn genGetTracebackLimit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

/// Generate _tracemalloc.get_traced_memory()
pub fn genGetTracedMemory(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i64, 0), @as(i64, 0) }");
}

/// Generate _tracemalloc.reset_peak()
pub fn genResetPeak(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _tracemalloc.get_tracemalloc_memory()
pub fn genGetTracemallocMemory(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate _tracemalloc.get_object_traceback(obj)
pub fn genGetObjectTraceback(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

/// Generate _tracemalloc._get_traces()
pub fn genGetTraces(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}

/// Generate _tracemalloc._get_object_traceback(obj)
pub fn genGetObjectTracebackInternal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}
