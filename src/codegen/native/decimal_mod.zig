/// Python decimal module - Decimal fixed-point arithmetic
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

const ctx_val = "struct { prec: i64 = 28, rounding: []const u8 = \"ROUND_HALF_EVEN\", Emin: i64 = -999999, Emax: i64 = 999999, capitals: i64 = 1, clamp: i64 = 0 }{}";

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "Decimal", genDecimal },
    .{ "setcontext", genSetcontext },
    .{ "getcontext", genGetcontext },
    .{ "localcontext", genLocalcontext },
    .{ "BasicContext", genBasicContext },
    .{ "ExtendedContext", genExtendedContext },
    .{ "DefaultContext", genDefaultContext },
    .{ "ROUND_CEILING", genRoundCeiling },
    .{ "ROUND_DOWN", genRoundDown },
    .{ "ROUND_FLOOR", genRoundFloor },
    .{ "ROUND_HALF_DOWN", genRoundHalfDown },
    .{ "ROUND_HALF_EVEN", genRoundHalfEven },
    .{ "ROUND_HALF_UP", genRoundHalfUp },
    .{ "ROUND_UP", genRoundUp },
    .{ "ROUND_05UP", genRound05Up },
    .{ "DecimalException", genDecimalException },
    .{ "InvalidOperation", genInvalidOperation },
    .{ "DivisionByZero", genDivisionByZero },
    .{ "Overflow", genOverflow },
    .{ "Underflow", genUnderflow },
    .{ "Inexact", genInexact },
    .{ "Rounded", genRounded },
    .{ "Subnormal", genSubnormal },
    .{ "FloatOperation", genFloatOperation },
    .{ "Clamped", genClamped },
});

fn genDecimal(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.emitValue(builder_mod.ZigValue.raw("runtime.Decimal{ .value = 0 }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const b = try self.getBuilder();
    try b.write("runtime.Decimal{ .value = ");
    const output1 = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output1);
    if (args[0] == .constant and args[0].constant.value == .string) {
        const b2 = try self.getBuilder();
        try b2.write("std.fmt.parseFloat(f64, ");
        const out2 = b2.getBodyAndClear();
        try self.output.appendSlice(self.allocator, out2);
        try self.genExpr(args[0]);
        const b3 = try self.getBuilder();
        try b3.write(") catch 0");
        const out3 = b3.getBodyAndClear();
        try self.output.appendSlice(self.allocator, out3);
    } else if (args[0] == .constant) {
        const b2 = try self.getBuilder();
        try b2.write("@as(f64, @floatFromInt(");
        const out2 = b2.getBodyAndClear();
        try self.output.appendSlice(self.allocator, out2);
        try self.genExpr(args[0]);
        const b3 = try self.getBuilder();
        try b3.write("))");
        const out3 = b3.getBodyAndClear();
        try self.output.appendSlice(self.allocator, out3);
    } else {
        try self.genExpr(args[0]);
    }
    {
        const b4 = try self.getBuilder();
        try b4.write(" }");
        const output2 = b4.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output2);
    }
}

fn genSetcontext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("{}"), builder_mod.EmitConfig.forExpression());
}

fn genGetcontext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(ctx_val), builder_mod.EmitConfig.forExpression());
}

fn genLocalcontext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(ctx_val), builder_mod.EmitConfig.forExpression());
}

fn genBasicContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(ctx_val), builder_mod.EmitConfig.forExpression());
}

fn genExtendedContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(ctx_val), builder_mod.EmitConfig.forExpression());
}

fn genDefaultContext(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(ctx_val), builder_mod.EmitConfig.forExpression());
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

fn genDecimalException(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("DecimalException"), builder_mod.EmitConfig.forExpression());
}

fn genInvalidOperation(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("InvalidOperation"), builder_mod.EmitConfig.forExpression());
}

fn genDivisionByZero(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("DivisionByZero"), builder_mod.EmitConfig.forExpression());
}

fn genOverflow(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("Overflow"), builder_mod.EmitConfig.forExpression());
}

fn genUnderflow(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("Underflow"), builder_mod.EmitConfig.forExpression());
}

fn genInexact(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("Inexact"), builder_mod.EmitConfig.forExpression());
}

fn genRounded(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("Rounded"), builder_mod.EmitConfig.forExpression());
}

fn genSubnormal(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("Subnormal"), builder_mod.EmitConfig.forExpression());
}

fn genFloatOperation(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("FloatOperation"), builder_mod.EmitConfig.forExpression());
}

fn genClamped(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.string("Clamped"), builder_mod.EmitConfig.forExpression());
}
