/// Python _decimal module - Internal decimal support (C accelerator)
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
    .{ "Decimal", genDecimal },
    .{ "Context", genContext },
    .{ "localcontext", genLocalcontext },
    .{ "getcontext", genGetcontext },
    .{ "setcontext", genSetcontext },
    .{ "BasicContext", genBasicContext },
    .{ "ExtendedContext", genExtendedContext },
    .{ "DefaultContext", genDefaultContext },
    .{ "MAX_PREC", genMaxPrec },
    .{ "MAX_EMAX", genMaxEmax },
    .{ "MIN_EMIN", genMinEmin },
    .{ "MIN_ETINY", genMinEtiny },
    .{ "ROUND_CEILING", genRoundCeiling },
    .{ "ROUND_DOWN", genRoundDown },
    .{ "ROUND_FLOOR", genRoundFloor },
    .{ "ROUND_HALF_DOWN", genRoundHalfDown },
    .{ "ROUND_HALF_EVEN", genRoundHalfEven },
    .{ "ROUND_HALF_UP", genRoundHalfUp },
    .{ "ROUND_UP", genRoundUp },
    .{ "ROUND_05UP", genRound05Up },
});

fn genDecimal(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    const default = ".{ .sign = 0, .digits = &[_]u8{}, .exp = 0 }";
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
    try b.emitValue(builder_mod.ZigValue.raw(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genLocalcontext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genGetcontext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genSetcontext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genBasicContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .prec = 9, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genExtendedContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .prec = 9, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genDefaultContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genMaxPrec(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 999999999999999999)"), builder_mod.EmitConfig.forExpression());
}

fn genMaxEmax(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, 999999999999999999)"), builder_mod.EmitConfig.forExpression());
}

fn genMinEmin(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, -999999999999999999)"), builder_mod.EmitConfig.forExpression());
}

fn genMinEtiny(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i64, -999999999999999999)"), builder_mod.EmitConfig.forExpression());
}

fn genRoundCeiling(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("ROUND_CEILING"), builder_mod.EmitConfig.forExpression());
}

fn genRoundDown(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("ROUND_DOWN"), builder_mod.EmitConfig.forExpression());
}

fn genRoundFloor(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("ROUND_FLOOR"), builder_mod.EmitConfig.forExpression());
}

fn genRoundHalfDown(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("ROUND_HALF_DOWN"), builder_mod.EmitConfig.forExpression());
}

fn genRoundHalfEven(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("ROUND_HALF_EVEN"), builder_mod.EmitConfig.forExpression());
}

fn genRoundHalfUp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("ROUND_HALF_UP"), builder_mod.EmitConfig.forExpression());
}

fn genRoundUp(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("ROUND_UP"), builder_mod.EmitConfig.forExpression());
}

fn genRound05Up(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("ROUND_05UP"), builder_mod.EmitConfig.forExpression());
}
