/// Python bz2 module - Bzip2 compression library
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "compress", genPassthrough }, .{ "decompress", genPassthrough }, .{ "open", h.c("@as(?*anyopaque, null)") }, .{ "BZ2File", h.c("@as(?*anyopaque, null)") },
    .{ "BZ2Compressor", h.c(".{ .compress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .flush = struct { fn f() []const u8 { return \"\"; } }.f }") },
    .{ "BZ2Decompressor", h.c(".{ .decompress = struct { fn f(data: []const u8) []const u8 { return data; } }.f, .eof = true, .needs_input = false, .unused_data = \"\" }") },
});

fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) { try self.genExpr(args[0]); } else { try self.emit("\"\""); } }
