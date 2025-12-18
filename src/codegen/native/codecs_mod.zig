/// Python codecs module - Codec registry and base classes
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "encode", genEncode },
    .{ "decode", genDecode },
    .{ "lookup", genLookup },
    .{ "getencoder", genGetencoder },
    .{ "getdecoder", genGetdecoder },
    .{ "getincrementalencoder", genGetincrementalencoder },
    .{ "getincrementaldecoder", genGetincrementaldecoder },
    .{ "getreader", genGetreader },
    .{ "getwriter", genGetwriter },
    .{ "register", genRegister },
    .{ "unregister", genUnregister },
    .{ "register_error", genRegisterError },
    .{ "lookup_error", genLookupError },
    .{ "strict_errors", genStrictErrors },
    .{ "ignore_errors", genIgnoreErrors },
    .{ "replace_errors", genReplaceErrors },
    .{ "xmlcharrefreplace_errors", genXmlcharrefreplaceErrors },
    .{ "backslashreplace_errors", genBackslashreplaceErrors },
    .{ "namereplace_errors", genNamereplaceErrors },
    .{ "open", genOpen },
    .{ "EncodedFile", genEncodedFile },
    .{ "iterencode", genIterencode },
    .{ "iterdecode", genIterdecode },
    .{ "BOM", genBOM },
    .{ "BOM_UTF8", genBOM_UTF8 },
    .{ "BOM_UTF16", genBOM_UTF16 },
    .{ "BOM_UTF16_LE", genBOM_UTF16_LE },
    .{ "BOM_UTF16_BE", genBOM_UTF16_BE },
    .{ "BOM_UTF32", genBOM_UTF32 },
    .{ "BOM_UTF32_LE", genBOM_UTF32_LE },
    .{ "BOM_UTF32_BE", genBOM_UTF32_BE },
    .{ "Codec", genCodec },
    .{ "IncrementalEncoder", genIncrementalEncoder },
    .{ "IncrementalDecoder", genIncrementalDecoder },
    .{ "StreamWriter", genStreamWriter },
    .{ "StreamReader", genStreamReader },
    .{ "StreamReaderWriter", genStreamReaderWriter },
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

fn genLookup(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { name: []const u8 = \"utf-8\", encode: ?*anyopaque = null, decode: ?*anyopaque = null, incrementalencoder: ?*anyopaque = null, incrementaldecoder: ?*anyopaque = null, streamreader: ?*anyopaque = null, streamwriter: ?*anyopaque = null }{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetencoder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genGetdecoder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genGetincrementalencoder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genGetincrementaldecoder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genGetreader(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genGetwriter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genRegister(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genUnregister(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genRegisterError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genLookupError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genStrictErrors(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genIgnoreErrors(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"\", @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genReplaceErrors(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"?\", @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genXmlcharrefreplaceErrors(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"\", @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genBackslashreplaceErrors(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"\", @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genNamereplaceErrors(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ \"\", @as(i64, 0) }"), builder_mod.EmitConfig.forExpression());
}

fn genOpen(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genEncodedFile(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(?*anyopaque, null)"), builder_mod.EmitConfig.forExpression());
}

fn genIterencode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
}

fn genIterdecode(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("&[_][]const u8{}"), builder_mod.EmitConfig.forExpression());
}

fn genBOM(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("\"\\xef\\xbb\\xbf\""), builder_mod.EmitConfig.forExpression());
}

fn genBOM_UTF8(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("\"\\xef\\xbb\\xbf\""), builder_mod.EmitConfig.forExpression());
}

fn genBOM_UTF16(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("\"\\xff\\xfe\""), builder_mod.EmitConfig.forExpression());
}

fn genBOM_UTF16_LE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("\"\\xff\\xfe\""), builder_mod.EmitConfig.forExpression());
}

fn genBOM_UTF16_BE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("\"\\xfe\\xff\""), builder_mod.EmitConfig.forExpression());
}

fn genBOM_UTF32(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("\"\\xff\\xfe\\x00\\x00\""), builder_mod.EmitConfig.forExpression());
}

fn genBOM_UTF32_LE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("\"\\xff\\xfe\\x00\\x00\""), builder_mod.EmitConfig.forExpression());
}

fn genBOM_UTF32_BE(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("\"\\x00\\x00\\xfe\\xff\""), builder_mod.EmitConfig.forExpression());
}

fn genCodec(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { pub fn encode(__self: @This(), input: []const u8) []const u8 { _ = &__self; return input; } pub fn decode(__self: @This(), input: []const u8) []const u8 { _ = &__self; return input; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genIncrementalEncoder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { errors: []const u8 = \"strict\", pub fn encode(__self: @This(), input: []const u8, final: bool) []const u8 { _ = &__self; _ = final; return input; } pub fn reset(__self: *@This()) void { _ = __self; } pub fn getstate(__self: @This()) i64 { _ = &__self; return 0; } pub fn setstate(__self: *@This(), state: i64) void { _ = __self; _ = state; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genIncrementalDecoder(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { errors: []const u8 = \"strict\", pub fn encode(__self: @This(), input: []const u8, final: bool) []const u8 { _ = &__self; _ = final; return input; } pub fn reset(__self: *@This()) void { _ = __self; } pub fn getstate(__self: @This()) i64 { _ = &__self; return 0; } pub fn setstate(__self: *@This(), state: i64) void { _ = __self; _ = state; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genStreamWriter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { stream: ?*anyopaque = null, errors: []const u8 = \"strict\", pub fn write(__self: @This(), data: []const u8) void { _ = &__self; _ = data; } pub fn writelines(__self: @This(), lines: anytype) void { _ = &__self; _ = lines; } pub fn reset(__self: *@This()) void { _ = __self; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genStreamReader(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct { stream: ?*anyopaque = null, errors: []const u8 = \"strict\", pub fn read(__self: @This(), size: i64) []const u8 { _ = &__self; _ = size; return \"\"; } pub fn readline(__self: @This()) []const u8 { _ = &__self; return \"\"; } pub fn readlines(__self: @This()) [][]const u8 { _ = &__self; return &[_][]const u8{}; } pub fn reset(__self: *@This()) void { _ = __self; } }{}"), builder_mod.EmitConfig.forExpression());
}

fn genStreamReaderWriter(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("struct {}{}"), builder_mod.EmitConfig.forExpression());
}
