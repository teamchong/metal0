/// Python aifc module - AIFF/AIFC file handling
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", genOpen },
    .{ "Error", genError },
    .{ "Aifc_read", genAifcRead },
    .{ "Aifc_write", genAifcWrite },
});

fn genOpen(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.withInlineBlock("aifc", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v = ");
                try c.genExpr(a[0]);
                try c.emitFmt("; break :{s} .{{ .file = __v, .mode = \"rb\" }}", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .file = @as(?*anyopaque, null), .mode = \"rb\" }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.AifcError"), builder_mod.EmitConfig.forExpression());
}

fn genAifcRead(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }"), builder_mod.EmitConfig.forExpression());
}

fn genAifcWrite(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }"), builder_mod.EmitConfig.forExpression());
}
