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
        try self.withInlineBlock("hash_new", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("var _h = try hashlib.new(");
                try c.genExpr(a[0]);
                try c.emit("); _h.update(");
                try c.genExpr(a[1]);
                try c.emitFmt("); break :{s} _h", .{label});
            }
        }.emit);
    } else {
        try self.emitCallCtx("try hashlib.new", args[0], struct {
            pub fn f(s: *NativeCodegen, e: ast.Node) CodegenError!void {
                try s.genExpr(e);
            }
        }.f);
    }
}
