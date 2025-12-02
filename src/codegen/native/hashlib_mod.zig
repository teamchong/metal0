/// Python hashlib module - md5, sha1, sha256, sha512
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "md5", h.hashNew("md5") }, .{ "sha1", h.hashNew("sha1") }, .{ "sha224", h.hashNew("sha224") },
    .{ "sha256", h.hashNew("sha256") }, .{ "sha384", h.hashNew("sha384") }, .{ "sha512", h.hashNew("sha512") },
    .{ "new", genNew },
});

fn genNew(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    if (args.len > 1) {
        try self.emit("blk: { var _h = try hashlib.new(");
        try self.genExpr(args[0]);
        try self.emit("); _h.update(");
        try self.genExpr(args[1]);
        try self.emit("); break :blk _h; }");
    } else {
        try self.emit("try hashlib.new(");
        try self.genExpr(args[0]);
        try self.emit(")");
    }
}
