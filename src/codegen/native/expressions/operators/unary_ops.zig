/// Unary operations: not, -, +, ~
/// Handles boolean negation, numeric negation, positive, and bitwise inversion
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
const shared = @import("../../shared_maps.zig");
const string_traits = @import("../../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../../analysis/traits/container_traits.zig");
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const bigint_ops = @import("bigint_ops.zig");
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;
const ZigBuilder = builder_mod.ZigBuilder;

/// Generate unary operations (not, -, ~)
pub fn genUnaryOp(self: *NativeCodegen, unaryop: ast.Node.UnaryOp) CodegenError!void {
    switch (unaryop.op) {
        .Not => try genNotOp(self, unaryop),
        .USub => try genNegOp(self, unaryop),
        .UAdd => try genPosOp(self, unaryop),
        .Invert => try genInvertOp(self, unaryop),
    }
}

/// Generate 'not' operation
/// Python: not x -> Zig: !runtime.toBool(x) or specialized per type
fn genNotOp(self: *NativeCodegen, unaryop: ast.Node.UnaryOp) CodegenError!void {
    const operand_type = try self.inferExprScoped(unaryop.operand.*);
    const operand = try self.captureExpr(unaryop.operand.*);
    const b = try self.getBuilder();

    // PyValue: use .isTruthy() method (must check first as PyValue can hold any type)
    if (operand_type == .pyvalue) {
        try b.write("!");
        try self.emitZigValue(operand);
        try b.write(".isTruthy()");
        try self.flushBuilder();
        return;
    }

    // Check if operand is a variable assigned from VM fallback
    // (needsVMFallback only checks the expression itself, not prior assignments)
    if (unaryop.operand.* == .name) {
        const var_name = unaryop.operand.name.id;
        if (self.pyvalue_vars.contains(var_name)) {
            try b.write("!");
            try self.emitZigValue(operand);
            try b.write(".isTruthy()");
            try self.flushBuilder();
            return;
        }
    }

    if (string_traits.isString(operand_type)) {
        // String: not "abc" -> len == 0
        try b.write("(");
        try self.emitZigValue(operand);
        try b.write(").len == 0");
    } else if (container_traits.isList(operand_type)) {
        // List: not lst -> !runtime.toBool(lst)
        try b.write("!runtime.toBool(");
        try self.emitZigValue(operand);
        try b.write(")");
    } else if (container_traits.isTuple(operand_type)) {
        // Tuple: not tup -> len == 0
        try b.write("(@typeInfo(@TypeOf(");
        try self.emitZigValue(operand);
        try b.write(")).@\"struct\".fields.len == 0)");
    } else if (shared.isEmptyTuple(unaryop.operand.*)) {
        // Empty tuple literal: not () -> true
        try b.write("true");
    } else if (unaryop.operand.* == .tuple) {
        // Non-empty tuple literal: not (1,2) -> false
        try b.write("false");
    } else if (type_traits.isBoolean(operand_type) or type_traits.isIntegral(operand_type) or type_traits.isFloating(operand_type)) {
        // Primitives: not x -> !(x)
        try b.write("!(");
        try self.emitZigValue(operand);
        try b.write(")");
    } else {
        // Fallback: runtime.toBool
        try b.write("!runtime.toBool(");
        try self.emitZigValue(operand);
        try b.write(")");
    }
    try self.flushBuilder();
}

/// Generate numeric negation: -x
fn genNegOp(self: *NativeCodegen, unaryop: ast.Node.UnaryOp) CodegenError!void {
    const operand_type = try self.inferExprScoped(unaryop.operand.*);
    const b = try self.getBuilder();

    // PyValue: use .neg() method
    if (operand_type == .pyvalue) {
        const operand = try self.captureExpr(unaryop.operand.*);
        try b.write("(");
        try self.emitZigValue(operand);
        try b.write(").neg()");
        try self.flushBuilder();
        return;
    }

    // Boolean: -True/-False -> -@intFromBool
    if (type_traits.isBoolean(operand_type)) {
        const operand = try self.captureExpr(unaryop.operand.*);
        try b.write("-@as(i64, @intFromBool(");
        try self.emitZigValue(operand);
        try b.write("))");
        try self.flushBuilder();
        return;
    }

    // Complex: use .neg() method
    if (operand_type == .complex) {
        const operand = try self.captureExpr(unaryop.operand.*);
        try b.write("(");
        try self.emitZigValue(operand);
        try b.write(").neg()");
        try self.flushBuilder();
        return;
    }

    // UnifiedInt: use runtime helper
    if (operand_type == .unified_int) {
        const operand = try self.captureExpr(unaryop.operand.*);
        try b.write("runtime.unified_int_ops.neg(");
        try self.emitZigValue(operand);
        try b.write(", __global_allocator)");
        try self.flushBuilder();
        return;
    }

    // BigInt: use runtime helper
    if (operand_type == .bigint) {
        const operand = try self.captureExpr(unaryop.operand.*);
        try b.write("runtime.bigint_ops.neg(");
        try self.emitZigValue(operand);
        try b.write(", __global_allocator)");
        try self.flushBuilder();
        return;
    }

    // Unknown type: use block expression with type dispatch
    if (type_traits.isUnknown(operand_type)) {
        try self.flushBuilder();
        var em = self.exprEmitter();
        try em.withBlock("unk", bigint_ops.UnknownNegateCtx{
            .cg = self,
            .operand = unaryop.operand,
            .alloc_name = "__global_allocator",
        }, bigint_ops.UnknownNegateCtx.emit);
        return;
    }

    // Default: simple negation
    const operand = try self.captureExpr(unaryop.operand.*);
    try b.write("-(");
    try self.emitZigValue(operand);
    try b.write(")");
    try self.flushBuilder();
}

/// Generate unary positive: +x
/// Python: +x -> x (with bool conversion to int)
fn genPosOp(self: *NativeCodegen, unaryop: ast.Node.UnaryOp) CodegenError!void {
    const operand_type = try self.inferExprScoped(unaryop.operand.*);
    const b = try self.getBuilder();

    if (type_traits.isBoolean(operand_type)) {
        // Boolean: +True -> 1, +False -> 0
        const operand = try self.captureExpr(unaryop.operand.*);
        try b.write("@as(i64, @intFromBool(");
        try self.emitZigValue(operand);
        try b.write("))");
        try self.flushBuilder();
    } else {
        // Others: just emit the operand
        try self.flushBuilder();
        try genExpr(self, unaryop.operand.*);
    }
}

/// Generate bitwise inversion: ~x
fn genInvertOp(self: *NativeCodegen, unaryop: ast.Node.UnaryOp) CodegenError!void {
    const operand_type = try self.inferExprScoped(unaryop.operand.*);
    const b = try self.getBuilder();

    // Check if operand is a PyValue variable
    const is_pyvalue = if (unaryop.operand.* == .name) blk: {
        const name = unaryop.operand.name.id;
        const vt = self.type_inferrer.getScopedVar(name) orelse
            self.type_inferrer.var_types.get(name);
        break :blk if (vt) |v| (v == .pyvalue) else false;
    } else false;

    if (is_pyvalue) {
        const operand = try self.captureExpr(unaryop.operand.*);
        try b.write("(");
        try self.emitZigValue(operand);
        try b.write(").pyInvert()");
        try self.flushBuilder();
        return;
    }

    // Check if operand is boolean (including True/False names and bool constants)
    const is_bool = blk: {
        if (type_traits.isBoolean(operand_type)) break :blk true;
        if (unaryop.operand.* == .name) {
            const name = unaryop.operand.name.id;
            if (std.mem.eql(u8, name, "True") or std.mem.eql(u8, name, "False")) {
                break :blk true;
            }
        }
        if (unaryop.operand.* == .constant) {
            if (unaryop.operand.constant.value == .bool) {
                break :blk true;
            }
        }
        break :blk false;
    };

    if (is_bool) {
        // Boolean: ~True -> ~1 = -2
        const operand = try self.captureExpr(unaryop.operand.*);
        try b.write("~@as(i64, @intFromBool(");
        try self.emitZigValue(operand);
        try b.write("))");
        try self.flushBuilder();
        return;
    }

    // UnifiedInt: use runtime helper
    if (operand_type == .unified_int) {
        const operand = try self.captureExpr(unaryop.operand.*);
        try b.write("runtime.unified_int_ops.bitNot(");
        try self.emitZigValue(operand);
        try b.write(", __global_allocator)");
        try self.flushBuilder();
        return;
    }

    // BigInt: use block expression for clone + negate
    if (operand_type == .bigint) {
        try self.flushBuilder();
        var em = self.exprEmitter();
        try em.withBlock("inv", bigint_ops.BigIntInvertCtx{
            .cg = self,
            .operand = unaryop.operand,
            .alloc_name = "__global_allocator",
        }, bigint_ops.BigIntInvertCtx.emit);
        return;
    }

    // Default: simple bitwise invert with i64 cast
    const operand = try self.captureExpr(unaryop.operand.*);
    try b.write("~@as(i64, ");
    try self.emitZigValue(operand);
    try b.write(")");
    try self.flushBuilder();
}
