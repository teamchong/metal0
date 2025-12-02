/// Python runpy module - Run Python modules
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "run_module", genRun_module },
    .{ "run_path", genRun_path },
});

// Note: These are AOT-limited since they involve dynamic execution

/// Generate runpy.run_module(mod_name, run_name=None, alter_sys=False)
pub fn genRun_module(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate runpy.run_path(path_name, run_name=None, alter_sys=False)
pub fn genRun_path(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}
