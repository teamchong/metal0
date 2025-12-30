/// BigInt operations: context structs, helpers, and binary operations
/// Handles arbitrary-precision integer arithmetic using runtime.bigint_ops
///
/// MIGRATION STATUS: Partially migrated to ZigBuilder pattern
/// - Uses captureExpr() to bridge AST expressions to ZigValue
/// - Uses builder.write() for main generators
/// - Context structs still use emit for callback compatibility
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;
const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
const expr_emitter = @import("../../expr_emitter.zig");
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;
const ZigBuilder = builder_mod.ZigBuilder;
const shared_maps = @import("../../shared_maps.zig");

// ============================================
// BigInt operation helpers - builder pattern
// ============================================

/// Emit runtime.bigint_ops.fromInt(allocator, value) using auto-close callback
fn emitBigIntFromInt(self: *NativeCodegen, b: *ZigBuilder, operand: ZigValue) CodegenError!void {
    _ = self;
    try b.emitCallExpr("runtime.bigint_ops.fromInt", &.{ .allocator, .{ .value = operand } });
}

/// Emit runtime.bigint_ops.fromInt(allocator, @as(i64, @intCast(value)))
fn emitBigIntFromIntCast(self: *NativeCodegen, b: *ZigBuilder, operand: ZigValue) CodegenError!void {
    try b.emitRaw("runtime.bigint_ops.fromInt(__global_allocator, @as(i64, @intCast(");
    try self.emitZigValue(operand);
    try b.emitRaw(")))");
}

/// Emit runtime.bigint_ops.fromInt(allocator, @as(i64, value))
fn emitBigIntFromI64Cast(self: *NativeCodegen, b: *ZigBuilder, operand: ZigValue) CodegenError!void {
    try b.emitRaw("runtime.bigint_ops.fromInt(__global_allocator, @as(i64, ");
    try self.emitZigValue(operand);
    try b.emitRaw("))");
}

/// Emit shift operand: @as(usize, @intCast(value))
fn emitShiftOperand(self: *NativeCodegen, b: *ZigBuilder, operand: ZigValue) CodegenError!void {
    try b.emitRaw("@as(usize, @intCast(");
    try self.emitZigValue(operand);
    try b.emitRaw("))");
}

/// Emit pow exponent: @as(u32, @intCast(value))
fn emitPowExponent(self: *NativeCodegen, b: *ZigBuilder, operand: ZigValue) CodegenError!void {
    try b.emitRaw("@as(u32, @intCast(");
    try self.emitZigValue(operand);
    try b.emitRaw("))");
}

/// Get BigInt runtime function name for an operator
/// Uses unified OperatorMap from shared_maps.zig
pub fn getBigIntRuntimeOp(op_name: []const u8) ?[]const u8 {
    return shared_maps.getBigIntOp(op_name);
}

// =============================================================================
// BigInt operand emission helpers (module-level for callback access)
// =============================================================================

/// Emit left operand as BigInt value (for .method() calls)
/// Uses builder pattern for type-aware emission
pub fn emitBigIntLeftOperand(s: *NativeCodegen, ltype: NativeType, left: *const ast.Node, aname: []const u8) CodegenError!void {
    const b = try s.getBuilder();
    const left_val = try s.exprToValue(left.*);

    if (ltype == .bigint) {
        // Already BigInt - wrap in parens to ensure catch precedence is correct
        try b.emitRaw("(");
        try s.emitZigValue(left_val);
        try b.emitRaw(")");
    } else if (ltype == .int) {
        if (ltype.int.needsBigInt()) {
            try b.emitRaw("(runtime.BigInt.fromInt128(");
            try b.emitRaw(aname);
            try b.emitRaw(", ");
            try s.emitZigValue(left_val);
            try b.emitRaw(") catch @panic(\"OOM\"))");
        } else {
            try b.emitRaw("(runtime.BigInt.fromInt(");
            try b.emitRaw(aname);
            try b.emitRaw(", ");
            try s.emitZigValue(left_val);
            try b.emitRaw(") catch @panic(\"OOM\"))");
        }
    } else {
        try b.emitRaw("(runtime.BigInt.fromInt(");
        try b.emitRaw(aname);
        try b.emitRaw(", @as(i64, (");
        try s.emitZigValue(left_val);
        try b.emitRaw("))) catch @panic(\"OOM\"))");
    }
}

/// Emit right operand as BigInt pointer reference
/// Uses builder pattern for type-aware emission
pub fn emitBigIntRightOperand(s: *NativeCodegen, rtype: NativeType, right: *const ast.Node, aname: []const u8) CodegenError!void {
    const b = try s.getBuilder();
    const right_val = try s.exprToValue(right.*);

    if (rtype == .bigint) {
        try b.emitRaw("&(");
        try s.emitZigValue(right_val);
        try b.emitRaw(")");
    } else if (rtype == .int) {
        if (rtype.int.needsBigInt()) {
            try b.emitRaw("&(runtime.BigInt.fromInt128(");
            try b.emitRaw(aname);
            try b.emitRaw(", ");
            try s.emitZigValue(right_val);
            try b.emitRaw(") catch @panic(\"OOM\"))");
        } else {
            try b.emitRaw("&(runtime.BigInt.fromInt(");
            try b.emitRaw(aname);
            try b.emitRaw(", ");
            try s.emitZigValue(right_val);
            try b.emitRaw(") catch @panic(\"OOM\"))");
        }
    } else {
        try b.emitRaw("&(runtime.BigInt.fromInt(");
        try b.emitRaw(aname);
        try b.emitRaw(", @as(i64, (");
        try s.emitZigValue(right_val);
        try b.emitRaw("))) catch @panic(\"OOM\"))");
    }
}

// =============================================================================
// BigInt operation context structs for callback pattern
// =============================================================================

/// Context for standard BigInt binary operations (add, sub, mul, etc.)
/// Uses builder pattern for type-aware emission
pub const BigIntBinOpCtx = struct {
    cg: *NativeCodegen,
    left_type: NativeType,
    left: *const ast.Node,
    method: []const u8,
    right_type: NativeType,
    right: *const ast.Node,
    alloc_name: []const u8,

    pub fn emit(ctx: @This(), _: *NativeCodegen) CodegenError!void {
        const b = try ctx.cg.getBuilder();
        try emitBigIntLeftOperand(ctx.cg, ctx.left_type, ctx.left, ctx.alloc_name);
        try b.emitRaw(".");
        try b.emitRaw(ctx.method);
        try b.emitRaw("(");
        try emitBigIntRightOperand(ctx.cg, ctx.right_type, ctx.right, ctx.alloc_name);
        try b.emitRaw(", ");
        try b.emitRaw(ctx.alloc_name);
    }
};

/// Context for BigInt negation (clone and negate)
pub const BigIntNegateCtx = struct {
    cg: *NativeCodegen,
    operand: *const ast.Node,
    alloc_name: []const u8,

    pub fn emit(ctx: @This(), blk: *expr_emitter.LabeledBlock) CodegenError!void {
        try blk.emit("var __neg_tmp = (");
        try blk.emitExpr(ctx.operand.*);
        try blk.emit(").clone(");
        try blk.emit(ctx.alloc_name);
        try blk.emit(") catch @panic(\"OOM\"); __neg_tmp.negate(); ");
        try blk.breakWith("__neg_tmp");
    }
};

/// Context for BigInt inversion (~n = -(n+1))
pub const BigIntInvertCtx = struct {
    cg: *NativeCodegen,
    operand: *const ast.Node,
    alloc_name: []const u8,

    pub fn emit(ctx: @This(), blk: *expr_emitter.LabeledBlock) CodegenError!void {
        try blk.emit("var __bi_tmp = (");
        try blk.emitExpr(ctx.operand.*);
        try blk.emit(").add(&(runtime.BigInt.fromInt(");
        try blk.emit(ctx.alloc_name);
        try blk.emit(", 1) catch @panic(\"OOM\")), ");
        try blk.emit(ctx.alloc_name);
        try blk.emit(") catch @panic(\"OOM\"); __bi_tmp.negate(); ");
        try blk.breakWith("__bi_tmp");
    }
};

/// Context for unknown type negation (with nested block for BigInt path)
pub const UnknownNegateCtx = struct {
    cg: *NativeCodegen,
    operand: *const ast.Node,
    alloc_name: []const u8,

    pub fn emit(ctx: @This(), blk: *expr_emitter.LabeledBlock) CodegenError!void {
        try blk.emit("const __v = ");
        try blk.emitExpr(ctx.operand.*);
        try blk.emit("; const __T = @TypeOf(__v); ");
        try blk.startBreak();
        try blk.emit("if (@typeInfo(__T) == .@\"struct\" and @hasDecl(__T, \"negate\")) ");
        // Nested block for BigInt path
        var inner = try blk.nested("val");
        try inner.emit("var __tmp = __v.clone(");
        try inner.emit(ctx.alloc_name);
        try inner.emit(") catch @panic(\"OOM\"); __tmp.negate(); ");
        try inner.breakWith("__tmp");
        try inner.close();
        try blk.emit(" else -__v");
    }
};

/// Context for BigInt shift operations
/// Uses builder pattern for type-aware emission
pub const BigIntShiftCtx = struct {
    cg: *NativeCodegen,
    left_type: NativeType,
    left: *const ast.Node,
    method: []const u8,
    right: *const ast.Node,
    alloc_name: []const u8,

    pub fn emit(ctx: @This(), _: *NativeCodegen) CodegenError!void {
        const b = try ctx.cg.getBuilder();
        const right_val = try ctx.cg.exprToValue(ctx.right.*);
        try emitBigIntLeftOperand(ctx.cg, ctx.left_type, ctx.left, ctx.alloc_name);
        try b.emitRaw(".");
        try b.emitRaw(ctx.method);
        try b.emitRaw("(@as(usize, @intCast(");
        try ctx.cg.emitZigValue(right_val);
        try b.emitRaw(")), ");
        try b.emitRaw(ctx.alloc_name);
    }
};

/// Context for BigInt pow operation
/// Uses builder pattern for type-aware emission
pub const BigIntPowCtx = struct {
    cg: *NativeCodegen,
    left_type: NativeType,
    left: *const ast.Node,
    right: *const ast.Node,
    alloc_name: []const u8,

    pub fn emit(ctx: @This(), _: *NativeCodegen) CodegenError!void {
        const b = try ctx.cg.getBuilder();
        const right_val = try ctx.cg.exprToValue(ctx.right.*);
        try emitBigIntLeftOperand(ctx.cg, ctx.left_type, ctx.left, ctx.alloc_name);
        try b.emitRaw(".pow(@as(u32, @intCast(");
        try ctx.cg.emitZigValue(right_val);
        try b.emitRaw(")), ");
        try b.emitRaw(ctx.alloc_name);
    }
};

/// Context for large exponent pow with bool conversion
/// Uses UnifiedInt via unified_int_ops (panics on OOM, no error unions)
/// Uses builder pattern for type-aware emission
pub const LargeExpPowCtx = struct {
    cg: *NativeCodegen,
    binop: ast.Node.BinOp,
    left_is_bool: bool,
    right_is_bool: bool,
    alloc_name: []const u8,

    pub fn emit(ctx: @This(), _: *NativeCodegen) CodegenError!void {
        const b = try ctx.cg.getBuilder();
        const left_val = try ctx.cg.exprToValue(ctx.binop.left.*);
        const right_val = try ctx.cg.exprToValue(ctx.binop.right.*);

        // Use unified_int_ops.pow(left, exp, allocator) -> UnifiedInt
        try b.emitRaw("runtime.unified_int_ops.pow(runtime.unified_int_ops.fromI64(");
        // Left operand with bool conversion
        if (ctx.left_is_bool) {
            try b.emitRaw("@as(i64, @intFromBool(");
            try ctx.cg.emitZigValue(left_val);
            try b.emitRaw("))");
        } else {
            try ctx.cg.emitZigValue(left_val);
        }
        try b.emitRaw("), @as(u32, @intCast(");
        // Right operand with bool conversion
        if (ctx.right_is_bool) {
            try b.emitRaw("@as(i64, @intFromBool(");
            try ctx.cg.emitZigValue(right_val);
            try b.emitRaw("))");
        } else {
            try ctx.cg.emitZigValue(right_val);
        }
        try b.emitRaw(")), ");
        try b.emitRaw(ctx.alloc_name);
        try b.emitRaw(")");
    }
};

// =============================================================================
// BigInt binary operation generators
// =============================================================================

/// Generate BigInt binary operations using runtime.bigint_ops helpers
/// Pattern: runtime.bigint_ops.add(left, right, allocator)
/// No complex parenthesization needed - runtime handles OOM internally
pub fn genBigIntBinOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    // Capture operands as ZigValues
    const left_operand = try self.captureExpr(binop.left.*);
    const right_operand = try self.captureExpr(binop.right.*);
    const b = try self.getBuilder();

    // Get the runtime helper function name from unified map
    const op_name = @tagName(binop.op);
    const runtime_fn = getBigIntRuntimeOp(op_name) orelse {
        // Unsupported operation - use VM fallback for drop-in CPython replacement
        try self.flushBuilder();
        try self.emitVMFallback(.{ .binop = binop });
        return;
    };

    // Emit: runtime.bigint_ops.xxx(left, right, allocator)
    try b.emitRaw("runtime.bigint_ops.");
    try b.emitRaw(runtime_fn);
    try b.emitRaw("(");

    // Emit left operand (convert to BigInt if needed)
    try emitBigIntOperandValue(self, b, left_type, left_operand);
    try b.emitRaw(", ");

    // For shift/pow operations, right operand is a primitive (usize/u32)
    if (binop.op == .LShift or binop.op == .RShift) {
        try emitShiftOperand(self, b, right_operand);
    } else if (binop.op == .Pow) {
        try emitPowExponent(self, b, right_operand);
    } else {
        // Standard binary ops: right operand is also BigInt
        try emitBigIntOperandValue(self, b, right_type, right_operand);
    }

    try b.emitRaw(", __global_allocator)");
    try self.flushBuilder();
}

/// Emit an operand as a BigInt value (AST node version)
/// Uses builder pattern for type-aware emission
/// Handles conversion from i64, i128, or existing BigInt
pub fn emitBigIntOperand(self: *NativeCodegen, op_type: NativeType, node: *const ast.Node, alloc_name: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    const node_val = try self.exprToValue(node.*);

    if (op_type == .bigint) {
        // Already BigInt - emit directly
        try self.emitZigValue(node_val);
    } else if (op_type == .int) {
        if (op_type.int.needsBigInt()) {
            // Large int (i128) - use fromInt with cast
            try b.emitRaw("runtime.bigint_ops.fromInt(");
            try b.emitRaw(alloc_name);
            try b.emitRaw(", @as(i64, @intCast(");
            try self.emitZigValue(node_val);
            try b.emitRaw(")))");
        } else {
            // Normal i64
            try b.emitRaw("runtime.bigint_ops.fromInt(");
            try b.emitRaw(alloc_name);
            try b.emitRaw(", ");
            try self.emitZigValue(node_val);
            try b.emitRaw(")");
        }
    } else {
        // Unknown type - try to convert as i64
        try b.emitRaw("runtime.bigint_ops.fromInt(");
        try b.emitRaw(alloc_name);
        try b.emitRaw(", @as(i64, ");
        try self.emitZigValue(node_val);
        try b.emitRaw("))");
    }
}

/// Emit an operand as a BigInt value (ZigValue version) using builder
/// Handles conversion from i64, i128, or existing BigInt
fn emitBigIntOperandValue(self: *NativeCodegen, b: *ZigBuilder, op_type: NativeType, operand: ZigValue) CodegenError!void {
    if (op_type == .bigint) {
        // Already BigInt - emit directly
        try self.emitZigValue(operand);
    } else if (op_type == .int) {
        if (op_type.int.needsBigInt()) {
            // Large int (i128) - use fromInt with cast
            try emitBigIntFromIntCast(self, b, operand);
        } else {
            // Normal i64
            try emitBigIntFromInt(self, b, operand);
        }
    } else {
        // Unknown type - try to convert as i64
        try emitBigIntFromI64Cast(self, b, operand);
    }
}

/// Generate BigInt binary operations when RIGHT operand is BigInt (e.g., 0 - bigint)
/// Now uses the same runtime.bigint_ops helpers as genBigIntBinOp
pub fn genBigIntBinOpRightBig(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    // Delegate to the main function - it handles all cases now
    try genBigIntBinOp(self, binop, left_type, right_type);
}

/// Check if a type requires BigInt representation (explicit bigint or unbounded int)
pub fn needsBigInt(t: NativeType) bool {
    return t == .bigint or (t == .int and t.int.needsBigInt());
}
