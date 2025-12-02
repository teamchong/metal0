/// Python codecs module - Codec registry and base classes
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
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

/// Generate codecs.encode(obj, encoding='utf-8', errors='strict') -> bytes
pub fn genEncode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("&[_]u8{}");
        return;
    }
    try self.genExpr(args[0]);
}

/// Generate codecs.decode(obj, encoding='utf-8', errors='strict') -> str
pub fn genDecode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"\"");
        return;
    }
    try self.genExpr(args[0]);
}

/// Generate codecs.lookup(encoding) -> CodecInfo
pub fn genLookup(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("name: []const u8 = \"utf-8\",\n");
    try self.emitIndent();
    try self.emit("encode: ?*anyopaque = null,\n");
    try self.emitIndent();
    try self.emit("decode: ?*anyopaque = null,\n");
    try self.emitIndent();
    try self.emit("incrementalencoder: ?*anyopaque = null,\n");
    try self.emitIndent();
    try self.emit("incrementaldecoder: ?*anyopaque = null,\n");
    try self.emitIndent();
    try self.emit("streamreader: ?*anyopaque = null,\n");
    try self.emitIndent();
    try self.emit("streamwriter: ?*anyopaque = null,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate codecs.getencoder(encoding) -> encoder function
pub fn genGetencoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate codecs.getdecoder(encoding) -> decoder function
pub fn genGetdecoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate codecs.getincrementalencoder(encoding) -> encoder class
pub fn genGetincrementalencoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate codecs.getincrementaldecoder(encoding) -> decoder class
pub fn genGetincrementaldecoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate codecs.getreader(encoding) -> reader class
pub fn genGetreader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate codecs.getwriter(encoding) -> writer class
pub fn genGetwriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate codecs.register(search_function) -> None
pub fn genRegister(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate codecs.unregister(search_function) -> None
pub fn genUnregister(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate codecs.register_error(name, error_handler) -> None
pub fn genRegisterError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate codecs.lookup_error(name) -> error_handler
pub fn genLookupError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate codecs.strict_errors(exception) -> raise
pub fn genStrictErrors(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate codecs.ignore_errors(exception) -> ('', pos)
pub fn genIgnoreErrors(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"\", @as(i64, 0) }");
}

/// Generate codecs.replace_errors(exception) -> (replacement, pos)
pub fn genReplaceErrors(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"?\", @as(i64, 0) }");
}

/// Generate codecs.xmlcharrefreplace_errors(exception) -> (replacement, pos)
pub fn genXmlcharrefreplaceErrors(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"\", @as(i64, 0) }");
}

/// Generate codecs.backslashreplace_errors(exception) -> (replacement, pos)
pub fn genBackslashreplaceErrors(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"\", @as(i64, 0) }");
}

/// Generate codecs.namereplace_errors(exception) -> (replacement, pos)
pub fn genNamereplaceErrors(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ \"\", @as(i64, 0) }");
}

/// Generate codecs.open(filename, mode='r', encoding=None, errors='strict', buffering=-1) -> file
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate codecs.EncodedFile(file, data_encoding, file_encoding=None, errors='strict') -> wrapped file
pub fn genEncodedFile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate codecs.iterencode(iterator, encoding, errors='strict') -> iterator
pub fn genIterencode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate codecs.iterdecode(iterator, encoding, errors='strict') -> iterator
pub fn genIterdecode(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate codecs.BOM constant
pub fn genBOM(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\xef\\xbb\\xbf\"");
}

/// Generate codecs.BOM_UTF8 constant
pub fn genBOM_UTF8(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\xef\\xbb\\xbf\"");
}

/// Generate codecs.BOM_UTF16 constant
pub fn genBOM_UTF16(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\xff\\xfe\"");
}

/// Generate codecs.BOM_UTF16_LE constant
pub fn genBOM_UTF16_LE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\xff\\xfe\"");
}

/// Generate codecs.BOM_UTF16_BE constant
pub fn genBOM_UTF16_BE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\xfe\\xff\"");
}

/// Generate codecs.BOM_UTF32 constant
pub fn genBOM_UTF32(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\xff\\xfe\\x00\\x00\"");
}

/// Generate codecs.BOM_UTF32_LE constant
pub fn genBOM_UTF32_LE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\xff\\xfe\\x00\\x00\"");
}

/// Generate codecs.BOM_UTF32_BE constant
pub fn genBOM_UTF32_BE(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\x00\\x00\\xfe\\xff\"");
}

/// Generate codecs.Codec base class
pub fn genCodec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("pub fn encode(self: @This(), input: []const u8) []const u8 { return input; }\n");
    try self.emitIndent();
    try self.emit("pub fn decode(self: @This(), input: []const u8) []const u8 { return input; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate codecs.IncrementalEncoder base class
pub fn genIncrementalEncoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("errors: []const u8 = \"strict\",\n");
    try self.emitIndent();
    try self.emit("pub fn encode(self: @This(), input: []const u8, final: bool) []const u8 { _ = final; return input; }\n");
    try self.emitIndent();
    try self.emit("pub fn reset(__self: *@This()) void { }\n");
    try self.emitIndent();
    try self.emit("pub fn getstate(self: @This()) i64 { return 0; }\n");
    try self.emitIndent();
    try self.emit("pub fn setstate(__self: *@This(), state: i64) void { _ = state; }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate codecs.IncrementalDecoder base class
pub fn genIncrementalDecoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genIncrementalEncoder(self, args);
}

/// Generate codecs.StreamWriter base class
pub fn genStreamWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("stream: ?*anyopaque = null,\n");
    try self.emitIndent();
    try self.emit("errors: []const u8 = \"strict\",\n");
    try self.emitIndent();
    try self.emit("pub fn write(self: @This(), data: []const u8) void { _ = data; }\n");
    try self.emitIndent();
    try self.emit("pub fn writelines(self: @This(), lines: anytype) void { _ = lines; }\n");
    try self.emitIndent();
    try self.emit("pub fn reset(__self: *@This()) void { }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate codecs.StreamReader base class
pub fn genStreamReader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("stream: ?*anyopaque = null,\n");
    try self.emitIndent();
    try self.emit("errors: []const u8 = \"strict\",\n");
    try self.emitIndent();
    try self.emit("pub fn read(self: @This(), size: i64) []const u8 { _ = size; return \"\"; }\n");
    try self.emitIndent();
    try self.emit("pub fn readline(self: @This()) []const u8 { return \"\"; }\n");
    try self.emitIndent();
    try self.emit("pub fn readlines(self: @This()) [][]const u8 { return &[_][]const u8{}; }\n");
    try self.emitIndent();
    try self.emit("pub fn reset(__self: *@This()) void { }\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate codecs.StreamReaderWriter base class
pub fn genStreamReaderWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {}{}");
}
