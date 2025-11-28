/// Python pstats module - Statistics object for the profiler
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate pstats.Stats(*filenames, stream=sys.stdout)
pub fn genStats(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .stats = .{}, .total_calls = 0, .prim_calls = 0, .total_tt = 0.0, .stream = null }");
}

/// Generate pstats.SortKey enum
pub fn genSortKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .CALLS = 0, .CUMULATIVE = 1, .FILENAME = 2, .LINE = 3, .NAME = 4, .NFL = 5, .PCALLS = 6, .STDNAME = 7, .TIME = 8 }");
}

/// Generate Stats.strip_dirs()
pub fn genStripDirs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate Stats.add(*filenames)
pub fn genAdd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate Stats.dump_stats(filename)
pub fn genDumpStats(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate Stats.sort_stats(*keys)
pub fn genSortStats(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate Stats.reverse_order()
pub fn genReverseOrder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate Stats.print_stats(*restrictions)
pub fn genPrintStats(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate Stats.print_callers(*restrictions)
pub fn genPrintCallers(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate Stats.print_callees(*restrictions)
pub fn genPrintCallees(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate Stats.get_stats_profile()
pub fn genGetStatsProfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .total_tt = 0.0, .func_profiles = .{} }");
}

/// Generate pstats.FunctionProfile class
pub fn genFunctionProfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .ncalls = 0, .tottime = 0.0, .percall_tottime = 0.0, .cumtime = 0.0, .percall_cumtime = 0.0, .file_name = \"\", .line_number = 0 }");
}

/// Generate pstats.StatsProfile class
pub fn genStatsProfile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .total_tt = 0.0, .func_profiles = .{} }");
}
