/// Python sunau module - Sun AU audio file handling
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "open", genOpen }, .{ "Au_read", h.c(".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }") },
    .{ "Au_write", h.c(".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }") },
    .{ "AUDIO_FILE_MAGIC", h.I32(0x2e736e64) },
    .{ "AUDIO_FILE_ENCODING_MULAW_8", h.I32(1) }, .{ "AUDIO_FILE_ENCODING_LINEAR_8", h.I32(2) },
    .{ "AUDIO_FILE_ENCODING_LINEAR_16", h.I32(3) }, .{ "AUDIO_FILE_ENCODING_LINEAR_24", h.I32(4) },
    .{ "AUDIO_FILE_ENCODING_LINEAR_32", h.I32(5) }, .{ "AUDIO_FILE_ENCODING_FLOAT", h.I32(6) },
    .{ "AUDIO_FILE_ENCODING_DOUBLE", h.I32(7) }, .{ "AUDIO_FILE_ENCODING_ALAW_8", h.I32(27) },
    .{ "Error", h.err("SunauError") },
});

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const f = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .file = f, .mode = \"rb\" }; }"); }
    else try self.emit(".{ .file = @as(?*anyopaque, null), .mode = \"rb\" }");
}
