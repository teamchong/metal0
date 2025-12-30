/// Float methods (is_integer, as_integer_ratio, hex, fromhex)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

// isFloatUncertain replaced by self.isExprUncertain() (DRY consolidation)

/// Helper to emit float expression, extracting from PyValue if uncertain
fn emitFloatExpr(self: *NativeCodegen, obj: ast.Node) CodegenError!void {
    if (self.isExprUncertain(obj)) {
        // Extract float from PyValue using .asFloat()
        try self.genExpr(obj);
        try self.emit(".asFloat()");
    } else {
        try self.genExpr(obj);
    }
}

/// Helper to emit runtime float call: (try runtime.{func}(allocator, floatExpr))
/// Handles error handling variations based on context
/// Uses withParensCtx for guaranteed bracket matching
fn emitRuntimeFloatCall(self: *NativeCodegen, func: []const u8, obj: ast.Node) CodegenError!void {
    const Ctx = struct { f: []const u8, o: ast.Node, assert_raises: bool, try_body: bool };
    try self.withParensCtx(Ctx{
        .f = func,
        .o = obj,
        .assert_raises = self.in_assert_raises_context,
        .try_body = self.inside_try_body,
    }, struct {
        pub fn emit(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            if (ctx.assert_raises) {
                try s.emit("runtime.");
            } else if (ctx.try_body) {
                try s.emit("try runtime.");
            } else {
                try s.emit("runtime.");
            }
            try s.emit(ctx.f);
            try s.emitCallCtx("", ctx.o, struct {
                pub fn inner(s2: *NativeCodegen, o: ast.Node) CodegenError!void {
                    try s2.emit("__global_allocator, ");
                    try emitFloatExpr(s2, o);
                }
            }.inner);
            if (!ctx.assert_raises and !ctx.try_body) {
                try s.emit(" catch unreachable");
            }
        }
    }.emit);
}

/// Helper to emit simple runtime float call: runtime.{func}(floatExpr)
/// Uses auto-close pattern for guaranteed bracket matching
fn emitSimpleFloatCall(self: *NativeCodegen, func: []const u8, obj: ast.Node) CodegenError!void {
    try self.emit("runtime.");
    try self.emit(func);
    const Ctx = struct { o: ast.Node };
    try self.emitCallCtx("", Ctx{ .o = obj }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try emitFloatExpr(s, ctx.o);
        }
    }.f);
}

/// Helper to emit try runtime float call with allocator: try runtime.{func}(allocator, floatExpr)
/// Uses auto-close pattern for guaranteed bracket matching
fn emitTryFloatCallWithAlloc(self: *NativeCodegen, func: []const u8, obj: ast.Node) CodegenError!void {
    try self.emit("try runtime.");
    try self.emit(func);
    const Ctx = struct { o: ast.Node };
    try self.emitCallCtx("", Ctx{ .o = obj }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emit("__global_allocator, ");
            try emitFloatExpr(s, ctx.o);
        }
    }.f);
}

/// Helper to emit wrapped try runtime float call: (try runtime.{func}(allocator, floatExpr))
/// Uses withParensCtx for guaranteed bracket matching
fn emitParenTryFloatCallWithAlloc(self: *NativeCodegen, func: []const u8, obj: ast.Node) CodegenError!void {
    const Ctx = struct { f: []const u8, o: ast.Node };
    try self.withParensCtx(Ctx{ .f = func, .o = obj }, struct {
        pub fn emit(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emit("try runtime.");
            try s.emit(ctx.f);
            try s.emitCallCtx("", ctx.o, struct {
                pub fn inner(s2: *NativeCodegen, o: ast.Node) CodegenError!void {
                    try s2.emit("__global_allocator, ");
                    try emitFloatExpr(s2, o);
                }
            }.inner);
        }
    }.emit);
}

/// Generate float.is_integer() - returns true if float has integral value
/// Python: (1.0).is_integer() -> True, (1.1).is_integer() -> False
/// Two-Flow: Extracts float from PyValue if uncertain
/// Zig: runtime.floatIsInteger(f)
pub fn genIsInteger(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // is_integer takes no arguments
    try emitSimpleFloatCall(self, "floatIsInteger", obj);
}

/// Generate float.as_integer_ratio() - returns (numerator, denominator) tuple as UnifiedInt
/// Python: (0.5).as_integer_ratio() -> (1, 2)
/// Two-Flow: Extracts float from PyValue if uncertain
/// Zig: try runtime.floatAsIntegerRatioBigInt(allocator, f)
/// Returns IntegerRatioResult with .numerator and .denominator BigInt fields
/// For tuple unpacking n, d = f.as_integer_ratio(), codegen converts to .{n, d} tuple
/// Raises ValueError for NaN, OverflowError for Inf
pub fn genAsIntegerRatio(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args; // as_integer_ratio takes no arguments
    // Return a struct that can be unpacked: { UnifiedInt, UnifiedInt }
    // The IntegerRatioResult has .numerator and .denominator BigInt fields, convert to UnifiedInt
    try self.withInlineBlock("ratio", obj, struct {
        fn emit(s: *NativeCodegen, label: []const u8, o: ast.Node) CodegenError!void {
            try s.emit("const __ratio = try runtime.floatAsIntegerRatioBigInt(__global_allocator, ");
            try emitFloatExpr(s, o);
            try s.emitFmt("); break :{s} .{{ try runtime.UnifiedInt.fromBigIntValue(__global_allocator, &__ratio.numerator), try runtime.UnifiedInt.fromBigIntValue(__global_allocator, &__ratio.denominator) }}", .{label});
        }
    }.emit);
}

/// Generate float.hex() - returns hexadecimal string representation
/// Python: (255.0).hex() -> '0x1.fe00000000000p+7'
/// Two-Flow: Extracts float from PyValue if uncertain
/// Zig: try runtime.floatHex(allocator, f)
pub fn genHex(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try emitTryFloatCallWithAlloc(self, "floatHex", obj);
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
/// In assertRaises context, returns error union for expectError to catch
/// Zig: runtime.floatFloorBig(allocator, f) catch unreachable (or raw in assertRaises context)
pub fn genFloor(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try emitRuntimeFloatCall(self, "floatFloorBig", obj);
}

/// Generate float.__ceil__() - returns smallest int >= value
/// Python: (1.3).__ceil__() -> 2, (1e200).__ceil__() -> BigInt
/// Two-Flow: Extracts float from PyValue if uncertain
/// Returns IntResult which handles both small (i64) and large (BigInt) values
/// assertEqual and comparison codegen handle IntResult appropriately
/// In assertRaises context, returns error union for expectError to catch
/// Zig: runtime.floatCeilBig(allocator, f) catch unreachable (or raw in assertRaises context)
pub fn genCeil(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try emitRuntimeFloatCall(self, "floatCeilBig", obj);
}

/// Generate float.__trunc__() - truncate towards zero (as BigInt for large values)
/// Python: (-1.7).__trunc__() -> -1
/// Two-Flow: Extracts float from PyValue if uncertain
/// Zig: try runtime.floatTrunc(allocator, f)
pub fn genTrunc(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    _ = args;
    try emitParenTryFloatCallWithAlloc(self, "floatTrunc", obj);
}

/// Generate float.__round__([ndigits]) - round to nearest
/// Python: (1.5).__round__() -> 2, (1.25).__round__(1) -> 1.2
/// Two-Flow: Extracts float from PyValue if uncertain
/// Zig: try runtime.floatRound(allocator, f) for no args
pub fn genRound(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitParenTryFloatCallWithAlloc(self, "floatRound", obj);
    } else {
        // Round to ndigits decimal places - returns float, not int
        // Use banker's rounding (round half to even) for Python semantics
        const Ctx = struct { o: ast.Node, a: ast.Node };
        try self.withInlineBlock("round", Ctx{ .o = obj, .a = args[0] }, struct {
            fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
                try s.emit("const __ndigits = ");
                try s.genExpr(ctx.a);
                try s.emit("; const __mult = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(__ndigits))); ");
                try s.emitFmt("break :{s} runtime.builtins.bankersRound(", .{label});
                try emitFloatExpr(s, ctx.o);
                try s.emit(" * __mult) / __mult");
            }
        }.emit);
    }
}

/// Generate float.__truediv__(other) - true division
/// Python: (10.0).__truediv__(3) -> 3.333...
/// Handles both int and BigInt divisors
pub fn genTruediv(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // obj / args[0], with runtime type dispatch for BigInt
    const Ctx = struct { o: ast.Node, a: []ast.Node };
    try self.withParensCtx(Ctx{ .o = obj, .a = args }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.withParensCtx(ctx.o, struct {
                pub fn inner(s2: *NativeCodegen, o: ast.Node) CodegenError!void {
                    try s2.genExpr(o);
                }
            }.inner);
            try s.emit(" / ");
            try s.emitCallCtx("runtime.toFloat", ctx.a, struct {
                pub fn inner2(s2: *NativeCodegen, a: []ast.Node) CodegenError!void {
                    if (a.len > 0) {
                        try s2.genExpr(a[0]);
                    } else {
                        try s2.emit("1");
                    }
                }
            }.inner2);
        }
    }.f);
}

/// Generate float.__rtruediv__(other) - reverse true division
/// Python: (10.0).__rtruediv__(3) -> 0.3 (i.e., 3 / 10.0)
pub fn genRtruediv(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    // args[0] / obj
    const Ctx = struct { o: ast.Node, a: []ast.Node };
    try self.withParensCtx(Ctx{ .o = obj, .a = args }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emitCallCtx("@as", ctx.a, struct {
                pub fn inner(s2: *NativeCodegen, a: []ast.Node) CodegenError!void {
                    try s2.emit("f64, ");
                    try s2.emitCallCtx("@floatFromInt", a, struct {
                        pub fn inner2(s3: *NativeCodegen, args2: []ast.Node) CodegenError!void {
                            if (args2.len > 0) {
                                try s3.genExpr(args2[0]);
                            } else {
                                try s3.emit("1");
                            }
                        }
                    }.inner2);
                }
            }.inner);
            try s.emit(" / ");
            try s.genExpr(ctx.o);
        }
    }.f);
}

/// Generate float.__floordiv__(other) - floor division
/// Python: (10.0).__floordiv__(3) -> 3.0
pub fn genFloordiv(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const Ctx = struct { o: ast.Node, a: []ast.Node };
    try self.emitCallCtx("@as", Ctx{ .o = obj, .a = args }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emit("f64, ");
            try s.emitCallCtx("@floatFromInt", ctx, struct {
                pub fn inner(s2: *NativeCodegen, ctx2: Ctx) CodegenError!void {
                    try s2.emitCallCtx("@divFloor", ctx2, struct {
                        pub fn inner2(s3: *NativeCodegen, ctx3: Ctx) CodegenError!void {
                            try s3.emitCallCtx("@as", ctx3.o, struct {
                                pub fn inner3(s4: *NativeCodegen, o: ast.Node) CodegenError!void {
                                    try s4.emit("i64, ");
                                    try s4.emitCallCtx("@intFromFloat", o, struct {
                                        pub fn inner4(s5: *NativeCodegen, obj2: ast.Node) CodegenError!void {
                                            try s5.genExpr(obj2);
                                        }
                                    }.inner4);
                                }
                            }.inner3);
                            try s3.emit(", ");
                            if (ctx3.a.len > 0) {
                                try s3.genExpr(ctx3.a[0]);
                            } else {
                                try s3.emit("1");
                            }
                        }
                    }.inner2);
                }
            }.inner);
        }
    }.f);
}

/// Generate float.__mod__(other) - modulo
/// Python: (10.0).__mod__(3) -> 1.0
pub fn genMod(self: *NativeCodegen, obj: ast.Node, args: []ast.Node) CodegenError!void {
    const Ctx = struct { o: ast.Node, a: []ast.Node };
    try self.emitCallCtx("@mod", Ctx{ .o = obj, .a = args }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.genExpr(ctx.o);
            try s.emit(", ");
            try s.emitCallCtx("@as", ctx.a, struct {
                pub fn inner(s2: *NativeCodegen, a: []ast.Node) CodegenError!void {
                    try s2.emit("f64, ");
                    try s2.emitCallCtx("@floatFromInt", a, struct {
                        pub fn innermost(s3: *NativeCodegen, args2: []ast.Node) CodegenError!void {
                            if (args2.len > 0) {
                                try s3.genExpr(args2[0]);
                            } else {
                                try s3.emit("1");
                            }
                        }
                    }.innermost);
                }
            }.inner);
        }
    }.f);
}
