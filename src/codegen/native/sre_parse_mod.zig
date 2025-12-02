/// Python sre_parse module - Internal support module for sre
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "parse", genParse }, .{ "parse_template", h.c(".{ &[_]@TypeOf(.{}){}, &[_]@TypeOf(.{}){} }") },
    .{ "expand_template", h.c("\"\"") }, .{ "SubPattern", h.c(".{ .data = &[_]@TypeOf(.{}){}, .width = null }") },
    .{ "Pattern", h.c(".{ .flags = 0, .groupdict = .{}, .groupwidths = &[_]?struct{usize, usize}{}, .lookbehindgroups = null }") },
    .{ "Tokenizer", h.c(".{ .istext = true, .string = \"\", .decoded_string = null, .index = 0, .next = null }") },
    .{ "getwidth", h.c(".{ @as(usize, 0), @as(usize, 65535) }") },
    .{ "SPECIAL_CHARS", h.c("\"\\\\()[]{}|^$*+?.\"") }, .{ "REPEAT_CHARS", h.c("\"*+?{\"") },
    .{ "DIGITS", h.c(".{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' }") },
    .{ "OCTDIGITS", h.c(".{ '0', '1', '2', '3', '4', '5', '6', '7' }") },
    .{ "HEXDIGITS", h.c(".{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f', 'A', 'B', 'C', 'D', 'E', 'F' }") },
    .{ "ASCIILETTERS", h.c("\"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ\"") },
    .{ "WHITESPACE", h.c("\" \\t\\n\\r\\x0b\\x0c\"") },
    .{ "ESCAPES", h.c(".{}") }, .{ "CATEGORIES", h.c(".{}") },
    .{ "FLAGS", h.c(".{ .i = 2, .L = 4, .m = 8, .s = 16, .u = 32, .x = 64, .a = 256 }") },
    .{ "TYPE_FLAGS", h.U32(2 | 4 | 32 | 256) }, .{ "GLOBAL_FLAGS", h.U32(64) },
    .{ "Verbose", h.err("Verbose") },
});

fn genParse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit(".{ .data = &[_]@TypeOf(.{}){}, .flags = 0, .groups = 0 }"); return; }
    try self.emit("blk: { const pattern = "); try self.genExpr(args[0]); try self.emit("; _ = pattern; break :blk .{ .data = &[_]@TypeOf(.{}){}, .flags = 0, .groups = 0 }; }");
}
