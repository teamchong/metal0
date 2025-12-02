/// Python _codecs module - C accelerator for codecs (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "encode", genPassthrough }, .{ "decode", genPassthrough },
    .{ "register", genConst("{}") }, .{ "lookup", genConst(".{ .encode = null, .decode = null, .streamreader = null, .streamwriter = null }") },
    .{ "register_error", genConst("{}") }, .{ "lookup_error", genConst("null") },
    .{ "utf_8_encode", genCodecResult }, .{ "utf_8_decode", genCodecResult },
    .{ "ascii_encode", genCodecResult }, .{ "ascii_decode", genCodecResult },
    .{ "latin_1_encode", genCodecResult }, .{ "latin_1_decode", genCodecResult },
    .{ "escape_encode", genCodecResult }, .{ "escape_decode", genCodecResult },
    .{ "raw_unicode_escape_encode", genCodecResult }, .{ "raw_unicode_escape_decode", genCodecResult },
    .{ "unicode_escape_encode", genCodecResult }, .{ "unicode_escape_decode", genCodecResult },
    .{ "charmap_encode", genCodecResult }, .{ "charmap_decode", genCodecResult },
    .{ "charmap_build", genConst("&[_]u8{} ** 256") },
    .{ "mbcs_encode", genCodecResult }, .{ "mbcs_decode", genCodecResult },
    .{ "readbuffer_encode", genPassthrough },
});

fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}

fn genCodecResult(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ "); try self.genExpr(args[0]);
        try self.emit(", "); try self.genExpr(args[0]); try self.emit(".len }");
    } else try self.emit(".{ \"\", 0 }");
}
