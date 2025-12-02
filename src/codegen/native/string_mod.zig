/// Python string module - string constants and utilities
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Public exports for use in builtins.zig
pub const genAsciiLowercase = h.c("\"abcdefghijklmnopqrstuvwxyz\"");
pub const genAsciiUppercase = h.c("\"ABCDEFGHIJKLMNOPQRSTUVWXYZ\"");
pub const genAsciiLetters = h.c("\"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ\"");
pub const genDigits = h.c("\"0123456789\"");
pub const genPunctuation = h.c("\"!\\\"#$%&'()*+,-./:;<=>?@[\\\\]^_`{|}~\"");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "ascii_lowercase", genAsciiLowercase }, .{ "ascii_uppercase", genAsciiUppercase },
    .{ "ascii_letters", genAsciiLetters }, .{ "digits", genDigits },
    .{ "hexdigits", h.c("\"0123456789abcdefABCDEF\"") }, .{ "octdigits", h.c("\"01234567\"") },
    .{ "punctuation", genPunctuation }, .{ "whitespace", h.c("\" \\t\\n\\r\\x0b\\x0c\"") },
    .{ "printable", h.c("\"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!\\\"#$%&'()*+,-./:;<=>?@[\\\\]^_`{|}~ \\t\\n\\r\\x0b\\x0c\"") },
    .{ "capwords", genCapwords }, .{ "Formatter", h.c("struct { format: []const u8 = \"\", pub fn vformat(self: @This(), s: []const u8, _: anytype, _: anytype) []const u8 { return s; } }{}") },
    .{ "Template", genTemplate },
});

pub fn genCapwords(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("capwords_blk: {\n"); self.indent();
    try self.emitIndent(); try self.emit("const _s = "); try self.genExpr(args[0]); try self.emit(";\n");
    try self.emitIndent(); try self.emit("var _result: std.ArrayList(u8) = .{};\n");
    try self.emitIndent(); try self.emit("var _cap_next = true;\n");
    try self.emitIndent(); try self.emit("for (_s) |c| {\n"); self.indent();
    try self.emitIndent(); try self.emit("if (c == ' ') { _result.append(__global_allocator, ' ') catch continue; _cap_next = true; }\n");
    try self.emitIndent(); try self.emit("else if (_cap_next and c >= 'a' and c <= 'z') { _result.append(__global_allocator, c - 32) catch continue; _cap_next = false; }\n");
    try self.emitIndent(); try self.emit("else { _result.append(__global_allocator, c) catch continue; _cap_next = false; }\n");
    self.dedent(); try self.emitIndent(); try self.emit("}\n");
    try self.emitIndent(); try self.emit("break :capwords_blk _result.items;\n");
    self.dedent(); try self.emitIndent(); try self.emit("}");
}

fn genTemplate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("struct { template: []const u8 = \"\", pub fn substitute(self: @This(), _: anytype) []const u8 { return __self.template; } pub fn safe_substitute(self: @This(), _: anytype) []const u8 { return __self.template; } }{}"); return; }
    try self.emit("struct { template: []const u8, pub fn substitute(self: @This(), _: anytype) []const u8 { return __self.template; } pub fn safe_substitute(self: @This(), _: anytype) []const u8 { return __self.template; } }{ .template = ");
    try self.genExpr(args[0]); try self.emit(" }");
}
