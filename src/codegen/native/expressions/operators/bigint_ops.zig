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

// ============================================
// BigInt operation helpers - builder pattern
// ============================================

/// Emit runtime.bigint_ops.fromInt(allocator, value) using builder
fn emitBigIntFromInt(self: *NativeCodegen, b: *ZigBuilder, operand: ZigValue) CodegenError!void {
    try b.write("runtime.bigint_ops.fromInt(__global_allocator, ");
    try self.emitZigValue(operand);
    try b.write(")");
}

/// Emit runtime.bigint_ops.fromInt(allocator, @as(i64, @intCast(value))) using builder
fn emitBigIntFromIntCast(self: *NativeCodegen, b: *ZigBuilder, operand: ZigValue) CodegenError!void {
    try b.write("runtime.bigint_ops.fromInt(__global_allocator, @as(i64, @intCast(");
    try self.emitZigValue(operand);
    try b.write(")))");
}

/// Emit runtime.bigint_ops.fromInt(allocator, @as(i64, value)) using builder
fn emitBigIntFromI64Cast(self: *NativeCodegen, b: *ZigBuilder, operand: ZigValue) CodegenError!void {
    try b.write("runtime.bigint_ops.fromInt(__global_allocator, @as(i64, ");
    try self.emitZigValue(operand);
    try b.write("))");
}

/// Emit shift operand: @as(usize, @intCast(value)) using builder
fn emitShiftOperand(self: *NativeCodegen, b: *ZigBuilder, operand: ZigValue) CodegenError!void {
    try b.write("@as(usize, @intCast(");
    try self.emitZigValue(operand);
    try b.write("))");
}

/// Emit pow exponent: @as(u32, @intCast(value)) using builder
fn emitPowExponent(self: *NativeCodegen, b: *ZigBuilder, operand: ZigValue) CodegenError!void {
    try b.write("@as(u32, @intCast(");
    try self.emitZigValue(operand);
    try b.write("))");
}

/// BigInt method names for standard binary operations (left.method(&right, allocator))
pub const BigIntStdMethods = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Add", "add" }, .{ "Sub", "sub" }, .{ "Mult", "mul" },
    .{ "FloorDiv", "floorDiv" }, .{ "Mod", "mod" },
    .{ "BitAnd", "bitAnd" }, .{ "BitOr", "bitOr" }, .{ "BitXor", "bitXor" },
});

/// Runtime helper function names for BigInt operations
/// Maps operator tag to runtime.bigint_ops.xxx function name
pub const BigIntRuntimeOps = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Add", "add" },
    .{ "Sub", "sub" },
    .{ "Mult", "mul" },
    .{ "FloorDiv", "divFloor" },
    .{ "Div", "divFloor" }, // Python / on ints is floor div
    .{ "Mod", "mod" },
    .{ "BitAnd", "bitAnd" },
    .{ "BitOr", "bitOr" },
    .{ "BitXor", "bitXor" },
    .{ "LShift", "shl" },
    .{ "RShift", "shr" },
    .{ "Pow", "pow" },
});

// =============================================================================
// BigInt operand emission helpers (module-level for callback access)
// =============================================================================

/// Emit left operand as BigInt value (for .method() calls)
pub fn emitBigIntLeftOperand(s: *NativeCodegen, ltype: NativeType, left: *const ast.Node, aname: []const u8) CodegenError!void {
    if (ltype == .bigint) {
        // Already BigInt - wrap in parens to ensure catch precedence is correct
        try s.emit("(");
        try genExpr(s, left.*);
        try s.emit(")");
    } else if (ltype == .int) {
        if (ltype.int.needsBigInt()) {
            try s.emit("(runtime.BigInt.fromInt128(");
            try s.emit(aname);
            try s.emit(", ");
            try genExpr(s, left.*);
            try s.emit(") catch @panic(\"OOM\"))");
        } else {
            try s.emit("(runtime.BigInt.fromInt(");
            try s.emit(aname);
            try s.emit(", ");
            try genExpr(s, left.*);
            try s.emit(") catch @panic(\"OOM\"))");
        }
    } else {
        try s.emit("(runtime.BigInt.fromInt(");
        try s.emit(aname);
        try s.emit(", @as(i64, (");
        try genExpr(s, left.*);
        try s.emit("))) catch @panic(\"OOM\"))");
    }
}

/// Emit right operand as BigInt pointer reference
pub fn emitBigIntRightOperand(s: *NativeCodegen, rtype: NativeType, right: *const ast.Node, aname: []const u8) CodegenError!void {
    if (rtype == .bigint) {
        try s.emit("&(");
        try genExpr(s, right.*);
        try s.emit(")");
    } else if (rtype == .int) {
        if (rtype.int.needsBigInt()) {
            try s.emit("&(runtime.BigInt.fromInt128(");
            try s.emit(aname);
            try s.emit(", ");
            try genExpr(s, right.*);
            try s.emit(") catch @panic(\"OOM\"))");
        } else {
            try s.emit("&(runtime.BigInt.fromInt(");
            try s.emit(aname);
            try s.emit(", ");
            try genExpr(s, right.*);
            try s.emit(") catch @panic(\"OOM\"))");
        }
    } else {
        try s.emit("&(runtime.BigInt.fromInt(");
        try s.emit(aname);
        try s.emit(", @as(i64, (");
        try genExpr(s, right.*);
        try s.emit("))) catch @panic(\"OOM\"))");
    }
}

// =============================================================================
// BigInt operation context structs for callback pattern
// =============================================================================

/// Context for standard BigInt binary operations (add, sub, mul, etc.)
pub const BigIntBinOpCtx = struct {
    cg: *NativeCodegen,
    left_type: NativeType,
    left: *const ast.Node,
    method: []const u8,
    right_type: NativeType,
    right: *const ast.Node,
    alloc_name: []const u8,

    pub fn emit(ctx: @This(), _: *NativeCodegen) CodegenError!void {
        try emitBigIntLeftOperand(ctx.cg, ctx.left_type, ctx.left, ctx.alloc_name);
        try ctx.cg.emit(".");
        try ctx.cg.emit(ctx.method);
        try ctx.cg.emit("(");
        try emitBigIntRightOperand(ctx.cg, ctx.right_type, ctx.right, ctx.alloc_name);
        try ctx.cg.emit(", ");
        try ctx.cg.emit(ctx.alloc_name);
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
pub const BigIntShiftCtx = struct {
    cg: *NativeCodegen,
    left_type: NativeType,
    left: *const ast.Node,
    method: []const u8,
    right: *const ast.Node,
    alloc_name: []const u8,

    pub fn emit(ctx: @This(), _: *NativeCodegen) CodegenError!void {
        try emitBigIntLeftOperand(ctx.cg, ctx.left_type, ctx.left, ctx.alloc_name);
        try ctx.cg.emit(".");
        try ctx.cg.emit(ctx.method);
        try ctx.cg.emit("(@as(usize, @intCast(");
        try genExpr(ctx.cg, ctx.right.*);
        try ctx.cg.emit(")), ");
        try ctx.cg.emit(ctx.alloc_name);
    }
};

/// Context for BigInt pow operation
pub const BigIntPowCtx = struct {
    cg: *NativeCodegen,
    left_type: NativeType,
    left: *const ast.Node,
    right: *const ast.Node,
    alloc_name: []const u8,

    pub fn emit(ctx: @This(), _: *NativeCodegen) CodegenError!void {
        try emitBigIntLeftOperand(ctx.cg, ctx.left_type, ctx.left, ctx.alloc_name);
        try ctx.cg.emit(".pow(@as(u32, @intCast(");
        try genExpr(ctx.cg, ctx.right.*);
        try ctx.cg.emit(")), ");
        try ctx.cg.emit(ctx.alloc_name);
    }
};

/// Context for large exponent pow with bool conversion
/// Now uses UnifiedInt via unified_int_ops (panics on OOM, no error unions)
pub const LargeExpPowCtx = struct {
    cg: *NativeCodegen,
    binop: ast.Node.BinOp,
    left_is_bool: bool,
    right_is_bool: bool,
    alloc_name: []const u8,

    pub fn emit(ctx: @This(), _: *NativeCodegen) CodegenError!void {
        // Use unified_int_ops.pow(left, exp, allocator) -> UnifiedInt
        try ctx.cg.emit("runtime.unified_int_ops.pow(runtime.unified_int_ops.fromI64(");
        // Left operand with bool conversion
        if (ctx.left_is_bool) {
            try ctx.cg.emit("@as(i64, @intFromBool(");
            try genExpr(ctx.cg, ctx.binop.left.*);
            try ctx.cg.emit("))");
        } else {
            try genExpr(ctx.cg, ctx.binop.left.*);
        }
        try ctx.cg.emit("), @as(u32, @intCast(");
        // Right operand with bool conversion
        if (ctx.right_is_bool) {
            try ctx.cg.emit("@as(i64, @intFromBool(");
            try genExpr(ctx.cg, ctx.binop.right.*);
            try ctx.cg.emit("))");
        } else {
            try genExpr(ctx.cg, ctx.binop.right.*);
        }
        try ctx.cg.emit(")), ");
        try ctx.cg.emit(ctx.alloc_name);
        try ctx.cg.emit(")");
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

    // Get the runtime helper function name
    const op_name = @tagName(binop.op);
    const runtime_fn = BigIntRuntimeOps.get(op_name) orelse {
        // Unsupported operation - use VM fallback for drop-in CPython replacement
        try self.flushBuilder();
        try self.emitVMFallback(.{ .binop = binop });
        return;
    };

    // Emit: runtime.bigint_ops.xxx(left, right, allocator)
    try b.write("runtime.bigint_ops.");
    try b.write(runtime_fn);
    try b.write("(");

    // Emit left operand (convert to BigInt if needed)
    try emitBigIntOperandValue(self, b, left_type, left_operand);
    try b.write(", ");

    // For shift/pow operations, right operand is a primitive (usize/u32)
    if (binop.op == .LShift or binop.op == .RShift) {
        try emitShiftOperand(self, b, right_operand);
    } else if (binop.op == .Pow) {
        try emitPowExponent(self, b, right_operand);
    } else {
        // Standard binary ops: right operand is also BigInt
        try emitBigIntOperandValue(self, b, right_type, right_operand);
    }

    try b.write(", __global_allocator)");
    try self.flushBuilder();
}

/// Emit an operand as a BigInt value (AST node version)
/// Handles conversion from i64, i128, or existing BigInt
pub fn emitBigIntOperand(self: *NativeCodegen, op_type: NativeType, node: *const ast.Node, alloc_name: []const u8) CodegenError!void {
    if (op_type == .bigint) {
        // Already BigInt - emit directly
        try genExpr(self, node.*);
    } else if (op_type == .int) {
        if (op_type.int.needsBigInt()) {
            // Large int (i128) - use fromInt128
            try self.emit("runtime.bigint_ops.fromInt(");
            try self.emit(alloc_name);
            try self.emit(", @as(i64, @intCast(");
            try genExpr(self, node.*);
            try self.emit(")))");
        } else {
            // Normal i64
            try self.emit("runtime.bigint_ops.fromInt(");
            try self.emit(alloc_name);
            try self.emit(", ");
            try genExpr(self, node.*);
            try self.emit(")");
        }
    } else {
        // Unknown type - try to convert as i64
        try self.emit("runtime.bigint_ops.fromInt(");
        try self.emit(alloc_name);
        try self.emit(", @as(i64, ");
        try genExpr(self, node.*);
        try self.emit("))");
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
