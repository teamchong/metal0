/// Python _statistics module - Internal statistics support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "normal_dist_inv_cdf", genNormalDistInvCdf },
});

/// Generate _statistics._normal_dist_inv_cdf(p, mu, sigma)
pub fn genNormalDistInvCdf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(f64, 0.0)");
}
