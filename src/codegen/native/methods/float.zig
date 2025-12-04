/// Float methods (is_integer, as_integer_ratio, hex, fromhex)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

/// Generate float.is_integer() - returns true if float has integral value
/// Python: (1.0).is_integer() -> True, (1.1).is_integer() -> False
/// Zig: runtime.floatIsInteger(f)
pub fn genIsInteger(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // is_integer takes no arguments
    try self.emit("runtime.floatIsInteger(");
    try self.genExpr(obj);
    try self.emit(")");
}

/// Generate float.as_integer_ratio() - returns (numerator, denominator) tuple
/// Python: (0.5).as_integer_ratio() -> (1, 2)
/// Zig: try runtime.floatAsIntegerRatio(f)
/// Raises ValueError for NaN, OverflowError for Inf
pub fn genAsIntegerRatio(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // as_integer_ratio takes no arguments
    try self.emit("(try runtime.floatAsIntegerRatio(");
    try self.genExpr(obj);
    try self.emit("))");
}

/// Generate float.hex() - returns hexadecimal string representation
/// Python: (255.0).hex() -> '0x1.fe00000000000p+7'
/// Zig: runtime.floatHex(allocator, f)
pub fn genHex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
    try self.emit("runtime.floatHex(");
    try self.emit(alloc_name);
    try self.emit(", ");
    try self.genExpr(obj);
    try self.emit(")");
}

/// Generate float.conjugate() - returns the float itself (for complex number compat)
/// Python: (1.5).conjugate() -> 1.5
pub fn genConjugate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    // For floats, conjugate() just returns the value itself
    try self.genExpr(obj);
}

/// Generate float.__floor__() - returns largest int <= value (as BigInt for large values)
/// Python: (1.7).__floor__() -> 1, (1e200).__floor__() -> BigInt
/// Zig: try runtime.floatFloor(allocator, f)
pub fn genFloor(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
    try self.emit("(try runtime.floatFloor(");
    try self.emit(alloc_name);
    try self.emit(", ");
    try self.genExpr(obj);
    try self.emit("))");
}

/// Generate float.__ceil__() - returns smallest int >= value (as BigInt for large values)
/// Python: (1.3).__ceil__() -> 2
/// Zig: try runtime.floatCeil(allocator, f)
pub fn genCeil(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
    try self.emit("(try runtime.floatCeil(");
    try self.emit(alloc_name);
    try self.emit(", ");
    try self.genExpr(obj);
    try self.emit("))");
}

/// Generate float.__trunc__() - truncate towards zero (as BigInt for large values)
/// Python: (-1.7).__trunc__() -> -1
/// Zig: try runtime.floatTrunc(allocator, f)
pub fn genTrunc(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
    try self.emit("(try runtime.floatTrunc(");
    try self.emit(alloc_name);
    try self.emit(", ");
    try self.genExpr(obj);
    try self.emit("))");
}

/// Generate float.__round__([ndigits]) - round to nearest
/// Python: (1.5).__round__() -> 2, (1.25).__round__(1) -> 1.2
/// Zig: try runtime.floatRound(allocator, f) for no args
pub fn genRound(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
    if (args.len == 0) {
        try self.emit("(try runtime.floatRound(");
        try self.emit(alloc_name);
        try self.emit(", ");
        try self.genExpr(obj);
        try self.emit("))");
    } else {
        // Round to ndigits decimal places - returns float, not int
        try self.emit("blk: { const __ndigits = ");
        try self.genExpr(args[0]);
        try self.emit("; const __mult = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(__ndigits))); ");
        try self.emit("break :blk @round(");
        try self.genExpr(obj);
        try self.emit(" * __mult) / __mult; }");
    }
}

/// Generate float.__truediv__(other) - true division
/// Python: (10.0).__truediv__(3) -> 3.333...
pub fn genTruediv(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // obj / args[0]
    try self.emit("((");
    try self.genExpr(obj);
    try self.emit(") / @as(f64, @floatFromInt(");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("1");
    }
    try self.emit(")))");
}

/// Generate float.__rtruediv__(other) - reverse true division
/// Python: (10.0).__rtruediv__(3) -> 0.3 (i.e., 3 / 10.0)
pub fn genRtruediv(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // args[0] / obj
    try self.emit("(@as(f64, @floatFromInt(");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("1");
    }
    try self.emit(")) / ");
    try self.genExpr(obj);
    try self.emit(")");
}

/// Generate float.__floordiv__(other) - floor division
/// Python: (10.0).__floordiv__(3) -> 3.0
pub fn genFloordiv(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    try self.emit("@as(f64, @floatFromInt(@divFloor(@as(i64, @intFromFloat(");
    try self.genExpr(obj);
    try self.emit(")), ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("1");
    }
    try self.emit(")))");
}

/// Generate float.__mod__(other) - modulo
/// Python: (10.0).__mod__(3) -> 1.0
pub fn genMod(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    try self.emit("@mod(");
    try self.genExpr(obj);
    try self.emit(", @as(f64, @floatFromInt(");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("1");
    }
    try self.emit(")))");
}
