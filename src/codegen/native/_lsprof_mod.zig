/// Python _lsprof module - Internal profiler support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "profiler", genConst(".{ .timer = null, .timeunit = 0.0, .subcalls = true, .builtins = true }") }, .{ "enable", genConst("{}") }, .{ "disable", genConst("{}") }, .{ "clear", genConst("{}") },
    .{ "getstats", genConst("&[_]@TypeOf(.{}){}") }, .{ "profiler_entry", genConst(".{ .code = null, .callcount = 0, .reccallcount = 0, .totaltime = 0.0, .inlinetime = 0.0, .calls = null }") },
    .{ "profiler_subentry", genConst(".{ .code = null, .callcount = 0, .reccallcount = 0, .totaltime = 0.0, .inlinetime = 0.0 }") },
});
