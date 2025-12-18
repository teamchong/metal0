/// Python _codecs module - C accelerator for codecs (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "encode", genEncode },
    .{ "decode", genDecode },
    .{ "register", genRegister },
    .{ "lookup", genLookup },
    .{ "register_error", genRegisterError },
    .{ "lookup_error", genLookupError },
    .{ "utf_8_encode", genCodecResult },
    .{ "utf_8_decode", genCodecResult },
    .{ "ascii_encode", genCodecResult },
    .{ "ascii_decode", genCodecResult },
    .{ "latin_1_encode", genCodecResult },
    .{ "latin_1_decode", genCodecResult },
    .{ "escape_encode", genCodecResult },
    .{ "escape_decode", genCodecResult },
    .{ "raw_unicode_escape_encode", genCodecResult },
    .{ "raw_unicode_escape_decode", genCodecResult },
    .{ "unicode_escape_encode", genCodecResult },
    .{ "unicode_escape_decode", genCodecResult },
    .{ "charmap_encode", genCodecResult },
    .{ "charmap_decode", genCodecResult },
    .{ "charmap_build", genCharmapBuild },
    .{ "mbcs_encode", genCodecResult },
    .{ "mbcs_decode", genCodecResult },
    .{ "readbuffer_encode", genReadbufferEncode },
});

fn genEncode(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}

fn genDecode(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}

fn genRegister(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genLookup(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .encode = null, .decode = null, .streamreader = null, .streamwriter = null }"), builder_mod.EmitConfig.forExpression());
}

fn genRegisterError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genLookupError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
}

fn genCodecResult(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"\", 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genCharmapBuild(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_]u8{} ** 256"), builder_mod.EmitConfig.forExpression());
}

fn genReadbufferEncode(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try b.emitValue(builder_mod.ZigValue.string(""), builder_mod.EmitConfig.forExpression());
    }
}
