/// Python codecs module - Codec registry and base classes
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "encode", genPassthrough }, .{ "decode", genPassthrough },
    .{ "lookup", h.c("struct { name: []const u8 = \"utf-8\", encode: ?*anyopaque = null, decode: ?*anyopaque = null, incrementalencoder: ?*anyopaque = null, incrementaldecoder: ?*anyopaque = null, streamreader: ?*anyopaque = null, streamwriter: ?*anyopaque = null }{}") },
    .{ "getencoder", h.c("@as(?*anyopaque, null)") }, .{ "getdecoder", h.c("@as(?*anyopaque, null)") },
    .{ "getincrementalencoder", h.c("@as(?*anyopaque, null)") }, .{ "getincrementaldecoder", h.c("@as(?*anyopaque, null)") },
    .{ "getreader", h.c("@as(?*anyopaque, null)") }, .{ "getwriter", h.c("@as(?*anyopaque, null)") },
    .{ "register", h.c("{}") }, .{ "unregister", h.c("{}") }, .{ "register_error", h.c("{}") },
    .{ "lookup_error", h.c("@as(?*anyopaque, null)") }, .{ "strict_errors", h.c("{}") },
    .{ "ignore_errors", h.c(".{ \"\", @as(i64, 0) }") }, .{ "replace_errors", h.c(".{ \"?\", @as(i64, 0) }") },
    .{ "xmlcharrefreplace_errors", h.c(".{ \"\", @as(i64, 0) }") }, .{ "backslashreplace_errors", h.c(".{ \"\", @as(i64, 0) }") },
    .{ "namereplace_errors", h.c(".{ \"\", @as(i64, 0) }") },
    .{ "open", h.c("@as(?*anyopaque, null)") }, .{ "EncodedFile", h.c("@as(?*anyopaque, null)") },
    .{ "iterencode", h.c("&[_][]const u8{}") }, .{ "iterdecode", h.c("&[_][]const u8{}") },
    .{ "BOM", h.c("\"\\xef\\xbb\\xbf\"") }, .{ "BOM_UTF8", h.c("\"\\xef\\xbb\\xbf\"") },
    .{ "BOM_UTF16", h.c("\"\\xff\\xfe\"") }, .{ "BOM_UTF16_LE", h.c("\"\\xff\\xfe\"") }, .{ "BOM_UTF16_BE", h.c("\"\\xfe\\xff\"") },
    .{ "BOM_UTF32", h.c("\"\\xff\\xfe\\x00\\x00\"") }, .{ "BOM_UTF32_LE", h.c("\"\\xff\\xfe\\x00\\x00\"") }, .{ "BOM_UTF32_BE", h.c("\"\\x00\\x00\\xfe\\xff\"") },
    .{ "Codec", h.c("struct { pub fn encode(self: @This(), input: []const u8) []const u8 { return input; } pub fn decode(self: @This(), input: []const u8) []const u8 { return input; } }{}") },
    .{ "IncrementalEncoder", h.c("struct { errors: []const u8 = \"strict\", pub fn encode(self: @This(), input: []const u8, final: bool) []const u8 { _ = final; return input; } pub fn reset(__self: *@This()) void { } pub fn getstate(self: @This()) i64 { return 0; } pub fn setstate(__self: *@This(), state: i64) void { _ = state; } }{}") },
    .{ "IncrementalDecoder", h.c("struct { errors: []const u8 = \"strict\", pub fn encode(self: @This(), input: []const u8, final: bool) []const u8 { _ = final; return input; } pub fn reset(__self: *@This()) void { } pub fn getstate(self: @This()) i64 { return 0; } pub fn setstate(__self: *@This(), state: i64) void { _ = state; } }{}") },
    .{ "StreamWriter", h.c("struct { stream: ?*anyopaque = null, errors: []const u8 = \"strict\", pub fn write(self: @This(), data: []const u8) void { _ = data; } pub fn writelines(self: @This(), lines: anytype) void { _ = lines; } pub fn reset(__self: *@This()) void { } }{}") },
    .{ "StreamReader", h.c("struct { stream: ?*anyopaque = null, errors: []const u8 = \"strict\", pub fn read(self: @This(), size: i64) []const u8 { _ = size; return \"\"; } pub fn readline(self: @This()) []const u8 { return \"\"; } pub fn readlines(self: @This()) [][]const u8 { return &[_][]const u8{}; } pub fn reset(__self: *@This()) void { } }{}") },
    .{ "StreamReaderWriter", h.c("struct {}{}") },
});

fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
