/// Python trace module - Trace execution of Python programs
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Trace", genTrace },
    .{ "CoverageResults", genCoverageResults },
});

fn genTrace(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .count = true, .trace = true, .countfuncs = false, .countcallers = false, .ignoremods = &[_][]const u8{}, .ignoredirs = &[_][]const u8{}, .infile = @as(?[]const u8, null), .outfile = @as(?[]const u8, null) }"), builder_mod.EmitConfig.forExpression());
}

fn genCoverageResults(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .counts = @as(?*anyopaque, null), .counter = @as(?*anyopaque, null), .calledfuncs = @as(?*anyopaque, null), .callers = @as(?*anyopaque, null), .infile = @as(?[]const u8, null), .outfile = @as(?[]const u8, null) }"), builder_mod.EmitConfig.forExpression());
}
