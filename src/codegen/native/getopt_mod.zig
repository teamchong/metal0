/// Python getopt module - C-style parser for command line options
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getopt", genGetopt }, .{ "gnu_getopt", genGetopt }, .{ "GetoptError", h.err("GetoptError") }, .{ "error", h.err("GetoptError") },
});

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genGetopt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit(".{ &[_]struct { []const u8, []const u8 }{}, &[_][]const u8{} }"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_go: {{ const argv = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const shortopts = "); try self.genExpr(args[1]);
    try self.emitFmt("; _ = shortopts; var opts: std.ArrayList(struct {{ []const u8, []const u8 }}) = .{{}}; var remaining: std.ArrayList([]const u8) = .{{}}; for (argv) |arg| {{ remaining.append(__global_allocator, arg) catch unreachable; }} break :__m{d}_go .{{ opts.items, remaining.items }}; }})", .{id});
}
