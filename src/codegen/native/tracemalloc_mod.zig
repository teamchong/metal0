/// Python tracemalloc module - Trace memory allocations
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
    .{ "get_object_traceback", genConst("null") }, .{ "get_traceback_limit", genConst("@as(i32, 1)") },
    .{ "get_traced_memory", genConst(".{ @as(i64, 0), @as(i64, 0) }") }, .{ "reset_peak", genConst("{}") }, .{ "get_tracemalloc_memory", genConst("@as(i64, 0)") },
    .{ "take_snapshot", genConst(".{ .traces = &[_]@TypeOf(.{}){} }") }, .{ "Snapshot", genConst(".{ .traces = &[_]@TypeOf(.{}){} }") },
    .{ "Statistic", genConst(".{ .traceback = null, .size = 0, .count = 0 }") },
    .{ "StatisticDiff", genConst(".{ .traceback = null, .size = 0, .size_diff = 0, .count = 0, .count_diff = 0 }") },
    .{ "Trace", genConst(".{ .traceback = null, .size = 0 }") },
    .{ "Traceback", genConst(".{ .frames = &[_]@TypeOf(.{}){} }") },
    .{ "Frame", genConst(".{ .filename = \"\", .lineno = 0 }") },
    .{ "Filter", genConst(".{ .inclusive = true, .filename_pattern = \"*\", .lineno = null, .all_frames = false, .domain = null }") },
    .{ "DomainFilter", genConst(".{ .inclusive = true, .domain = 0 }") },
});
