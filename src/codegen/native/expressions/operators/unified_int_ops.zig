/// UnifiedInt and Complex number operations
/// Handles auto-promoting i64/BigInt arithmetic and complex number math
///
/// MIGRATION STATUS: Fully migrated to ZigBuilder pattern
/// - Uses captureExpr() to bridge AST expressions to ZigValue
/// - Uses builder.write() for all output
/// - Uses self.emitZigValue() for ZigValue emission
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;
const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;
const ZigBuilder = builder_mod.ZigBuilder;
const shared_maps = @import("../../shared_maps.zig");

/// Check if a type is UnifiedInt (handles both small i64 and large BigInt)
pub fn isUnifiedInt(t: NativeType) bool {
    return t == .unified_int;
}

/// Get UnifiedInt runtime function name for an operator
/// Uses unified OperatorMap from shared_maps.zig
pub fn getUnifiedIntRuntimeOp(op_name: []const u8) ?[]const u8 {
    return shared_maps.getUnifiedIntOp(op_name);
}

/// Emit an operand as UnifiedInt value using builder pattern
/// Handles conversion from different source types
fn emitAsUnifiedInt(self: *NativeCodegen, b: *ZigBuilder, operand: ZigValue, t: NativeType) CodegenError!void {
    if (isUnifiedInt(t)) {
        // Already UnifiedInt - emit directly
        try self.emitZigValue(operand);
    } else if (t == .bigint) {
        // BigInt -> UnifiedInt.fromBigInt (no allocation needed)
        try b.emitRaw("runtime.UnifiedInt.fromBigInt(");
        try self.emitZigValue(operand);
        try b.emitRaw(")");
    } else if (t == .int or t == .usize) {
        // i64/usize -> UnifiedInt.fromI64 (no allocation needed)
        try b.emitRaw("runtime.unified_int_ops.fromI64(@as(i64, ");
        try self.emitZigValue(operand);
        try b.emitRaw("))");
    } else {
        // Unknown - try to convert as i64
        try b.emitRaw("runtime.unified_int_ops.fromI64(@as(i64, ");
        try self.emitZigValue(operand);
        try b.emitRaw("))");
    }
}

/// Generate UnifiedInt binary operations using runtime.unified_int_ops helpers
/// Pattern: runtime.unified_int_ops.add(left, right, allocator)
/// No 'try' needed - runtime helpers panic on OOM internally
pub fn genUnifiedIntBinOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    // Capture operands as ZigValues
    const left_operand = try self.captureExpr(binop.left.*);
    const right_operand = try self.captureExpr(binop.right.*);
    const b = try self.getBuilder();

    // Get the runtime helper function name from unified map
    const op_name = @tagName(binop.op);

    // Standard binary operations: runtime.unified_int_ops.xxx(left, right, allocator)
    if (getUnifiedIntRuntimeOp(op_name)) |runtime_fn| {
        // For shift/pow operations, right operand is a primitive (u32)
        if (binop.op == .LShift or binop.op == .RShift or binop.op == .Pow) {
            // Emit: runtime.unified_int_ops.func(left, @as(u32, @intCast(right)), __global_allocator)
            try b.emitRaw("runtime.unified_int_ops.");
            try b.emitRaw(runtime_fn);
            try b.emitRaw("(");
            try emitAsUnifiedInt(self, b, left_operand, left_type);
            try b.emitRaw(", @as(u32, @intCast(");
            try self.emitZigValue(right_operand);
            try b.emitRaw(")), __global_allocator)");
        } else {
            // Standard binary ops: both operands are UnifiedInt
            // Emit: runtime.unified_int_ops.func(left, right, __global_allocator)
            try b.emitRaw("runtime.unified_int_ops.");
            try b.emitRaw(runtime_fn);
            try b.emitRaw("(");
            try emitAsUnifiedInt(self, b, left_operand, left_type);
            try b.emitRaw(", ");
            try emitAsUnifiedInt(self, b, right_operand, right_type);
            try b.emitRaw(", __global_allocator)");
        }
        try self.flushBuilder();
        return;
    }

    switch (binop.op) {
        .Div => {
            // Python division always returns float
            // Convert UnifiedInt to f64 via toF64()
            try b.emitRaw("(runtime.unified_int_ops.toF64(");
            try emitAsUnifiedInt(self, b, left_operand, left_type);
            try b.emitRaw(") / runtime.unified_int_ops.toF64(");
            try emitAsUnifiedInt(self, b, right_operand, right_type);
            try b.emitRaw("))");
            try self.flushBuilder();
        },
        else => {
            // Unsupported UnifiedInt op - use VM fallback for drop-in CPython replacement
            try self.flushBuilder();
            try self.emitVMFallback(.{ .binop = binop });
        },
    }
}

/// Emit an operand as a complex number using builder pattern
/// Handles conversion from int/float to complex
fn emitAsComplex(self: *NativeCodegen, b: *ZigBuilder, operand: ZigValue, t: NativeType) CodegenError!void {
    if (t == .complex) {
        // Already complex
        try self.emitZigValue(operand);
    } else if (t == .float) {
        // float -> complex with real part
        try b.emitRaw("runtime.PyComplex.create(");
        try self.emitZigValue(operand);
        try b.emitRaw(", 0.0)");
    } else {
        // int/bool -> complex with real part
        try b.emitRaw("runtime.PyComplex.create(@as(f64, @floatFromInt(");
        try self.emitZigValue(operand);
        try b.emitRaw(")), 0.0)");
    }
}

/// Generate complex number binary operations
/// Handles: complex + complex, int/float + complex, complex + int/float
pub fn genComplexBinOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    // Capture operands as ZigValues
    const left_operand = try self.captureExpr(binop.left.*);
    const right_operand = try self.captureExpr(binop.right.*);
    const b = try self.getBuilder();

    const method = switch (binop.op) {
        .Add => "add",
        .Sub => "sub",
        .Mult => "mul",
        .Div => "div",
        else => {
            // Unsupported complex operation - use VM fallback for drop-in CPython replacement
            try self.flushBuilder();
            try self.emitVMFallback(.{ .binop = binop });
            return;
        },
    };

    // Emit: left.method(right)
    try emitAsComplex(self, b, left_operand, left_type);
    try b.emitRaw(".");
    try b.emitRaw(method);
    try b.emitRaw("(");
    try emitAsComplex(self, b, right_operand, right_type);
    try b.emitRaw(")");
    try self.flushBuilder();
}
