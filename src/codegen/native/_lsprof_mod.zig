/// Python _lsprof module - Internal profiler support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _lsprof.Profiler(timer=None, timeunit=None, subcalls=True, builtins=True)
pub fn genProfiler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .timer = null, .timeunit = 0.0, .subcalls = true, .builtins = true }");
}

/// Generate Profiler.enable(subcalls=True, builtins=True)
pub fn genEnable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Profiler.disable()
pub fn genDisable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Profiler.clear()
pub fn genClear(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Profiler.getstats()
pub fn genGetstats(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]@TypeOf(.{}){}");
}

/// Generate profiler_entry type
pub fn genProfilerEntry(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .code = null, .callcount = 0, .reccallcount = 0, .totaltime = 0.0, .inlinetime = 0.0, .calls = null }");
}

/// Generate profiler_subentry type
pub fn genProfilerSubentry(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .code = null, .callcount = 0, .reccallcount = 0, .totaltime = 0.0, .inlinetime = 0.0 }");
}
