/// Python _codecs module - C accelerator for codecs (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "encode", genPassthrough }, .{ "decode", genPassthrough },
    .{ "register", genUnit }, .{ "lookup", genLookup }, .{ "register_error", genUnit }, .{ "lookup_error", genNull },
    .{ "utf_8_encode", genCodecResult }, .{ "utf_8_decode", genCodecResult },
    .{ "ascii_encode", genCodecResult }, .{ "ascii_decode", genCodecResult },
    .{ "latin_1_encode", genCodecResult }, .{ "latin_1_decode", genCodecResult },
    .{ "escape_encode", genCodecResult }, .{ "escape_decode", genCodecResult },
    .{ "raw_unicode_escape_encode", genCodecResult }, .{ "raw_unicode_escape_decode", genCodecResult },
    .{ "unicode_escape_encode", genCodecResult }, .{ "unicode_escape_decode", genCodecResult },
    .{ "charmap_encode", genCodecResult }, .{ "charmap_decode", genCodecResult },
    .{ "charmap_build", genCharmapBuild },
    .{ "mbcs_encode", genCodecResult }, .{ "mbcs_decode", genCodecResult },
    .{ "readbuffer_encode", genPassthrough },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "null"); }
fn genLookup(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .encode = null, .decode = null, .streamreader = null, .streamwriter = null }"); }
fn genCharmapBuild(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_]u8{} ** 256"); }

// Passthrough - returns arg[0] or empty string
fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}

// Codec result - returns tuple of (data, length)
fn genCodecResult(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ "); try self.genExpr(args[0]);
        try self.emit(", "); try self.genExpr(args[0]); try self.emit(".len }");
    } else try self.emit(".{ \"\", 0 }");
}
