/// Python _functools module - C accelerator for functools (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

// MIGRATED TO ZIGBUILDER

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "reduce", genReduce },
    .{ "cmp_to_key", genCmpToKey },
});

fn genReduce(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 2) {
        try self.withInlineBlock("red", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v0 = ");
                try c.genExpr(a[0]);
                try c.emit("; const __v1 = ");
                try c.genExpr(a[1]);
                try c.emitFmt("; _ = __v1; break :{s} __v0", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.null_(), builder_mod.EmitConfig.forExpression());
    }
}

fn genCmpToKey(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.withInlineBlock("ctk", args, struct {
            fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
                try c.emit("const __v = ");
                try c.genExpr(a[0]);
                try c.emitFmt("; break :{s} .{{ .cmp = __v }}", .{label});
            }
        }.emit);
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{}"), builder_mod.EmitConfig.forExpression());
    }
}
