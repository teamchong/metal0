/// Unary operations: not, -, +, ~
/// Handles boolean negation, numeric negation, positive, and bitwise inversion
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
const shared = @import("../../shared_maps.zig");
const string_traits = @import("../../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../../analysis/traits/container_traits.zig");
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const bigint_ops = @import("bigint_ops.zig");
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;

// MIGRATED TO ZIGBUILDER

// ============================================
// Unary operation helpers - auto-closing patterns
// ============================================

/// Emit method call on operand: (operand).method()
/// Uses auto-close pattern to guarantee matching parentheses
fn emitMethodCall(self: *NativeCodegen, operand: ZigValue, method: []const u8) CodegenError!void {
    const Ctx = struct { o: ZigValue };
    try self.withParensCtx(Ctx{ .o = operand }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emitZigValue(ctx.o);
        }
    }.f);
    try self.emit(".");
    try self.emit(method);
    try self.emit("()");
}

/// Emit negation: -(operand)
/// Uses auto-close pattern to guarantee matching parentheses
fn emitNegate(self: *NativeCodegen, operand: ZigValue) CodegenError!void {
    try self.emit("-");
    const Ctx = struct { o: ZigValue };
    try self.withParensCtx(Ctx{ .o = operand }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emitZigValue(ctx.o);
        }
    }.f);
}

/// Emit logical not: !(operand)
/// Uses auto-close pattern to guarantee matching parentheses
fn emitLogicalNot(self: *NativeCodegen, operand: ZigValue) CodegenError!void {
    try self.emit("!");
    const Ctx = struct { o: ZigValue };
    try self.withParensCtx(Ctx{ .o = operand }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emitZigValue(ctx.o);
        }
    }.f);
}

/// Emit runtime function with allocator: runtime.func(operand, __global_allocator)
/// Uses auto-close pattern to guarantee matching parentheses
fn emitRuntimeUnary(self: *NativeCodegen, func: []const u8, operand: ZigValue) CodegenError!void {
    try self.emit(func);
    const Ctx = struct { o: ZigValue };
    try self.withParensCtx(Ctx{ .o = operand }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emitZigValue(ctx.o);
            try s.emit(", __global_allocator");
        }
    }.f);
}

/// Emit bool-to-int with prefix: prefix@as(i64, @intFromBool(operand))suffix
/// Uses auto-close pattern to guarantee matching parentheses
fn emitBoolToInt(self: *NativeCodegen, prefix: []const u8, operand: ZigValue, suffix: []const u8) CodegenError!void {
    try self.emit(prefix);
    try self.emit("@as(i64, @intFromBool");
    const Ctx = struct { o: ZigValue };
    try self.withParensCtx(Ctx{ .o = operand }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emitZigValue(ctx.o);
        }
    }.f);
    try self.emit(")");
    try self.emit(suffix);
}

/// Emit runtime.toBool wrapper: !runtime.toBool(operand)
/// Uses auto-close pattern to guarantee matching parentheses
fn emitNotToBool(self: *NativeCodegen, operand: ZigValue) CodegenError!void {
    try self.emit("!runtime.toBool");
    const Ctx = struct { o: ZigValue };
    try self.withParensCtx(Ctx{ .o = operand }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emitZigValue(ctx.o);
        }
    }.f);
}

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

    // PyValue: use .isTruthy() method (must check first as PyValue can hold any type)
    if (operand_type == .pyvalue) {
        try self.emit("!");
        try self.emitZigValue(operand);
        try self.emit(".isTruthy()");
        return;
    }

    // Check if operand is a variable assigned from VM fallback
    // (needsVMFallback only checks the expression itself, not prior assignments)
    if (unaryop.operand.* == .name) {
        const var_name = unaryop.operand.name.id;
        if (self.pyvalue_vars.contains(var_name)) {
            try self.emit("!");
            try self.emitZigValue(operand);
            try self.emit(".isTruthy()");
            return;
        }
    }

    if (string_traits.isString(operand_type)) {
        // String: not "abc" -> len == 0
        try self.emit("(");
        try self.emitZigValue(operand);
        try self.emit(").len == 0");
    } else if (container_traits.isList(operand_type)) {
        // List: not lst -> !runtime.toBool(lst)
        try emitNotToBool(self, operand);
    } else if (container_traits.isTuple(operand_type)) {
        // Tuple: not tup -> len == 0
        try self.emit("(@typeInfo(@TypeOf(");
        try self.emitZigValue(operand);
        try self.emit(")).@\"struct\".fields.len == 0)");
    } else if (shared.isEmptyTuple(unaryop.operand.*)) {
        // Empty tuple literal: not () -> true
        try self.emit("true");
    } else if (unaryop.operand.* == .tuple) {
        // Non-empty tuple literal: not (1,2) -> false
        try self.emit("false");
    } else if (type_traits.isBoolean(operand_type) or type_traits.isIntegral(operand_type) or type_traits.isFloating(operand_type)) {
        // Primitives: not x -> !x
        try emitLogicalNot(self, operand);
    } else {
        // Fallback: runtime.toBool
        try emitNotToBool(self, operand);
    }
}

/// Generate numeric negation: -x
fn genNegOp(self: *NativeCodegen, unaryop: ast.Node.UnaryOp) CodegenError!void {
    const operand_type = try self.inferExprScoped(unaryop.operand.*);

    // PyValue: use .neg() method
    if (operand_type == .pyvalue) {
        const operand = try self.captureExpr(unaryop.operand.*);
        try emitMethodCall(self, operand, "neg");
        return;
    }

    // Boolean: -True/-False -> -@intFromBool
    if (type_traits.isBoolean(operand_type)) {
        const operand = try self.captureExpr(unaryop.operand.*);
        try emitBoolToInt(self, "-", operand, "");
        return;
    }

    // Complex: use .neg() method
    if (operand_type == .complex) {
        const operand = try self.captureExpr(unaryop.operand.*);
        try emitMethodCall(self, operand, "neg");
        return;
    }

    // UnifiedInt: use runtime helper
    if (operand_type == .unified_int) {
        const operand = try self.captureExpr(unaryop.operand.*);
        try emitRuntimeUnary(self, "runtime.unified_int_ops.neg", operand);
        return;
    }

    // BigInt: use runtime helper
    if (operand_type == .bigint) {
        const operand = try self.captureExpr(unaryop.operand.*);
        try emitRuntimeUnary(self, "runtime.bigint_ops.neg", operand);
        return;
    }

    // Unknown type: use block expression with type dispatch
    if (type_traits.isUnknown(operand_type)) {
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
    try emitNegate(self, operand);
}

/// Generate unary positive: +x
/// Python: +x -> x (with bool conversion to int)
fn genPosOp(self: *NativeCodegen, unaryop: ast.Node.UnaryOp) CodegenError!void {
    const operand_type = try self.inferExprScoped(unaryop.operand.*);

    if (type_traits.isBoolean(operand_type)) {
        // Boolean: +True -> 1, +False -> 0
        const operand = try self.captureExpr(unaryop.operand.*);
        try emitBoolToInt(self, "", operand, "");
    } else {
        // Others: just emit the operand
        try genExpr(self, unaryop.operand.*);
    }
}

/// Generate bitwise inversion: ~x
fn genInvertOp(self: *NativeCodegen, unaryop: ast.Node.UnaryOp) CodegenError!void {
    const operand_type = try self.inferExprScoped(unaryop.operand.*);

    // Check if operand is a PyValue variable
    const is_pyvalue = if (unaryop.operand.* == .name) blk: {
        const name = unaryop.operand.name.id;
        const vt = self.type_inferrer.getScopedVar(name) orelse
            self.type_inferrer.var_types.get(name);
        break :blk if (vt) |v| (v == .pyvalue) else false;
    } else false;

    if (is_pyvalue) {
        const operand = try self.captureExpr(unaryop.operand.*);
        try emitMethodCall(self, operand, "pyInvert");
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
        try emitBoolToInt(self, "~", operand, "");
        return;
    }

    // UnifiedInt: use runtime helper
    if (operand_type == .unified_int) {
        const operand = try self.captureExpr(unaryop.operand.*);
        try emitRuntimeUnary(self, "runtime.unified_int_ops.bitNot", operand);
        return;
    }

    // BigInt: use block expression for clone + negate
    if (operand_type == .bigint) {
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
    try self.emit("~@as(i64, ");
    try self.emitZigValue(operand);
    try self.emit(")");
}
