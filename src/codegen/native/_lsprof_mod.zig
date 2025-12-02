/// Python _lsprof module - Internal profiler support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "profiler", genProfiler }, .{ "enable", genUnit }, .{ "disable", genUnit }, .{ "clear", genUnit }, .{ "getstats", genStats }, .{ "profiler_entry", genEntry }, .{ "profiler_subentry", genSubentry },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genStats(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]@TypeOf(.{}){}"); }
fn genProfiler(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .timer = null, .timeunit = 0.0, .subcalls = true, .builtins = true }"); }
fn genEntry(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .code = null, .callcount = 0, .reccallcount = 0, .totaltime = 0.0, .inlinetime = 0.0, .calls = null }"); }
fn genSubentry(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .code = null, .callcount = 0, .reccallcount = 0, .totaltime = 0.0, .inlinetime = 0.0 }"); }
