/// Python getopt module - C-style parser for command line options
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output - uses h.NativeCodegen from mod_helper
fn emitConst(self: *h.NativeCodegen, val: []const u8) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for formatted output
fn emitFmtConst(self: *h.NativeCodegen, comptime fmt: []const u8, args: anytype) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}



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
    try self.withInlineBlock("go", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const argv = ");
            try c.genExpr(a[0]);
            try emitConst(c, "; const shortopts = ");
            try c.genExpr(a[1]);
            try emitFmtConst(c, "; _ = shortopts; var opts: std.ArrayList(struct {{ []const u8, []const u8 }}) = .{{}}; var remaining: std.ArrayList([]const u8) = .{{}}; for (argv) |arg| {{ remaining.append(__global_allocator, arg) catch unreachable; }} break :{s} .{{ opts.items, remaining.items }}", .{label});
        }
    }.emit);
}

fn genGetoptError(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("error.GetoptError"), builder_mod.EmitConfig.forExpression());
}
