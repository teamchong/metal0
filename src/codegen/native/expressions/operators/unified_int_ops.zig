/// UnifiedInt and Complex number operations
/// Handles auto-promoting i64/BigInt arithmetic and complex number math
///
/// MIGRATION STATUS: Using ZigBuilder for structured code generation
/// - Uses captureExpr() to bridge AST expressions to ZigValue
/// - Emits using emitZigValue() for type-safe output
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;
const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;

// MIGRATED TO ZIGBUILDER

// ============================================
// UnifiedInt/Complex operation helpers - auto-closing patterns
// ============================================

/// Emit UnifiedInt binary op: runtime.unified_int_ops.func(left, right, allocator)
/// Uses auto-close pattern to guarantee matching parentheses
fn emitUnifiedIntBinaryOp(
    self: *NativeCodegen,
    func: []const u8,
    left_operand: ZigValue,
    left_type: NativeType,
    right_operand: ZigValue,
    right_type: NativeType,
) CodegenError!void {
    try self.emit("runtime.unified_int_ops.");
    try self.emit(func);
    const Ctx = struct { s: *NativeCodegen, lo: ZigValue, lt: NativeType, ro: ZigValue, rt: NativeType };
    try self.withParensCtx(Ctx{ .s = self, .lo = left_operand, .lt = left_type, .ro = right_operand, .rt = right_type }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try emitAsUnifiedInt(ctx.s, ctx.lo, ctx.lt);
            try s.emit(", ");
            try emitAsUnifiedInt(ctx.s, ctx.ro, ctx.rt);
            try s.emit(", __global_allocator");
        }
    }.f);
}

/// Emit UnifiedInt shift/pow op: runtime.unified_int_ops.func(left, @as(u32, right), allocator)
/// Uses auto-close pattern to guarantee matching parentheses
fn emitUnifiedIntShiftOp(
    self: *NativeCodegen,
    func: []const u8,
    left_operand: ZigValue,
    left_type: NativeType,
    right_operand: ZigValue,
) CodegenError!void {
    try self.emit("runtime.unified_int_ops.");
    try self.emit(func);
    const Ctx = struct { s: *NativeCodegen, lo: ZigValue, lt: NativeType, ro: ZigValue };
    try self.withParensCtx(Ctx{ .s = self, .lo = left_operand, .lt = left_type, .ro = right_operand }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try emitAsUnifiedInt(ctx.s, ctx.lo, ctx.lt);
            try s.emit(", @as(u32, @intCast");
            const Inner = struct { o: ZigValue };
            try s.withParensCtx(Inner{ .o = ctx.ro }, struct {
                pub fn g(si: *NativeCodegen, inner: Inner) CodegenError!void {
                    try si.emitZigValue(inner.o);
                }
            }.g);
            try s.emit("), __global_allocator");
        }
    }.f);
}

/// Emit complex binary op: left.method(right)
/// Uses auto-close pattern to guarantee matching parentheses
fn emitComplexBinaryOp(
    self: *NativeCodegen,
    method: []const u8,
    left_operand: ZigValue,
    left_type: NativeType,
    right_operand: ZigValue,
    right_type: NativeType,
) CodegenError!void {
    try emitAsComplex(self, left_operand, left_type);
    try self.emit(".");
    try self.emit(method);
    const Ctx = struct { s: *NativeCodegen, ro: ZigValue, rt: NativeType };
    try self.withParensCtx(Ctx{ .s = self, .ro = right_operand, .rt = right_type }, struct {
        pub fn f(_: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try emitAsComplex(ctx.s, ctx.ro, ctx.rt);
        }
    }.f);
}

/// Check if a type is UnifiedInt (handles both small i64 and large BigInt)
pub fn isUnifiedInt(t: NativeType) bool {
    return t == .unified_int;
}

/// Runtime helper function names for UnifiedInt operations
/// Maps operator tag to runtime.unified_int_ops.xxx function name
/// UnifiedInt handles both small (i64) and large (BigInt) automatically, panics on OOM
pub const UnifiedIntRuntimeOps = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Add", "add" },
    .{ "Sub", "sub" },
    .{ "Mult", "mul" },
    .{ "FloorDiv", "floorDiv" },
    .{ "Mod", "mod" },
    .{ "LShift", "shl" },
    .{ "RShift", "shr" },
    .{ "Pow", "pow" },
    .{ "BitAnd", "bitAnd" },
    .{ "BitOr", "bitOr" },
    .{ "BitXor", "bitXor" },
});

/// Emit an operand as UnifiedInt value
/// Handles conversion from different source types
/// Uses auto-close pattern to guarantee matching parentheses
fn emitAsUnifiedInt(self: *NativeCodegen, operand: ZigValue, t: NativeType) CodegenError!void {
    if (isUnifiedInt(t)) {
        // Already UnifiedInt - emit directly
        try self.emitZigValue(operand);
    } else if (t == .bigint) {
        // BigInt -> UnifiedInt.fromBigInt (no allocation needed)
        try self.emit("runtime.UnifiedInt.fromBigInt");
        const Ctx = struct { o: ZigValue };
        try self.withParensCtx(Ctx{ .o = operand }, struct {
            pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
                try s.emitZigValue(ctx.o);
            }
        }.f);
    } else if (t == .int or t == .usize) {
        // i64/usize -> UnifiedInt.fromI64 (no allocation needed)
        try self.emit("runtime.unified_int_ops.fromI64");
        const Ctx = struct { o: ZigValue };
        try self.withParensCtx(Ctx{ .o = operand }, struct {
            pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
                try s.emit("@as(i64, ");
                try s.emitZigValue(ctx.o);
                try s.emit(")");
            }
        }.f);
    } else {
        // Unknown - try to convert as i64
        try self.emit("runtime.unified_int_ops.fromI64");
        const Ctx = struct { o: ZigValue };
        try self.withParensCtx(Ctx{ .o = operand }, struct {
            pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
                try s.emit("@as(i64, ");
                try s.emitZigValue(ctx.o);
                try s.emit(")");
            }
        }.f);
    }
}

/// Generate UnifiedInt binary operations using runtime.unified_int_ops helpers
/// Pattern: runtime.unified_int_ops.add(left, right, allocator)
/// No 'try' needed - runtime helpers panic on OOM internally
pub fn genUnifiedIntBinOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    // Capture operands as ZigValues
    const left_operand = try self.captureExpr(binop.left.*);
    const right_operand = try self.captureExpr(binop.right.*);

    // Get the runtime helper function name
    const op_name = @tagName(binop.op);

    // Standard binary operations: runtime.unified_int_ops.xxx(left, right, allocator)
    if (UnifiedIntRuntimeOps.get(op_name)) |runtime_fn| {
        // For shift/pow operations, right operand is a primitive (u32)
        if (binop.op == .LShift or binop.op == .RShift or binop.op == .Pow) {
            try emitUnifiedIntShiftOp(self, runtime_fn, left_operand, left_type, right_operand);
        } else {
            // Standard binary ops: both operands are UnifiedInt
            try emitUnifiedIntBinaryOp(self, runtime_fn, left_operand, left_type, right_operand, right_type);
        }
        return;
    }

    switch (binop.op) {
        .Div => {
            // Python division always returns float
            // Convert UnifiedInt to f64 via toF64()
            try self.emit("(runtime.unified_int_ops.toF64(");
            try emitAsUnifiedInt(self, left_operand, left_type);
            try self.emit(") / runtime.unified_int_ops.toF64(");
            try emitAsUnifiedInt(self, right_operand, right_type);
            try self.emit("))");
        },
        else => {
            // Unsupported UnifiedInt op - use VM fallback for drop-in CPython replacement
            try self.emitVMFallback(.{ .binop = binop });
        },
    }
}

/// Emit an operand as a complex number
/// Handles conversion from int/float to complex
fn emitAsComplex(self: *NativeCodegen, operand: ZigValue, t: NativeType) CodegenError!void {
    if (t == .complex) {
        // Already complex
        try self.emitZigValue(operand);
    } else if (t == .float) {
        // float -> complex with real part
        try self.emit("runtime.PyComplex.create(");
        try self.emitZigValue(operand);
        try self.emit(", 0.0)");
    } else {
        // int/bool -> complex with real part
        try self.emit("runtime.PyComplex.create(@as(f64, @floatFromInt(");
        try self.emitZigValue(operand);
        try self.emit(")), 0.0)");
    }
}

/// Generate complex number binary operations
/// Handles: complex + complex, int/float + complex, complex + int/float
pub fn genComplexBinOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    // Capture operands as ZigValues
    const left_operand = try self.captureExpr(binop.left.*);
    const right_operand = try self.captureExpr(binop.right.*);

    const method = switch (binop.op) {
        .Add => "add",
        .Sub => "sub",
        .Mult => "mul",
        .Div => "div",
        else => {
            // Unsupported complex operation - use VM fallback for drop-in CPython replacement
            try self.emitVMFallback(.{ .binop = binop });
            return;
        },
    };

    try emitComplexBinaryOp(self, method, left_operand, left_type, right_operand, right_type);
}
