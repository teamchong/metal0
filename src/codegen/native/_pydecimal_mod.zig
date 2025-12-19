/// Python _pydecimal module - Pure Python decimal implementation
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
    .{ "decimal", genDecimal },
    .{ "context", genContext },
    .{ "localcontext", genLocalcontext },
    .{ "getcontext", genGetcontext },
    .{ "setcontext", genSetcontext },
});

fn genDecimal(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const default = ".{ .sign = 0, .int = 0, .exp = 0, .is_special = false }";
    if (args.len == 0) {
        try b.emitValue(builder_mod.ZigValue.raw(default), builder_mod.EmitConfig.forExpression());
        return;
    }
    try self.withInlineBlock("dec", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try emitConst(c, "_ = ");
            try c.genExpr(a[0]);
            try emitFmtConst(c, "; break :{s} ", .{label});
            try emitConst(c, default);
        }
    }.emit);
}

fn genContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .prec = 28, .rounding = \"ROUND_HALF_EVEN\", .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genLocalcontext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .prec = 28, .rounding = \"ROUND_HALF_EVEN\", .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genGetcontext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .prec = 28, .rounding = \"ROUND_HALF_EVEN\", .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genSetcontext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}
