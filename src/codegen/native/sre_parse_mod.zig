/// Python sre_parse module - Internal support module for sre
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "parse", genParse }, .{ "parse_template", genConst(".{ &[_]@TypeOf(.{}){}, &[_]@TypeOf(.{}){} }") },
    .{ "expand_template", genConst("\"\"") }, .{ "SubPattern", genConst(".{ .data = &[_]@TypeOf(.{}){}, .width = null }") },
    .{ "Pattern", genConst(".{ .flags = 0, .groupdict = .{}, .groupwidths = &[_]?struct{usize, usize}{}, .lookbehindgroups = null }") },
    .{ "Tokenizer", genConst(".{ .istext = true, .string = \"\", .decoded_string = null, .index = 0, .next = null }") },
    .{ "getwidth", genConst(".{ @as(usize, 0), @as(usize, 65535) }") },
    .{ "SPECIAL_CHARS", genConst("\"\\\\()[]{}|^$*+?.\"") }, .{ "REPEAT_CHARS", genConst("\"*+?{\"") },
    .{ "DIGITS", genConst(".{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' }") },
    .{ "OCTDIGITS", genConst(".{ '0', '1', '2', '3', '4', '5', '6', '7' }") },
    .{ "HEXDIGITS", genConst(".{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f', 'A', 'B', 'C', 'D', 'E', 'F' }") },
    .{ "ASCIILETTERS", genConst("\"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ\"") },
    .{ "WHITESPACE", genConst("\" \\t\\n\\r\\x0b\\x0c\"") },
    .{ "ESCAPES", genConst(".{}") }, .{ "CATEGORIES", genConst(".{}") },
    .{ "FLAGS", genConst(".{ .i = 2, .L = 4, .m = 8, .s = 16, .u = 32, .x = 64, .a = 256 }") },
    .{ "TYPE_FLAGS", genConst("@as(u32, 2 | 4 | 32 | 256)") }, .{ "GLOBAL_FLAGS", genConst("@as(u32, 64)") },
    .{ "Verbose", genConst("error.Verbose") },
});

fn genParse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit(".{ .data = &[_]@TypeOf(.{}){}, .flags = 0, .groups = 0 }"); return; }
    try self.emit("blk: { const pattern = "); try self.genExpr(args[0]); try self.emit("; _ = pattern; break :blk .{ .data = &[_]@TypeOf(.{}){}, .flags = 0, .groups = 0 }; }");
}
