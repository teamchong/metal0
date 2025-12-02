/// Python aifc module - AIFF/AIFC file handling
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genOpen }, .{ "Aifc_read", genAifc }, .{ "Aifc_write", genAifc }, .{ "Error", genError },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genAifc(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .nchannels = @as(i32, 0), .sampwidth = @as(i32, 0), .framerate = @as(i32, 0), .nframes = @as(i32, 0), .comptype = \"NONE\", .compname = \"not compressed\" }"); }
fn genError(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.AifcError"); }
fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("blk: { const f = "); try self.genExpr(args[0]); try self.emit("; break :blk .{ .file = f, .mode = \"rb\" }; }"); } else { try self.emit(".{ .file = @as(?*anyopaque, null), .mode = \"rb\" }"); }
}
