/// Python _struct module - C accelerator for struct (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "pack", genPack },
    .{ "pack_into", genPackInto },
    .{ "unpack", genUnpack },
    .{ "unpack_from", genUnpackFrom },
    .{ "iter_unpack", genIterUnpack },
    .{ "calcsize", genCalcsize },
    .{ "Struct", genStruct },
    .{ "error", genError },
});

fn genPack(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try b.emitInlineBlockStart("pk");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = __v; var _result: std.ArrayList(u8) = .{{}}; break :");
        try self.emitFmt("{s} _result.items; ", .{label});
        try b.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}

fn genPackInto(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genUnpack(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        const label = try b.emitInlineBlockStart("unp");
        try self.emit("const __v0 = ");
        try self.genExpr(args[0]);
        try self.emit("; const __v1 = ");
        try self.genExpr(args[1]);
        try self.emit("; _ = __v0; _ = __v1; break :");
        try self.emitFmt("{s} .{{}}; ", .{label});
        try b.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genUnpackFrom(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        const label = try b.emitInlineBlockStart("unpf");
        try self.emit("const __v0 = ");
        try self.genExpr(args[0]);
        try self.emit("; const __v1 = ");
        try self.genExpr(args[1]);
        try self.emit("; _ = __v0; _ = __v1; break :");
        try self.emitFmt("{s} .{{}}; ", .{label});
        try b.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genIterUnpack(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]@TypeOf(.{}){}"), builder_mod.EmitConfig.forExpression());
}

fn genCalcsize(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try b.emitInlineBlockStart("csz");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emit("; var _size: i64 = 0; for (__v) |c| {{ switch (c) {{ 'b', 'B', 'c', '?', 's', 'p' => _size += 1, 'h', 'H' => _size += 2, 'i', 'I', 'l', 'L', 'f' => _size += 4, 'q', 'Q', 'd' => _size += 8, else => {{}}, }} }} break :");
        try self.emitFmt("{s} _size; ", .{label});
        try b.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genStruct(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const label = try b.emitInlineBlockStart("st");
        try self.emit("const __v = ");
        try self.genExpr(args[0]);
        try self.emitFmt("; break :{s} .{{ .format = __v, .size = 0 }}; ", .{label});
        try b.emitInlineBlockEnd();
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .format = \"\", .size = 0 }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.StructError"), builder_mod.EmitConfig.forExpression());
}
