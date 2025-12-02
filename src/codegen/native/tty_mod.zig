/// Python tty module - Terminal control functions
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "setraw", h.c("{}") },
    .{ "setcbreak", h.c("{}") },
    .{ "isatty", genIsatty },
});

fn genIsatty(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.posix.isatty(@intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else try self.emit("false");
}
