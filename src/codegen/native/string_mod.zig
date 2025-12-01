/// Python string module - string constants and utilities
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "ascii_lowercase", genAsciiLowercase },
    .{ "ascii_uppercase", genAsciiUppercase },
    .{ "ascii_letters", genAsciiLetters },
    .{ "digits", genDigits },
    .{ "hexdigits", genHexdigits },
    .{ "octdigits", genOctdigits },
    .{ "punctuation", genPunctuation },
    .{ "whitespace", genWhitespace },
    .{ "printable", genPrintable },
    .{ "capwords", genCapwords },
    .{ "Formatter", genFormatter },
    .{ "Template", genTemplate },
});

// String constants as defined in Python's string module

/// Generate string.ascii_lowercase -> "abcdefghijklmnopqrstuvwxyz"
pub fn genAsciiLowercase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"abcdefghijklmnopqrstuvwxyz\"");
}

/// Generate string.ascii_uppercase -> "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
pub fn genAsciiUppercase(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ABCDEFGHIJKLMNOPQRSTUVWXYZ\"");
}

/// Generate string.ascii_letters -> lowercase + uppercase
pub fn genAsciiLetters(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ\"");
}

/// Generate string.digits -> "0123456789"
pub fn genDigits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"0123456789\"");
}

/// Generate string.hexdigits -> "0123456789abcdefABCDEF"
pub fn genHexdigits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"0123456789abcdefABCDEF\"");
}

/// Generate string.octdigits -> "01234567"
pub fn genOctdigits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"01234567\"");
}

/// Generate string.punctuation -> all ASCII punctuation characters
pub fn genPunctuation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"!\\\"#$%&'()*+,-./:;<=>?@[\\\\]^_`{|}~\"");
}

/// Generate string.whitespace -> " \t\n\r\v\f"
pub fn genWhitespace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\" \\t\\n\\r\\x0b\\x0c\"");
}

/// Generate string.printable -> digits + letters + punctuation + whitespace
pub fn genPrintable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!\\\"#$%&'()*+,-./:;<=>?@[\\\\]^_`{|}~ \\t\\n\\r\\x0b\\x0c\"");
}

/// Generate string.capwords(s, sep=None) -> string with capitalized words
pub fn genCapwords(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("capwords_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _s = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("var _result: std.ArrayList(u8) = .{};\n");
    try self.emitIndent();
    try self.emit("var _cap_next = true;\n");
    try self.emitIndent();
    try self.emit("for (_s) |c| {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("if (c == ' ') {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, ' ') catch continue;\n");
    try self.emitIndent();
    try self.emit("_cap_next = true;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else if (_cap_next and c >= 'a' and c <= 'z') {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, c - 32) catch continue;\n");
    try self.emitIndent();
    try self.emit("_cap_next = false;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("} else {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("_result.append(__global_allocator, c) catch continue;\n");
    try self.emitIndent();
    try self.emit("_cap_next = false;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
    try self.emitIndent();
    try self.emit("break :capwords_blk _result.items;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate string.Formatter class (placeholder)
pub fn genFormatter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct { format: []const u8 = \"\", pub fn vformat(self: @This(), s: []const u8, _: anytype, _: anytype) []const u8 { _ = self; return s; } }{}");
}

/// Generate string.Template class (placeholder)
pub fn genTemplate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("struct { template: []const u8 = \"\", pub fn substitute(self: @This(), _: anytype) []const u8 { return self.template; } pub fn safe_substitute(self: @This(), _: anytype) []const u8 { return self.template; } }{}");
        return;
    }

    try self.emit("struct { template: []const u8, pub fn substitute(self: @This(), _: anytype) []const u8 { return self.template; } pub fn safe_substitute(self: @This(), _: anytype) []const u8 { return self.template; } }{ .template = ");
    try self.genExpr(args[0]);
    try self.emit(" }");
}
