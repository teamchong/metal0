/// Python atexit module - Exit handlers
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "register", genRegister }, .{ "unregister", h.c("{}") }, .{ "_run_exitfuncs", h.c("{}") },
    .{ "_clear", h.c("{}") }, .{ "_ncallbacks", h.I64(0) },
});

fn genRegister(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("@as(?*anyopaque, null)");
}
