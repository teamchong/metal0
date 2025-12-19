/// Python _pickle module - C accelerator for pickle (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output - uses h.NativeCodegen from mod_helper
fn emitConst(self: *h.NativeCodegen, val: []const u8) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *h.NativeCodegen, comptime fmt: []const u8, args: anytype) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}



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
    try self.withInlineBlock("discard", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "_ = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; break :{s} \"\"", .{label});
        }
    }.emit);
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
    try self.withInlineBlock("discard", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "_ = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; break :{s} null", .{label});
        }
    }.emit);
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
