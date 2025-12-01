/// Python cmd module - Command-line interpreter framework
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Cmd", genCmd },
});

/// Generate cmd.Cmd class
pub fn genCmd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .prompt = \"(Cmd) \", .intro = null, .identchars = \"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_\", .ruler = \"=\", .lastcmd = \"\", .cmdqueue = &[_][]const u8{}, .completekey = \"tab\", .use_rawinput = true }");
}
