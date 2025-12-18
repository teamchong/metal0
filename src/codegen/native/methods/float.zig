/// Float methods (is_integer, as_integer_ratio, hex, fromhex)
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

/// Check if a float expression is uncertain (needs PyValue operations)
/// Two-Flow: routes uncertain floats to PyValue extraction
fn isFloatUncertain(self: *NativeCodegen, obj: ast.Node) bool {
    if (obj == .name) {
        const name = obj.name.id;
        // Check scoped vars first (for loop variables, function params)
        // then fall back to global var_types
        const var_type = self.type_inferrer.getScopedVar(name) orelse
            self.type_inferrer.var_types.get(name);
        if (var_type) |vt| {
            switch (vt) {
                .pyvalue, .unknown => return true,
                else => {},
            }
        }
        return false;
    }
    return false;
}

/// Helper to emit float expression, extracting from PyValue if uncertain
fn emitFloatExpr(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    if (isFloatUncertain(self, obj)) {
        // Extract float from PyValue using .asFloat()
        try self.genExpr(obj);
        try self.emit(".asFloat()");
    } else {
        try self.genExpr(obj);
    }
}

/// Generate float.is_integer() - returns true if float has integral value
/// Python: (1.0).is_integer() -> True, (1.1).is_integer() -> False
/// Two-Flow: Extracts float from PyValue if uncertain
/// Zig: runtime.floatIsInteger(f)
pub fn genIsInteger(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // is_integer takes no arguments
    try self.emit("runtime.floatIsInteger(");
    try emitFloatExpr(self, obj);
    try self.emit(")");
}

/// Generate float.as_integer_ratio() - returns (numerator, denominator) tuple as BigInt
/// Python: (0.5).as_integer_ratio() -> (1, 2)
/// Two-Flow: Extracts float from PyValue if uncertain
/// Zig: try runtime.floatAsIntegerRatioBigInt(allocator, f)
/// Returns IntegerRatioResult with .numerator and .denominator BigInt fields
/// For tuple unpacking n, d = f.as_integer_ratio(), codegen converts to .{n, d} tuple
/// Raises ValueError for NaN, OverflowError for Inf
pub fn genAsIntegerRatio(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // as_integer_ratio takes no arguments
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
    // Return a struct that can be unpacked: { BigInt, BigInt }
    // The IntegerRatioResult has .numerator and .denominator, we convert to anonymous tuple
    const label = try self.emitInlineBlockStart("ratio");
    try self.emit("const __ratio = try runtime.floatAsIntegerRatioBigInt(");
    try self.emit(alloc_name);
    try self.emit(", ");
    try emitFloatExpr(self, obj);
    try self.emitFmt("); break :{s} .{{ __ratio.numerator, __ratio.denominator }}; ", .{label});
    try self.emitInlineBlockEnd();
}

/// Generate float.hex() - returns hexadecimal string representation
/// Python: (255.0).hex() -> '0x1.fe00000000000p+7'
/// Two-Flow: Extracts float from PyValue if uncertain
/// Zig: try runtime.floatHex(allocator, f)
pub fn genHex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
    try self.emit("try runtime.floatHex(");
    try self.emit(alloc_name);
    try self.emit(", ");
    try emitFloatExpr(self, obj);
    try self.emit(")");
}

/// Generate float.conjugate() - returns the float itself (for complex number compat)
/// Python: (1.5).conjugate() -> 1.5
/// Two-Flow: Extracts float from PyValue if uncertain
pub fn genConjugate(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    // For floats, conjugate() just returns the value itself
    try emitFloatExpr(self, obj);
}

/// Generate float.__floor__() - returns largest int <= value
/// Python: (1.7).__floor__() -> 1, (1e200).__floor__() -> BigInt
/// Two-Flow: Extracts float from PyValue if uncertain
/// Returns IntResult which handles both small (i64) and large (BigInt) values
/// assertEqual and comparison codegen handle IntResult appropriately
/// In assertRaises context (inside_try_body), propagates errors for expectError to catch
/// Zig: runtime.floatFloorBig(allocator, f) catch unreachable (or try in assertRaises context)
pub fn genFloor(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
    if (self.inside_try_body) {
        // In assertRaises context - return error union for expectError to catch
        try self.emit("(runtime.floatFloorBig(");
        try self.emit(alloc_name);
        try self.emit(", ");
        try emitFloatExpr(self, obj);
        try self.emit("))");
    } else {
        try self.emit("(runtime.floatFloorBig(");
        try self.emit(alloc_name);
        try self.emit(", ");
        try emitFloatExpr(self, obj);
        try self.emit(") catch unreachable)");
    }
}

/// Generate float.__ceil__() - returns smallest int >= value
/// Python: (1.3).__ceil__() -> 2, (1e200).__ceil__() -> BigInt
/// Two-Flow: Extracts float from PyValue if uncertain
/// Returns IntResult which handles both small (i64) and large (BigInt) values
/// assertEqual and comparison codegen handle IntResult appropriately
/// In assertRaises context (inside_try_body), propagates errors for expectError to catch
/// Zig: runtime.floatCeilBig(allocator, f) catch unreachable (or try in assertRaises context)
pub fn genCeil(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
    if (self.inside_try_body) {
        // In assertRaises context - return error union for expectError to catch
        try self.emit("(runtime.floatCeilBig(");
        try self.emit(alloc_name);
        try self.emit(", ");
        try emitFloatExpr(self, obj);
        try self.emit("))");
    } else {
        try self.emit("(runtime.floatCeilBig(");
        try self.emit(alloc_name);
        try self.emit(", ");
        try emitFloatExpr(self, obj);
        try self.emit(") catch unreachable)");
    }
}

/// Generate float.__trunc__() - truncate towards zero (as BigInt for large values)
/// Python: (-1.7).__trunc__() -> -1
/// Two-Flow: Extracts float from PyValue if uncertain
/// Zig: try runtime.floatTrunc(allocator, f)
pub fn genTrunc(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
    try self.emit("(try runtime.floatTrunc(");
    try self.emit(alloc_name);
    try self.emit(", ");
    try emitFloatExpr(self, obj);
    try self.emit("))");
}

/// Generate float.__round__([ndigits]) - round to nearest
/// Python: (1.5).__round__() -> 2, (1.25).__round__(1) -> 1.2
/// Two-Flow: Extracts float from PyValue if uncertain
/// Zig: try runtime.floatRound(allocator, f) for no args
pub fn genRound(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
    if (args.len == 0) {
        try self.emit("(try runtime.floatRound(");
        try self.emit(alloc_name);
        try self.emit(", ");
        try emitFloatExpr(self, obj);
        try self.emit("))");
    } else {
        // Round to ndigits decimal places - returns float, not int
        const label = try self.emitInlineBlockStart("round");
        try self.emit("const __ndigits = ");
        try self.genExpr(args[0]);
        try self.emit("; const __mult = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(__ndigits))); ");
        try self.emitFmt("break :{s} @round(", .{label});
        try emitFloatExpr(self, obj);
        try self.emit(" * __mult) / __mult; ");
        try self.emitInlineBlockEnd();
    }
}

/// Generate float.__truediv__(other) - true division
/// Python: (10.0).__truediv__(3) -> 3.333...
/// Handles both int and BigInt divisors
pub fn genTruediv(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // obj / args[0], with runtime type dispatch for BigInt
    try self.emit("((");
    try self.genExpr(obj);
    try self.emit(") / runtime.toFloat(");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("1");
    }
    try self.emit("))");
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
