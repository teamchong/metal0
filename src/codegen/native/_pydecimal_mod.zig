/// Python _pydecimal module - Pure Python decimal implementation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

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
    // Generate: __m{id}_dec: { _ = arg; break :__m{id}_dec default; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_dec: {{ _ = ", .{id});
    try self.genExpr(args[0]);
    try self.emitFmt("; break :__m{d}_dec ", .{id});
    try self.emit(default ++ "; })");
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
