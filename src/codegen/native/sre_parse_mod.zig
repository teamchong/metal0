/// Python sre_parse module - Internal support module for sre
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{}"); }

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "parse", genParse }, .{ "parse_template", genParseTemplate }, .{ "expand_template", genExpandTemplate },
    .{ "SubPattern", genSubPattern }, .{ "Pattern", genPattern }, .{ "Tokenizer", genTokenizer },
    .{ "getwidth", genGetwidth }, .{ "SPECIAL_CHARS", genSpecialChars }, .{ "REPEAT_CHARS", genRepeatChars },
    .{ "DIGITS", genDigits }, .{ "OCTDIGITS", genOctdigits }, .{ "HEXDIGITS", genHexdigits },
    .{ "ASCIILETTERS", genAsciiletters }, .{ "WHITESPACE", genWhitespace },
    .{ "ESCAPES", genEmpty }, .{ "CATEGORIES", genEmpty },
    .{ "FLAGS", genFlags }, .{ "TYPE_FLAGS", genTypeFlags }, .{ "GLOBAL_FLAGS", genGlobalFlags },
    .{ "Verbose", genVerbose },
});

fn genParse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit(".{ .data = &[_]@TypeOf(.{}){}, .flags = 0, .groups = 0 }"); return; }
    try self.emit("blk: { const pattern = "); try self.genExpr(args[0]); try self.emit("; _ = pattern; break :blk .{ .data = &[_]@TypeOf(.{}){}, .flags = 0, .groups = 0 }; }");
}

fn genParseTemplate(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ &[_]@TypeOf(.{}){}, &[_]@TypeOf(.{}){} }"); }
fn genExpandTemplate(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genSubPattern(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .data = &[_]@TypeOf(.{}){}, .width = null }"); }
fn genPattern(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .flags = 0, .groupdict = .{}, .groupwidths = &[_]?struct{usize, usize}{}, .lookbehindgroups = null }"); }
fn genTokenizer(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .istext = true, .string = \"\", .decoded_string = null, .index = 0, .next = null }"); }
fn genGetwidth(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(usize, 0), @as(usize, 65535) }"); }
fn genSpecialChars(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\\\\()[]{}|^$*+?.\""); }
fn genRepeatChars(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"*+?{\""); }
fn genDigits(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' }"); }
fn genOctdigits(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ '0', '1', '2', '3', '4', '5', '6', '7' }"); }
fn genHexdigits(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f', 'A', 'B', 'C', 'D', 'E', 'F' }"); }
fn genAsciiletters(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ\""); }
fn genWhitespace(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\" \\t\\n\\r\\x0b\\x0c\""); }
fn genFlags(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .i = 2, .L = 4, .m = 8, .s = 16, .u = 32, .x = 64, .a = 256 }"); }
fn genTypeFlags(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 2 | 4 | 32 | 256)"); }
fn genGlobalFlags(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(u32, 64)"); }
fn genVerbose(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.Verbose"); }
