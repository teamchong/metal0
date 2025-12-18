/// Python _pickle module - C accelerator for pickle (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "dumps", genDumps },
    .{ "dump", genDump },
    .{ "loads", genLoads },
    .{ "load", genLoad },
    .{ "Pickler", genPickler },
    .{ "Unpickler", genUnpickler },
    .{ "HIGHEST_PROTOCOL", genHighestProtocol },
    .{ "DEFAULT_PROTOCOL", genDefaultProtocol },
    .{ "PickleError", genPickleError },
    .{ "PicklingError", genPicklingError },
    .{ "UnpicklingError", genUnpicklingError },
});

fn genDumps(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.string("\"\""), builder_mod.EmitConfig.forExpression());
        return;
    }
    // Generate: __m{id}_discard: { _ = arg; break :__m{id}_discard ""; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_discard: {{ _ = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; break :__m{d}_discard \"\"; }})", .{id});
}

fn genDump(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genLoads(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
        return;
    }
    // Generate: __m{id}_discard: { _ = arg; break :__m{id}_discard null; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_discard: {{ _ = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; break :__m{d}_discard null; }})", .{id});
}

fn genLoad(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genPickler(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .protocol = 4 }"), builder_mod.EmitConfig.forExpression());
}

fn genUnpickler(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
}

fn genHighestProtocol(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(5), builder_mod.EmitConfig.forExpression());
}

fn genDefaultProtocol(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.int(4), builder_mod.EmitConfig.forExpression());
}

fn genPickleError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.PickleError"), builder_mod.EmitConfig.forExpression());
}

fn genPicklingError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.PicklingError"), builder_mod.EmitConfig.forExpression());
}

fn genUnpicklingError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.UnpicklingError"), builder_mod.EmitConfig.forExpression());
}
