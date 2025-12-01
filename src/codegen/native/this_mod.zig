/// Python this module - The Zen of Python easter egg
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "s", genS },
    .{ "d", genD },
});

/// Generate this.s (encoded Zen of Python)
pub fn genS(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Gur Mra bs Clguba, ol Gvz Crgref...\"");
}

/// Generate this.d (decoding dictionary)
pub fn genD(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}
