/// Python _abc module - Internal ABC support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "get_cache_token", h.c("@as(u64, 0)") }, .{ "_abc_init", h.c("{}") },
    .{ "_abc_register", genReg }, .{ "_abc_instancecheck", h.c("false") },
    .{ "_abc_subclasscheck", h.c("false") }, .{ "_get_dump", h.c(".{ &[_]type{}, &[_]type{}, &[_]type{} }") },
    .{ "_reset_registry", h.c("{}") }, .{ "_reset_caches", h.c("{}") },
});

fn genReg(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) try self.genExpr(args[1]) else try self.emit("null");
}
