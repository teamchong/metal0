/// Python codecs module - Codec registry and base classes
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "encode", genPassthrough }, .{ "decode", genPassthrough },
    .{ "lookup", genCodecInfo }, .{ "getencoder", genNull }, .{ "getdecoder", genNull },
    .{ "getincrementalencoder", genNull }, .{ "getincrementaldecoder", genNull },
    .{ "getreader", genNull }, .{ "getwriter", genNull },
    .{ "register", genUnit }, .{ "unregister", genUnit }, .{ "register_error", genUnit },
    .{ "lookup_error", genNull }, .{ "strict_errors", genUnit },
    .{ "ignore_errors", genErrorTuple }, .{ "replace_errors", genReplaceErrorTuple },
    .{ "xmlcharrefreplace_errors", genErrorTuple }, .{ "backslashreplace_errors", genErrorTuple },
    .{ "namereplace_errors", genErrorTuple },
    .{ "open", genNull }, .{ "EncodedFile", genNull },
    .{ "iterencode", genEmptyStrSlice }, .{ "iterdecode", genEmptyStrSlice },
    .{ "BOM", genBOM_UTF8 }, .{ "BOM_UTF8", genBOM_UTF8 },
    .{ "BOM_UTF16", genBOM_UTF16_LE }, .{ "BOM_UTF16_LE", genBOM_UTF16_LE }, .{ "BOM_UTF16_BE", genBOM_UTF16_BE },
    .{ "BOM_UTF32", genBOM_UTF32_LE }, .{ "BOM_UTF32_LE", genBOM_UTF32_LE }, .{ "BOM_UTF32_BE", genBOM_UTF32_BE },
    .{ "Codec", genCodecClass }, .{ "IncrementalEncoder", genIncEncoder }, .{ "IncrementalDecoder", genIncEncoder },
    .{ "StreamWriter", genStreamWriter }, .{ "StreamReader", genStreamReader }, .{ "StreamReaderWriter", genEmptyStruct },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(?*anyopaque, null)"); }
fn genEmptyStrSlice(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{}"); }
fn genEmptyStruct(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "struct {}{}"); }
fn genErrorTuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"\", @as(i64, 0) }"); }
fn genReplaceErrorTuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ \"?\", @as(i64, 0) }"); }

// BOM constants
fn genBOM_UTF8(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\\xef\\xbb\\xbf\""); }
fn genBOM_UTF16_LE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\\xff\\xfe\""); }
fn genBOM_UTF16_BE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\\xfe\\xff\""); }
fn genBOM_UTF32_LE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\\xff\\xfe\\x00\\x00\""); }
fn genBOM_UTF32_BE(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\\x00\\x00\\xfe\\xff\""); }

// Passthrough - returns arg[0] or empty
fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}

// Complex struct types
fn genCodecInfo(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { name: []const u8 = \"utf-8\", encode: ?*anyopaque = null, decode: ?*anyopaque = null, incrementalencoder: ?*anyopaque = null, incrementaldecoder: ?*anyopaque = null, streamreader: ?*anyopaque = null, streamwriter: ?*anyopaque = null }{}");
}

fn genCodecClass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { pub fn encode(self: @This(), input: []const u8) []const u8 { return input; } pub fn decode(self: @This(), input: []const u8) []const u8 { return input; } }{}");
}

fn genIncEncoder(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { errors: []const u8 = \"strict\", pub fn encode(self: @This(), input: []const u8, final: bool) []const u8 { _ = final; return input; } pub fn reset(__self: *@This()) void { } pub fn getstate(self: @This()) i64 { return 0; } pub fn setstate(__self: *@This(), state: i64) void { _ = state; } }{}");
}

fn genStreamWriter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { stream: ?*anyopaque = null, errors: []const u8 = \"strict\", pub fn write(self: @This(), data: []const u8) void { _ = data; } pub fn writelines(self: @This(), lines: anytype) void { _ = lines; } pub fn reset(__self: *@This()) void { } }{}");
}

fn genStreamReader(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { stream: ?*anyopaque = null, errors: []const u8 = \"strict\", pub fn read(self: @This(), size: i64) []const u8 { _ = size; return \"\"; } pub fn readline(self: @This()) []const u8 { return \"\"; } pub fn readlines(self: @This()) [][]const u8 { return &[_][]const u8{}; } pub fn reset(__self: *@This()) void { } }{}");
}
