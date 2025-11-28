/// Python trace module - Trace execution of Python programs
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate trace.Trace class
pub fn genTrace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .count = true, .trace = true, .countfuncs = false, .countcallers = false, .ignoremods = &[_][]const u8{}, .ignoredirs = &[_][]const u8{}, .infile = @as(?[]const u8, null), .outfile = @as(?[]const u8, null) }");
}

/// Generate trace.CoverageResults class
pub fn genCoverageResults(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .counts = @as(?*anyopaque, null), .counter = @as(?*anyopaque, null), .calledfuncs = @as(?*anyopaque, null), .callers = @as(?*anyopaque, null), .infile = @as(?[]const u8, null), .outfile = @as(?[]const u8, null) }");
}
