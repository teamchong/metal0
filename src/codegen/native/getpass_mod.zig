/// Python getpass module - Portable password input
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getpass", genGetpass }, .{ "getuser", genGetuser }, .{ "GetPassWarning", h.c("\"GetPassWarning\"") },
});

fn genGetpass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("getpass_blk: {\n"); self.indent(); try self.emitIndent();
    try self.emit("const stdin = std.io.getStdIn().reader();\n"); try self.emitIndent();
    try self.emit("var buf: [256]u8 = undefined;\n"); try self.emitIndent();
    try self.emit("break :getpass_blk stdin.readUntilDelimiter(&buf, '\\n') catch \"\";\n"); self.dedent(); try self.emitIndent(); try self.emit("}");
}
fn genGetuser(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("getuser_blk: {\n"); self.indent(); try self.emitIndent();
    try self.emit("const user = std.posix.getenv(\"USER\") orelse std.posix.getenv(\"LOGNAME\") orelse \"unknown\";\n"); try self.emitIndent();
    try self.emit("break :getuser_blk user;\n"); self.dedent(); try self.emitIndent(); try self.emit("}");
}
