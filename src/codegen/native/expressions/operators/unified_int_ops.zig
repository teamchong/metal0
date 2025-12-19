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

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// ============================================
// UnifiedInt/Complex operation helpers - auto-closing patterns
// ============================================

/// Emit UnifiedInt binary op: runtime.unified_int_ops.func(left, right, allocator)
fn emitUnifiedIntBinaryOp(
    self: *NativeCodegen,
    func: []const u8,
    left_operand: ZigValue,
    left_type: NativeType,
    right_operand: ZigValue,
    right_type: NativeType,
) CodegenError!void {
    try emitConst(self, "runtime.unified_int_ops.");
    try emitConst(self, func);
    try emitConst(self, "(");
    try emitAsUnifiedInt(self, left_operand, left_type);
    try emitConst(self, ", ");
    try emitAsUnifiedInt(self, right_operand, right_type);
    try emitConst(self, ", __global_allocator)");
}

/// Emit UnifiedInt shift/pow op: runtime.unified_int_ops.func(left, @as(u32, right), allocator)
fn emitUnifiedIntShiftOp(
    self: *NativeCodegen,
    func: []const u8,
    left_operand: ZigValue,
    left_type: NativeType,
    right_operand: ZigValue,
) CodegenError!void {
    try emitConst(self, "runtime.unified_int_ops.");
    try emitConst(self, func);
    try emitConst(self, "(");
    try emitAsUnifiedInt(self, left_operand, left_type);
    try emitConst(self, ", @as(u32, @intCast(");
    try self.emitZigValue(right_operand);
    try emitConst(self, ")), __global_allocator)");
}

/// Emit complex binary op: left.method(right)
fn emitComplexBinaryOp(
    self: *NativeCodegen,
    method: []const u8,
    left_operand: ZigValue,
    left_type: NativeType,
    right_operand: ZigValue,
    right_type: NativeType,
) CodegenError!void {
    try emitAsComplex(self, left_operand, left_type);
    try emitConst(self, ".");
    try emitConst(self, method);
    try emitConst(self, "(");
    try emitAsComplex(self, right_operand, right_type);
    try emitConst(self, ")");
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
        try emitConst(self, "runtime.UnifiedInt.fromBigInt(");
        try self.emitZigValue(operand);
        try emitConst(self, ")");
    } else if (t == .int or t == .usize) {
        // i64/usize -> UnifiedInt.fromI64 (no allocation needed)
        try emitConst(self, "runtime.unified_int_ops.fromI64(@as(i64, ");
        try self.emitZigValue(operand);
        try emitConst(self, "))");
    } else {
        // Unknown - try to convert as i64
        try emitConst(self, "runtime.unified_int_ops.fromI64(@as(i64, ");
        try self.emitZigValue(operand);
        try emitConst(self, "))");
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
            try emitConst(self, "(runtime.unified_int_ops.toF64(");
            try emitAsUnifiedInt(self, left_operand, left_type);
            try emitConst(self, ") / runtime.unified_int_ops.toF64(");
            try emitAsUnifiedInt(self, right_operand, right_type);
            try emitConst(self, "))");
        },
        else => {
            // Unsupported UnifiedInt op - fall back to error
            try emitConst(self, "@compileError(\"Unsupported UnifiedInt operation: ");
            try emitConst(self, op_name);
            try emitConst(self, "\")");
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
        try emitConst(self, "runtime.PyComplex.create(");
        try self.emitZigValue(operand);
        try emitConst(self, ", 0.0)");
    } else {
        // int/bool -> complex with real part
        try emitConst(self, "runtime.PyComplex.create(@as(f64, @floatFromInt(");
        try self.emitZigValue(operand);
        try emitConst(self, ")), 0.0)");
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
            // Unsupported complex operation - fall back to error
            try emitConst(self, "@compileError(\"Unsupported complex operation\")");
            return;
        },
    };

    try emitComplexBinaryOp(self, method, left_operand, left_type, right_operand, right_type);
}
