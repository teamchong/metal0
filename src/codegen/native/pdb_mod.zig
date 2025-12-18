/// Python pdb module - Python debugger
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Pdb", genPdb },
    .{ "run", genRun },
    .{ "runeval", genRuneval },
    .{ "runcall", genRuncall },
    .{ "set_trace", genSetTrace },
    .{ "post_mortem", genPostMortem },
    .{ "pm", genPm },
    .{ "help", genHelp },
    .{ "Breakpoint", genBreakpoint },
});

fn genPdb(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .skip = @as(?[]const []const u8, null), .nosigint = false }"), builder_mod.EmitConfig.forExpression());
}

fn genRun(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genRuneval(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genRuncall(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genSetTrace(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genPostMortem(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genPm(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genHelp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genBreakpoint(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .file = \"\", .line = @as(i32, 0), .temporary = false, .cond = @as(?[]const u8, null), .funcname = @as(?[]const u8, null), .enabled = true, .ignore = @as(i32, 0), .hits = @as(i32, 0), .number = @as(i32, 0) }"), builder_mod.EmitConfig.forExpression());
}
