/// Python codecs module - Codec registry and base classes
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
    .{ "lookup", genConst("struct { name: []const u8 = \"utf-8\", encode: ?*anyopaque = null, decode: ?*anyopaque = null, incrementalencoder: ?*anyopaque = null, incrementaldecoder: ?*anyopaque = null, streamreader: ?*anyopaque = null, streamwriter: ?*anyopaque = null }{}") },
    .{ "getencoder", genConst("@as(?*anyopaque, null)") }, .{ "getdecoder", genConst("@as(?*anyopaque, null)") },
    .{ "getincrementalencoder", genConst("@as(?*anyopaque, null)") }, .{ "getincrementaldecoder", genConst("@as(?*anyopaque, null)") },
    .{ "getreader", genConst("@as(?*anyopaque, null)") }, .{ "getwriter", genConst("@as(?*anyopaque, null)") },
    .{ "register", genConst("{}") }, .{ "unregister", genConst("{}") }, .{ "register_error", genConst("{}") },
    .{ "lookup_error", genConst("@as(?*anyopaque, null)") }, .{ "strict_errors", genConst("{}") },
    .{ "ignore_errors", genConst(".{ \"\", @as(i64, 0) }") }, .{ "replace_errors", genConst(".{ \"?\", @as(i64, 0) }") },
    .{ "xmlcharrefreplace_errors", genConst(".{ \"\", @as(i64, 0) }") }, .{ "backslashreplace_errors", genConst(".{ \"\", @as(i64, 0) }") },
    .{ "namereplace_errors", genConst(".{ \"\", @as(i64, 0) }") },
    .{ "open", genConst("@as(?*anyopaque, null)") }, .{ "EncodedFile", genConst("@as(?*anyopaque, null)") },
    .{ "iterencode", genConst("&[_][]const u8{}") }, .{ "iterdecode", genConst("&[_][]const u8{}") },
    .{ "BOM", genConst("\"\\xef\\xbb\\xbf\"") }, .{ "BOM_UTF8", genConst("\"\\xef\\xbb\\xbf\"") },
    .{ "BOM_UTF16", genConst("\"\\xff\\xfe\"") }, .{ "BOM_UTF16_LE", genConst("\"\\xff\\xfe\"") }, .{ "BOM_UTF16_BE", genConst("\"\\xfe\\xff\"") },
    .{ "BOM_UTF32", genConst("\"\\xff\\xfe\\x00\\x00\"") }, .{ "BOM_UTF32_LE", genConst("\"\\xff\\xfe\\x00\\x00\"") }, .{ "BOM_UTF32_BE", genConst("\"\\x00\\x00\\xfe\\xff\"") },
    .{ "Codec", genConst("struct { pub fn encode(self: @This(), input: []const u8) []const u8 { return input; } pub fn decode(self: @This(), input: []const u8) []const u8 { return input; } }{}") },
    .{ "IncrementalEncoder", genConst("struct { errors: []const u8 = \"strict\", pub fn encode(self: @This(), input: []const u8, final: bool) []const u8 { _ = final; return input; } pub fn reset(__self: *@This()) void { } pub fn getstate(self: @This()) i64 { return 0; } pub fn setstate(__self: *@This(), state: i64) void { _ = state; } }{}") },
    .{ "IncrementalDecoder", genConst("struct { errors: []const u8 = \"strict\", pub fn encode(self: @This(), input: []const u8, final: bool) []const u8 { _ = final; return input; } pub fn reset(__self: *@This()) void { } pub fn getstate(self: @This()) i64 { return 0; } pub fn setstate(__self: *@This(), state: i64) void { _ = state; } }{}") },
    .{ "StreamWriter", genConst("struct { stream: ?*anyopaque = null, errors: []const u8 = \"strict\", pub fn write(self: @This(), data: []const u8) void { _ = data; } pub fn writelines(self: @This(), lines: anytype) void { _ = lines; } pub fn reset(__self: *@This()) void { } }{}") },
    .{ "StreamReader", genConst("struct { stream: ?*anyopaque = null, errors: []const u8 = \"strict\", pub fn read(self: @This(), size: i64) []const u8 { _ = size; return \"\"; } pub fn readline(self: @This()) []const u8 { return \"\"; } pub fn readlines(self: @This()) [][]const u8 { return &[_][]const u8{}; } pub fn reset(__self: *@This()) void { } }{}") },
    .{ "StreamReaderWriter", genConst("struct {}{}") },
});

fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
