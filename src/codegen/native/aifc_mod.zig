/// Python aifc module - AIFF/AIFC file handling
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", genOpen }, .{ "Error", h.err("AifcError") },
    .{ "Aifc_read", h.c(".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }") },
    .{ "Aifc_write", h.c(".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }") },
});

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const f = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .file = f, .mode = \"rb\" }; }"); } else { try self.emit(".{ .file = @as(?*anyopaque, null), .mode = \"rb\" }"); }
}
