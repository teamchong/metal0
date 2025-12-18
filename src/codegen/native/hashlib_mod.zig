/// Python hashlib module - md5, sha1, sha256, sha512
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "md5", h.hashNew("md5") }, .{ "sha1", h.hashNew("sha1") }, .{ "sha224", h.hashNew("sha224") },
    .{ "sha256", h.hashNew("sha256") }, .{ "sha384", h.hashNew("sha384") }, .{ "sha512", h.hashNew("sha512") },
    .{ "new", genNew },
});

fn genNew(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    if (args.len > 1) {
        const id = self.nextNameId();
        try self.emitFmt("__m{d}_hash_new: {{ var _h = try hashlib.new(", .{id});
        try self.genExpr(args[0]);
        try self.emitFmt("); _h.update(", .{});
        try self.genExpr(args[1]);
        try self.emitFmt("); break :__m{d}_hash_new _h; }}", .{id});
    } else {
        try self.emit("try hashlib.new(");
        try self.genExpr(args[0]);
        try self.emit(")");
    }
}
