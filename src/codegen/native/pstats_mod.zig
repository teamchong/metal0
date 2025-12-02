/// Python pstats module - Statistics object for the profiler
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Stats", genConst(".{ .stats = .{}, .total_calls = 0, .prim_calls = 0, .total_tt = 0.0, .stream = null }") },
    .{ "SortKey", genConst(".{ .CALLS = 0, .CUMULATIVE = 1, .FILENAME = 2, .LINE = 3, .NAME = 4, .NFL = 5, .PCALLS = 6, .STDNAME = 7, .TIME = 8 }") },
    .{ "strip_dirs", genConst(".{}") }, .{ "add", genConst(".{}") },
    .{ "dump_stats", genConst("{}") }, .{ "sort_stats", genConst(".{}") }, .{ "reverse_order", genConst(".{}") },
    .{ "print_stats", genConst(".{}") }, .{ "print_callers", genConst(".{}") }, .{ "print_callees", genConst(".{}") },
    .{ "get_stats_profile", genConst(".{ .total_tt = 0.0, .func_profiles = .{} }") },
    .{ "FunctionProfile", genConst(".{ .ncalls = 0, .tottime = 0.0, .percall_tottime = 0.0, .cumtime = 0.0, .percall_cumtime = 0.0, .file_name = \"\", .line_number = 0 }") },
    .{ "StatsProfile", genConst(".{ .total_tt = 0.0, .func_profiles = .{} }") },
});
