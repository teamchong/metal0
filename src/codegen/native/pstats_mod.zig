/// Python pstats module - Statistics object for the profiler
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Stats", genStats }, .{ "SortKey", genSortKey }, .{ "strip_dirs", genEmpty }, .{ "add", genEmpty },
    .{ "dump_stats", genUnit }, .{ "sort_stats", genEmpty }, .{ "reverse_order", genEmpty },
    .{ "print_stats", genEmpty }, .{ "print_callers", genEmpty }, .{ "print_callees", genEmpty },
    .{ "get_stats_profile", genStatsProfile }, .{ "FunctionProfile", genFunctionProfile }, .{ "StatsProfile", genStatsProfile },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }
fn genStats(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .stats = .{}, .total_calls = 0, .prim_calls = 0, .total_tt = 0.0, .stream = null }"); }
fn genSortKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .CALLS = 0, .CUMULATIVE = 1, .FILENAME = 2, .LINE = 3, .NAME = 4, .NFL = 5, .PCALLS = 6, .STDNAME = 7, .TIME = 8 }"); }
fn genStatsProfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .total_tt = 0.0, .func_profiles = .{} }"); }
fn genFunctionProfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .ncalls = 0, .tottime = 0.0, .percall_tottime = 0.0, .cumtime = 0.0, .percall_cumtime = 0.0, .file_name = \"\", .line_number = 0 }"); }
