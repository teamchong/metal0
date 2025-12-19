/// Python _struct module - C accelerator for struct (internal)
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
        try self.withInlineBlock("pk", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitConst(c, "; _ = __v; var _result: std.ArrayList(u8) = .{{}}; break :");
                try emitFmtConst(c, "{s} _result.items; ", .{label});
            }
        }.emit);
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
        try self.withInlineBlock("unp", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v0 = ");
                try c.genExpr(a[0]);
                try emitConst(c, "; const __v1 = ");
                try c.genExpr(a[1]);
                try emitConst(c, "; _ = __v0; _ = __v1; break :");
                try emitFmtConst(c, "{s} .{{}}; ", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
    }
}

fn genUnpackFrom(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        try self.withInlineBlock("unpf", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v0 = ");
                try c.genExpr(a[0]);
                try emitConst(c, "; const __v1 = ");
                try c.genExpr(a[1]);
                try emitConst(c, "; _ = __v0; _ = __v1; break :");
                try emitFmtConst(c, "{s} .{{}}; ", .{label});
            }
        }.emit);
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
        try self.withInlineBlock("csz", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitConst(c, "; var _size: i64 = 0; for (__v) |c| {{ switch (c) {{ 'b', 'B', 'c', '?', 's', 'p' => _size += 1, 'h', 'H' => _size += 2, 'i', 'I', 'l', 'L', 'f' => _size += 4, 'q', 'Q', 'd' => _size += 8, else => {{}}, }} }} break :");
                try emitFmtConst(c, "{s} _size; ", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
    }
}

fn genStruct(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.withInlineBlock("st", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try emitConst(c, "const __v = ");
                try c.genExpr(a[0]);
                try emitFmtConst(c, "; break :{s} .{{ .format = __v, .size = 0 }}; ", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .format = \"\", .size = 0 }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.StructError"), builder_mod.EmitConfig.forExpression());
}
