/// Python sndhdr module - Sound file type determination
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "what", genWhat },
    .{ "whathdr", genWhathdr },
    .{ "SndHeaders", genSndHeaders },
    .{ "tests", genTests },
});

fn genWhat(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?@TypeOf(.{ .filetype = \"\", .framerate = @as(i32, 0), .nchannels = @as(i32, 0), .nframes = @as(i32, -1), .sampwidth = @as(i32, 0) }), null)"), builder_mod.EmitConfig.forExpression());
}

fn genWhathdr(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?@TypeOf(.{ .filetype = \"\", .framerate = @as(i32, 0), .nchannels = @as(i32, 0), .nframes = @as(i32, -1), .sampwidth = @as(i32, 0) }), null)"), builder_mod.EmitConfig.forExpression());
}

fn genSndHeaders(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .filetype = \"\", .framerate = @as(i32, 0), .nchannels = @as(i32, 0), .nframes = @as(i32, -1), .sampwidth = @as(i32, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genTests(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]*const fn ([]const u8, *anyopaque) ?@TypeOf(.{ .filetype = \"\", .framerate = @as(i32, 0), .nchannels = @as(i32, 0), .nframes = @as(i32, -1), .sampwidth = @as(i32, 0) }){}"), builder_mod.EmitConfig.forExpression());
}
