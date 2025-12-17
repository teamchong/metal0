/// Python dbm module - Interfaces to Unix databases
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", genOpen },
    .{ "error", genError },
    .{ "whichdb", genWhichdb },
});

fn genOpen(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        // With argument: .{ .path = __v, .data = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }
        try self.emit(".{ .path = ");
        try self.genExpr(args[0]);
        try self.emit(", .data = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }");
    } else {
        // Without argument: default struct
        const b = try self.getBuilder();
        try b.emitValue(builder_mod.ZigValue.raw(".{ .path = \"\", .data = hashmap_helper.StringHashMap([]const u8).init(__global_allocator) }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.DbmError"), builder_mod.EmitConfig.forExpression());
}

fn genWhichdb(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?[]const u8, \"dbm.dumb\")"), builder_mod.EmitConfig.forExpression());
}
