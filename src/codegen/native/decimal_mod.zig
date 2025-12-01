/// Python decimal module - Decimal fixed-point arithmetic
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "Decimal", genDecimal },
    .{ "getcontext", genGetcontext },
    .{ "setcontext", genSetcontext },
    .{ "localcontext", genLocalcontext },
    .{ "BasicContext", genBasicContext },
    .{ "ExtendedContext", genExtendedContext },
    .{ "DefaultContext", genDefaultContext },
    .{ "ROUND_CEILING", genROUND_CEILING },
    .{ "ROUND_DOWN", genROUND_DOWN },
    .{ "ROUND_FLOOR", genROUND_FLOOR },
    .{ "ROUND_HALF_DOWN", genROUND_HALF_DOWN },
    .{ "ROUND_HALF_EVEN", genROUND_HALF_EVEN },
    .{ "ROUND_HALF_UP", genROUND_HALF_UP },
    .{ "ROUND_UP", genROUND_UP },
    .{ "ROUND_05UP", genROUND_05UP },
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

/// Generate decimal.Decimal(value) -> runtime.Decimal
pub fn genDecimal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("runtime.Decimal{ .value = 0 }");
        return;
    }

    try self.emit("runtime.Decimal{ .value = ");
    // Handle string or numeric input
    if (args[0] == .constant) {
        if (args[0].constant.value == .string) {
            try self.emit("std.fmt.parseFloat(f64, ");
            try self.genExpr(args[0]);
            try self.emit(") catch 0");
        } else {
            try self.emit("@as(f64, @floatFromInt(");
            try self.genExpr(args[0]);
            try self.emit("))");
        }
    } else {
        try self.genExpr(args[0]);
    }
    try self.emit(" }");
}

/// Generate decimal.getcontext() -> Context
pub fn genGetcontext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("struct {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("prec: i64 = 28,\n");
    try self.emitIndent();
    try self.emit("rounding: []const u8 = \"ROUND_HALF_EVEN\",\n");
    try self.emitIndent();
    try self.emit("Emin: i64 = -999999,\n");
    try self.emitIndent();
    try self.emit("Emax: i64 = 999999,\n");
    try self.emitIndent();
    try self.emit("capitals: i64 = 1,\n");
    try self.emitIndent();
    try self.emit("clamp: i64 = 0,\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}{}");
}

/// Generate decimal.setcontext(context) -> None
pub fn genSetcontext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate decimal.localcontext(ctx=None) -> context manager
pub fn genLocalcontext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genGetcontext(self, args);
}

/// Generate decimal.BasicContext constant
pub fn genBasicContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genGetcontext(self, args);
}

/// Generate decimal.ExtendedContext constant
pub fn genExtendedContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genGetcontext(self, args);
}

/// Generate decimal.DefaultContext constant
pub fn genDefaultContext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genGetcontext(self, args);
}

/// Rounding constants
pub fn genROUND_CEILING(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_CEILING\"");
}

pub fn genROUND_DOWN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_DOWN\"");
}

pub fn genROUND_FLOOR(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_FLOOR\"");
}

pub fn genROUND_HALF_DOWN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_HALF_DOWN\"");
}

pub fn genROUND_HALF_EVEN(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_HALF_EVEN\"");
}

pub fn genROUND_HALF_UP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_HALF_UP\"");
}

pub fn genROUND_UP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_UP\"");
}

pub fn genROUND_05UP(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"ROUND_05UP\"");
}

/// Exception types
pub fn genDecimalException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"DecimalException\"");
}

pub fn genInvalidOperation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"InvalidOperation\"");
}

pub fn genDivisionByZero(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"DivisionByZero\"");
}

pub fn genOverflow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Overflow\"");
}

pub fn genUnderflow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Underflow\"");
}

pub fn genInexact(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Inexact\"");
}

pub fn genRounded(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Rounded\"");
}

pub fn genSubnormal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Subnormal\"");
}

pub fn genFloatOperation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"FloatOperation\"");
}

pub fn genClamped(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"Clamped\"");
}
