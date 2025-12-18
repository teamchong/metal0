/// Python chunk module - Read IFF chunked data
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Chunk", genChunk },
    .{ "getname", genGetname },
    .{ "getsize", genGetsize },
    .{ "close", genClose },
    .{ "isatty", genIsatty },
    .{ "seek", genSeek },
    .{ "tell", genTell },
    .{ "read", genRead },
    .{ "skip", genSkip },
});

fn genChunk(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_chunk: {{ const __v = ", .{id});
        try self.genExpr(args[0]);
        try self.emit("; _ = __v;");
        try self.emitFmt(" break :__m{d}_chunk .{{ .closed = false, .align = true, .bigendian = true, .inclheader = false, .chunkname = &[_]u8{{0}} ** 4, .chunksize = 0, .size_read = 0 }}; }})", .{id});
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .closed = false, .align = true, .bigendian = true, .inclheader = false, .chunkname = &[_]u8{0} ** 4, .chunksize = 0, .size_read = 0 }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genGetname(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genGetsize(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genClose(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genIsatty(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.boolean(false), builder_mod.EmitConfig.forExpression());
}

fn genSeek(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genTell(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 0)"), builder_mod.EmitConfig.forExpression());
}

fn genRead(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
}

fn genSkip(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}
