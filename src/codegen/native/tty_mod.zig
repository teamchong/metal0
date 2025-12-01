/// Python tty module - Terminal control functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "setraw", genSetraw },
    .{ "setcbreak", genSetcbreak },
    .{ "isatty", genIsatty },
});

/// Generate tty.setraw(fd, when=termios.TCSAFLUSH)
/// Put terminal into raw mode
pub fn genSetraw(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate tty.setcbreak(fd, when=termios.TCSAFLUSH)
/// Put terminal into cbreak mode
pub fn genSetcbreak(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate tty.isatty(fd)
/// Return True if fd is connected to a terminal
pub fn genIsatty(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.posix.isatty(@intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("false");
    }
}
