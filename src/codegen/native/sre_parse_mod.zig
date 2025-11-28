/// Python sre_parse module - Internal support module for sre
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate sre_parse.parse(str, flags=0, state=None)
pub fn genParse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const pattern = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = pattern; break :blk .{ .data = &[_]@TypeOf(.{}){}, .flags = 0, .groups = 0 }; }");
    } else {
        try self.emit(".{ .data = &[_]@TypeOf(.{}){}, .flags = 0, .groups = 0 }");
    }
}

/// Generate sre_parse.parse_template(source, state)
pub fn genParseTemplate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ &[_]@TypeOf(.{}){}, &[_]@TypeOf(.{}){} }");
}

/// Generate sre_parse.expand_template(template, match)
pub fn genExpandTemplate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate sre_parse.SubPattern class
pub fn genSubPattern(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .data = &[_]@TypeOf(.{}){}, .width = null }");
}

/// Generate sre_parse.Pattern class (state)
pub fn genPattern(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .flags = 0, .groupdict = .{}, .groupwidths = &[_]?struct{usize, usize}{}, .lookbehindgroups = null }");
}

/// Generate sre_parse.Tokenizer class
pub fn genTokenizer(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .istext = true, .string = \"\", .decoded_string = null, .index = 0, .next = null }");
}

/// Generate sre_parse.getwidth(op, av)
pub fn genGetwidth(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(usize, 0), @as(usize, 65535) }");
}

/// Generate sre_parse.SPECIAL_CHARS constant
pub fn genSpecialChars(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\\\\()[]{}|^$*+?.\"");
}

/// Generate sre_parse.REPEAT_CHARS constant
pub fn genRepeatChars(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"*+?{\"");
}

/// Generate sre_parse.DIGITS constant
pub fn genDigits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' }");
}

/// Generate sre_parse.OCTDIGITS constant
pub fn genOctdigits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ '0', '1', '2', '3', '4', '5', '6', '7' }");
}

/// Generate sre_parse.HEXDIGITS constant
pub fn genHexdigits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f', 'A', 'B', 'C', 'D', 'E', 'F' }");
}

/// Generate sre_parse.ASCIILETTERS constant
pub fn genAsciiletters(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ\"");
}

/// Generate sre_parse.WHITESPACE constant
pub fn genWhitespace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\" \\t\\n\\r\\x0b\\x0c\"");
}

/// Generate sre_parse.ESCAPES dict
pub fn genEscapes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate sre_parse.CATEGORIES dict
pub fn genCategories(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate sre_parse.FLAGS dict
pub fn genFlags(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .i = 2, .L = 4, .m = 8, .s = 16, .u = 32, .x = 64, .a = 256 }");
}

/// Generate sre_parse.TYPE_FLAGS constant
pub fn genTypeFlags(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 2 | 4 | 32 | 256)");
}

/// Generate sre_parse.GLOBAL_FLAGS constant
pub fn genGlobalFlags(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(u32, 64)");
}

/// Generate sre_parse.Verbose exception
pub fn genVerbose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.Verbose");
}
