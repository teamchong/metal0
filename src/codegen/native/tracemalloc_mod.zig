/// Python tracemalloc module - Trace memory allocations
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "false"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "start", genUnit }, .{ "stop", genUnit }, .{ "is_tracing", genFalse }, .{ "clear_traces", genUnit },
    .{ "get_object_traceback", genNull }, .{ "get_traceback_limit", genTracebackLimit },
    .{ "get_traced_memory", genTracedMemory }, .{ "reset_peak", genUnit }, .{ "get_tracemalloc_memory", genZero },
    .{ "take_snapshot", genSnapshot }, .{ "Snapshot", genSnapshot },
    .{ "Statistic", genStatistic }, .{ "StatisticDiff", genStatisticDiff },
    .{ "Trace", genTrace }, .{ "Traceback", genTraceback }, .{ "Frame", genFrame },
    .{ "Filter", genFilter }, .{ "DomainFilter", genDomainFilter },
});

fn genTracebackLimit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genTracedMemory(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i64, 0), @as(i64, 0) }"); }
fn genZero(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }
fn genSnapshot(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .traces = &[_]@TypeOf(.{}){} }"); }
fn genStatistic(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .traceback = null, .size = 0, .count = 0 }"); }
fn genStatisticDiff(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .traceback = null, .size = 0, .size_diff = 0, .count = 0, .count_diff = 0 }"); }
fn genTrace(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .traceback = null, .size = 0 }"); }
fn genTraceback(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .frames = &[_]@TypeOf(.{}){} }"); }
fn genFrame(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .filename = \"\", .lineno = 0 }"); }
fn genFilter(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .inclusive = true, .filename_pattern = \"*\", .lineno = null, .all_frames = false, .domain = null }"); }
fn genDomainFilter(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .inclusive = true, .domain = 0 }"); }
