/// Python hashlib module - md5, sha1, sha256, sha512
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

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
                try emitConst(c, "var _h = try hashlib.new(");
                try c.genExpr(a[0]);
                try emitConst(c, "); _h.update(");
                try c.genExpr(a[1]);
                try emitFmtConst(c, "); break :{s} _h", .{label});
            }
        }.emit);
    } else {
        try emitConst(self, "try hashlib.new(");
        try self.genExpr(args[0]);
        try emitConst(self, ")");
    }
}
