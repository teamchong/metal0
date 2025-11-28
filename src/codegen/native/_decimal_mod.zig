/// Python _decimal module - Internal decimal support (C accelerator)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate _decimal.Decimal(value=0, context=None)
pub fn genDecimal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const v = ");
        try self.genExpr(args[0]);
        try self.emit("; _ = v; break :blk .{ .sign = 0, .digits = &[_]u8{}, .exp = 0 }; }");
    } else {
        try self.emit(".{ .sign = 0, .digits = &[_]u8{}, .exp = 0 }");
    }
}

/// Generate _decimal.Context(prec=28, rounding=ROUND_HALF_EVEN, Emin=-999999, Emax=999999, capitals=1, clamp=0, flags=None, traps=None)
pub fn genContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }");
}

/// Generate _decimal.localcontext(ctx=None, **kwargs)
pub fn genLocalcontext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }");
}

/// Generate _decimal.getcontext()
pub fn genGetcontext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }");
}

/// Generate _decimal.setcontext(context)
pub fn genSetcontext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate _decimal.BasicContext constant
pub fn genBasicContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .prec = 9, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }");
}

/// Generate _decimal.ExtendedContext constant
pub fn genExtendedContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .prec = 9, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }");
}

/// Generate _decimal.DefaultContext constant
pub fn genDefaultContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .prec = 28, .rounding = 4, .Emin = -999999, .Emax = 999999, .capitals = 1, .clamp = 0 }");
}

/// Generate _decimal.MAX_PREC constant
pub fn genMaxPrec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 999999999999999999)");
}

/// Generate _decimal.MAX_EMAX constant
pub fn genMaxEmax(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 999999999999999999)");
}

/// Generate _decimal.MIN_EMIN constant
pub fn genMinEmin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, -999999999999999999)");
}

/// Generate _decimal.MIN_ETINY constant
pub fn genMinEtiny(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, -999999999999999999)");
}

/// Generate _decimal.ROUND_CEILING constant
pub fn genRoundCeiling(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_CEILING\"");
}

/// Generate _decimal.ROUND_DOWN constant
pub fn genRoundDown(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_DOWN\"");
}

/// Generate _decimal.ROUND_FLOOR constant
pub fn genRoundFloor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_FLOOR\"");
}

/// Generate _decimal.ROUND_HALF_DOWN constant
pub fn genRoundHalfDown(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_HALF_DOWN\"");
}

/// Generate _decimal.ROUND_HALF_EVEN constant
pub fn genRoundHalfEven(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_HALF_EVEN\"");
}

/// Generate _decimal.ROUND_HALF_UP constant
pub fn genRoundHalfUp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_HALF_UP\"");
}

/// Generate _decimal.ROUND_UP constant
pub fn genRoundUp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_UP\"");
}

/// Generate _decimal.ROUND_05UP constant
pub fn genRound05Up(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_05UP\"");
}

/// Generate _decimal.DecimalException class
pub fn genDecimalException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.DecimalException");
}

/// Generate _decimal.InvalidOperation class
pub fn genInvalidOperation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.InvalidOperation");
}

/// Generate _decimal.DivisionByZero class
pub fn genDivisionByZero(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.DivisionByZero");
}

/// Generate _decimal.Overflow class
pub fn genOverflow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.Overflow");
}

/// Generate _decimal.Underflow class
pub fn genUnderflow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.Underflow");
}

/// Generate _decimal.Inexact class
pub fn genInexact(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.Inexact");
}

/// Generate _decimal.Rounded class
pub fn genRounded(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.Rounded");
}

/// Generate _decimal.Subnormal class
pub fn genSubnormal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.Subnormal");
}

/// Generate _decimal.Clamped class
pub fn genClamped(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.Clamped");
}
