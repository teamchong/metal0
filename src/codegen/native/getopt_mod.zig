/// Python getopt module - C-style parser for command line options
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "getopt", genGetopt },
    .{ "gnu_getopt", genGetopt },
    .{ "GetoptError", genGetoptError },
    .{ "error", genGetoptError },
});

fn genGetopt(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len < 2) {
        try b.emitValue(builder_mod.ZigValue.raw(".{ &[_]struct { []const u8, []const u8 }{}, &[_][]const u8{} }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_go: {{ const argv = ", .{id});
    try self.genExpr(args[0]);
    try self.emit("; const shortopts = ");
    try self.genExpr(args[1]);
    try self.emit("; _ = shortopts; var opts: std.ArrayList(struct { []const u8, []const u8 }) = .{}; var remaining: std.ArrayList([]const u8) = .{}; for (argv) |arg| { remaining.append(__global_allocator, arg) catch unreachable; } break :__m");
    try self.emitFmt("{d}_go .{{ opts.items, remaining.items }}; }})", .{id});
}

fn genGetoptError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.GetoptError"), builder_mod.EmitConfig.forExpression());
}
