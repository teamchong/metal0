/// Python contextvars module - Context Variables
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
    .{ "ContextVar", genContextVar },
    .{ "Token", genToken },
    .{ "Context", genContext },
    .{ "copy_context", genCopyContext },
});

fn genContextVar(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const default = ".{ .name = \"\", .value = null }";
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw(default), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("cv", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "const __v = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; break :{s} .{{ .name = __v, .value = null }}", .{label});
        }
    }.emit);
}

fn genToken(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .var = null, .old_value = null }"), builder_mod.EmitConfig.forExpression());
}

fn genContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .data = hashmap_helper.StringHashMap(?*anyopaque).init(__global_allocator) }"), builder_mod.EmitConfig.forExpression());
}

fn genCopyContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .data = hashmap_helper.StringHashMap(?*anyopaque).init(__global_allocator) }"), builder_mod.EmitConfig.forExpression());
}
