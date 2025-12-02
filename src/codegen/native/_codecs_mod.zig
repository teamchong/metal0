/// Python _codecs module - C accelerator for codecs (internal)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "encode", h.pass("\"\"") }, .{ "decode", h.pass("\"\"") },
    .{ "register", h.c("{}") }, .{ "lookup", h.c(".{ .encode = null, .decode = null, .streamreader = null, .streamwriter = null }") },
    .{ "register_error", h.c("{}") }, .{ "lookup_error", h.c("null") },
    .{ "utf_8_encode", genCodecResult }, .{ "utf_8_decode", genCodecResult },
    .{ "ascii_encode", genCodecResult }, .{ "ascii_decode", genCodecResult },
    .{ "latin_1_encode", genCodecResult }, .{ "latin_1_decode", genCodecResult },
    .{ "escape_encode", genCodecResult }, .{ "escape_decode", genCodecResult },
    .{ "raw_unicode_escape_encode", genCodecResult }, .{ "raw_unicode_escape_decode", genCodecResult },
    .{ "unicode_escape_encode", genCodecResult }, .{ "unicode_escape_decode", genCodecResult },
    .{ "charmap_encode", genCodecResult }, .{ "charmap_decode", genCodecResult },
    .{ "charmap_build", h.c("&[_]u8{} ** 256") },
    .{ "mbcs_encode", genCodecResult }, .{ "mbcs_decode", genCodecResult },
    .{ "readbuffer_encode", h.pass("\"\"") },
});

fn genCodecResult(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ "); try self.genExpr(args[0]);
        try self.emit(", "); try self.genExpr(args[0]); try self.emit(".len }");
    } else try self.emit(".{ \"\", 0 }");
}
