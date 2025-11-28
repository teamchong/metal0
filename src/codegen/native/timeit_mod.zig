/// Python timeit module - Measure execution time
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate timeit.timeit(stmt='pass', setup='pass', timer=<default>, number=1000000, globals=None)
pub fn genTimeit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 0.0)");
}

/// Generate timeit.repeat(stmt='pass', setup='pass', timer=<default>, repeat=5, number=1000000, globals=None)
pub fn genRepeat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]f64{}");
}

/// Generate timeit.default_timer() - return current time
pub fn genDefault_timer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, @floatFromInt(std.time.nanoTimestamp())) / 1_000_000_000.0");
}

/// Generate timeit.Timer class
pub fn genTimer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .stmt = \"pass\", .setup = \"pass\", .timer = @as(?*const fn () f64, null), .globals = @as(?*anyopaque, null) }");
}
