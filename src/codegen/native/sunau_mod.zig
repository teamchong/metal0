/// Python sunau module - Sun AU audio file handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genI32(comptime n: comptime_int) fn (*NativeCodegen, []ast.Node) CodegenError!void {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, std.fmt.comptimePrint("@as(i32, {})", .{n})); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genOpen }, .{ "Au_read", genAuRead }, .{ "Au_write", genAuRead },
    .{ "AUDIO_FILE_MAGIC", genI32(0x2e736e64) },
    .{ "AUDIO_FILE_ENCODING_MULAW_8", genI32(1) }, .{ "AUDIO_FILE_ENCODING_LINEAR_8", genI32(2) },
    .{ "AUDIO_FILE_ENCODING_LINEAR_16", genI32(3) }, .{ "AUDIO_FILE_ENCODING_LINEAR_24", genI32(4) },
    .{ "AUDIO_FILE_ENCODING_LINEAR_32", genI32(5) }, .{ "AUDIO_FILE_ENCODING_FLOAT", genI32(6) },
    .{ "AUDIO_FILE_ENCODING_DOUBLE", genI32(7) }, .{ "AUDIO_FILE_ENCODING_ALAW_8", genI32(27) },
    .{ "Error", genError },
});

fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.emit("blk: { const f = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .file = f, .mode = \"rb\" }; }"); } else try self.emit(".{ .file = @as(?*anyopaque, null), .mode = \"rb\" }"); }
fn genAuRead(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }"); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.SunauError"); }
