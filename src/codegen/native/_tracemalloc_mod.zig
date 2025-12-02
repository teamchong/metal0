/// Python _tracemalloc module - Internal tracemalloc support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "start", genConst("{}") }, .{ "stop", genConst("{}") }, .{ "is_tracing", genConst("false") }, .{ "clear_traces", genConst("{}") },
    .{ "get_traceback_limit", genConst("@as(i32, 1)") }, .{ "get_traced_memory", genConst(".{ @as(i64, 0), @as(i64, 0) }") }, .{ "reset_peak", genConst("{}") },
    .{ "get_tracemalloc_memory", genConst("@as(i64, 0)") }, .{ "get_object_traceback", genConst("null") }, .{ "get_traces", genConst("&[_]@TypeOf(.{}){}") },
    .{ "get_object_traceback_internal", genConst("null") },
});
