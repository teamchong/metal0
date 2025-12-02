/// Python trace module - Trace execution of Python programs
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Trace", genTrace }, .{ "CoverageResults", genCoverageResults },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genTrace(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .count = true, .trace = true, .countfuncs = false, .countcallers = false, .ignoremods = &[_][]const u8{}, .ignoredirs = &[_][]const u8{}, .infile = @as(?[]const u8, null), .outfile = @as(?[]const u8, null) }"); }
fn genCoverageResults(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .counts = @as(?*anyopaque, null), .counter = @as(?*anyopaque, null), .calledfuncs = @as(?*anyopaque, null), .callers = @as(?*anyopaque, null), .infile = @as(?[]const u8, null), .outfile = @as(?[]const u8, null) }"); }
