/// Python hashlib module - md5, sha1, sha256, sha512
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

fn genHash(comptime name: []const u8) h.H {
    return struct {
        fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len > 0) {
                try self.emit("(blk: { var _h = hashlib." ++ name ++ "(); _h.update(");
                try self.genExpr(args[0]);
                try self.emit("); break :blk _h; })");
            } else {
                try self.emit("hashlib." ++ name ++ "()");
            }
        }
    }.f;
}

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

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "md5", genHash("md5") }, .{ "sha1", genHash("sha1") }, .{ "sha224", genHash("sha224") },
    .{ "sha256", genHash("sha256") }, .{ "sha384", genHash("sha384") }, .{ "sha512", genHash("sha512") },
    .{ "new", genNew },
});
