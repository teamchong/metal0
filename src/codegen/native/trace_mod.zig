/// Python trace module - Trace execution of Python programs
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Trace", genConst(".{ .count = true, .trace = true, .countfuncs = false, .countcallers = false, .ignoremods = &[_][]const u8{}, .ignoredirs = &[_][]const u8{}, .infile = @as(?[]const u8, null), .outfile = @as(?[]const u8, null) }") },
    .{ "CoverageResults", genConst(".{ .counts = @as(?*anyopaque, null), .counter = @as(?*anyopaque, null), .calledfuncs = @as(?*anyopaque, null), .callers = @as(?*anyopaque, null), .infile = @as(?[]const u8, null), .outfile = @as(?[]const u8, null) }") },
});
