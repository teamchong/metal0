/// Python profile/cProfile module - Performance profiling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Profile", genProfile }, .{ "run", genUnit }, .{ "runctx", genUnit },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genProfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .stats = @as(?*anyopaque, null) }"); }
pub fn genCProfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .stats = @as(?*anyopaque, null) }"); }
