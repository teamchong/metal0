/// Python antigravity module - Easter egg (opens xkcd comic)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate antigravity (just importing opens browser to xkcd)
pub fn genInit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate antigravity.geohash(latitude, longitude, dession)
pub fn genGeohash(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 0.0)");
}
