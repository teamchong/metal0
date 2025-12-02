/// Python quopri module - Quoted-Printable encoding/decoding
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "encode", h.c("{}") }, .{ "decode", h.c("{}") },
    .{ "encodestring", genString }, .{ "decodestring", genString },
});

fn genString(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("\"\"");
}
