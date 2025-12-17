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
    // Note: Bitwise ops (BitAnd, BitOr, BitXor) are TODO in UnifiedInt
});

/// Emit an operand as UnifiedInt value
/// Handles conversion from different source types
fn emitAsUnifiedInt(self: *NativeCodegen, operand: ZigValue, t: NativeType) CodegenError!void {
    if (isUnifiedInt(t)) {
        // Already UnifiedInt - emit directly
        try self.emitZigValue(operand);
    } else if (t == .bigint) {
        // BigInt -> UnifiedInt.fromBigInt (no allocation needed)
        try self.emit("runtime.UnifiedInt.fromBigInt(");
        try self.emitZigValue(operand);
        try self.emit(")");
    } else if (t == .int or t == .usize) {
        // i64/usize -> UnifiedInt.fromI64 (no allocation needed)
        try self.emit("runtime.unified_int_ops.fromI64(@as(i64, ");
        try self.emitZigValue(operand);
        try self.emit("))");
    } else {
        // Unknown - try to convert as i64
        try self.emit("runtime.unified_int_ops.fromI64(@as(i64, ");
        try self.emitZigValue(operand);
        try self.emit("))");
    }
}

/// Generate UnifiedInt binary operations using runtime.unified_int_ops helpers
/// Pattern: runtime.unified_int_ops.add(left, right, allocator)
/// No 'try' needed - runtime helpers panic on OOM internally
pub fn genUnifiedIntBinOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    const alloc_name = "__global_allocator";

    // Capture operands as ZigValues
    const left_operand = try self.captureExpr(binop.left.*);
    const right_operand = try self.captureExpr(binop.right.*);

    // Get the runtime helper function name
    const op_name = @tagName(binop.op);

    // Standard binary operations: runtime.unified_int_ops.xxx(left, right, allocator)
    if (UnifiedIntRuntimeOps.get(op_name)) |runtime_fn| {
        // For shift/pow operations, right operand is a primitive (u32)
        if (binop.op == .LShift or binop.op == .RShift) {
            try self.emit("runtime.unified_int_ops.");
            try self.emit(runtime_fn);
            try self.emit("(");
            try emitAsUnifiedInt(self, left_operand, left_type);
            try self.emit(", @as(u32, @intCast(");
            try self.emitZigValue(right_operand);
            try self.emit(")), ");
            try self.emit(alloc_name);
            try self.emit(")");
        } else if (binop.op == .Pow) {
            try self.emit("runtime.unified_int_ops.");
            try self.emit(runtime_fn);
            try self.emit("(");
            try emitAsUnifiedInt(self, left_operand, left_type);
            try self.emit(", @as(u32, @intCast(");
            try self.emitZigValue(right_operand);
            try self.emit(")), ");
            try self.emit(alloc_name);
            try self.emit(")");
        } else {
            // Standard binary ops: both operands are UnifiedInt
            try self.emit("runtime.unified_int_ops.");
            try self.emit(runtime_fn);
            try self.emit("(");
            try emitAsUnifiedInt(self, left_operand, left_type);
            try self.emit(", ");
            try emitAsUnifiedInt(self, right_operand, right_type);
            try self.emit(", ");
            try self.emit(alloc_name);
            try self.emit(")");
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
            // Unsupported UnifiedInt op - fall back to error
            try self.emit("@compileError(\"Unsupported UnifiedInt operation: ");
            try self.emit(op_name);
            try self.emit("\")");
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

    switch (binop.op) {
        .Add => {
            // complex.add(other)
            try emitAsComplex(self, left_operand, left_type);
            try self.emit(".add(");
            try emitAsComplex(self, right_operand, right_type);
            try self.emit(")");
        },
        .Sub => {
            // complex.sub(other)
            try emitAsComplex(self, left_operand, left_type);
            try self.emit(".sub(");
            try emitAsComplex(self, right_operand, right_type);
            try self.emit(")");
        },
        .Mult => {
            // complex.mul(other)
            try emitAsComplex(self, left_operand, left_type);
            try self.emit(".mul(");
            try emitAsComplex(self, right_operand, right_type);
            try self.emit(")");
        },
        .Div => {
            // complex.div(other)
            try emitAsComplex(self, left_operand, left_type);
            try self.emit(".div(");
            try emitAsComplex(self, right_operand, right_type);
            try self.emit(")");
        },
        else => {
            // Unsupported complex operation - fall back to error
            try self.emit("@compileError(\"Unsupported complex operation\")");
        },
    }
}
