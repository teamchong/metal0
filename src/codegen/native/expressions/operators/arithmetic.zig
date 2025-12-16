/// Arithmetic operations: add, sub, mul, div, mod, pow, floor division
/// Handles BigInt operations, string concatenation, list concatenation, string repetition
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const expr_emitter = @import("../../expr_emitter.zig");
const genExpr = expressions.genExpr;
const producesBlockExpression = expressions.producesBlockExpression;
const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
const shared = @import("../../shared_maps.zig");
const BinaryDunders = shared.BinaryDunders;
const ReverseDunders = shared.ReverseDunders;
const collections = @import("../collections.zig");
const operator_traits = @import("../../../../analysis/traits/operator_traits.zig");
const string_traits = @import("../../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../../analysis/traits/container_traits.zig");
const type_traits = @import("../../../../analysis/traits/type_traits.zig");

/// Check if a list will be generated as a fixed array (constant + homogeneous)
fn willGenerateAsFixedArray(list_node: ast.Node) bool {
    if (list_node != .list) return false;
    const list = list_node.list;
    if (list.elts.len == 0) return false;
    // Check all elements are constants
    for (list.elts) |elem| {
        if (elem != .constant) return false;
    }
    // Check all elements are same type
    return allConstantsSameType(list.elts);
}

fn allConstantsSameType(elements: []ast.Node) bool {
    if (elements.len == 0) return true;
    const first_const = elements[0].constant;
    const first_type_tag: std.meta.Tag(@TypeOf(first_const.value)) = first_const.value;
    for (elements[1..]) |elem| {
        const elem_const = elem.constant;
        const elem_type_tag: std.meta.Tag(@TypeOf(elem_const.value)) = elem_const.value;
        if (elem_type_tag != first_type_tag) return false;
    }
    return true;
}

/// BigInt method names for standard binary operations (left.method(&right, allocator))
const BigIntStdMethods = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Add", "add" }, .{ "Sub", "sub" }, .{ "Mult", "mul" },
    .{ "FloorDiv", "floorDiv" }, .{ "Mod", "mod" },
    .{ "BitAnd", "bitAnd" }, .{ "BitOr", "bitOr" }, .{ "BitXor", "bitXor" },
});

/// Runtime helper function names for BigInt operations
/// Maps operator tag to runtime.bigint_ops.xxx function name
const BigIntRuntimeOps = std.StaticStringMap([]const u8).initComptime(.{
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

/// Generate expression, wrapping in parentheses if it's a block expression
fn genExprWrapped(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    if (producesBlockExpression(expr)) {
        try self.emit("(");
        try genExpr(self, expr);
        try self.emit(")");
    } else {
        try genExpr(self, expr);
    }
}

// =============================================================================
// BigInt operand emission helpers (module-level for callback access)
// =============================================================================

/// Emit left operand as BigInt value (for .method() calls)
fn emitBigIntLeftOperand(s: *NativeCodegen, ltype: NativeType, left: *const ast.Node, aname: []const u8) CodegenError!void {
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
fn emitBigIntRightOperand(s: *NativeCodegen, rtype: NativeType, right: *const ast.Node, aname: []const u8) CodegenError!void {
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
const BigIntBinOpCtx = struct {
    cg: *NativeCodegen,
    left_type: NativeType,
    left: *const ast.Node,
    method: []const u8,
    right_type: NativeType,
    right: *const ast.Node,
    alloc_name: []const u8,

    fn emit(ctx: @This(), _: *NativeCodegen) CodegenError!void {
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
const BigIntNegateCtx = struct {
    cg: *NativeCodegen,
    operand: *const ast.Node,
    alloc_name: []const u8,

    fn emit(ctx: @This(), blk: *expr_emitter.LabeledBlock) CodegenError!void {
        try blk.emit("var __neg_tmp = (");
        try blk.emitExpr(ctx.operand.*);
        try blk.emit(").clone(");
        try blk.emit(ctx.alloc_name);
        try blk.emit(") catch @panic(\"OOM\"); __neg_tmp.negate(); ");
        try blk.breakWith("__neg_tmp");
    }
};

/// Context for BigInt inversion (~n = -(n+1))
const BigIntInvertCtx = struct {
    cg: *NativeCodegen,
    operand: *const ast.Node,
    alloc_name: []const u8,

    fn emit(ctx: @This(), blk: *expr_emitter.LabeledBlock) CodegenError!void {
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
const UnknownNegateCtx = struct {
    cg: *NativeCodegen,
    operand: *const ast.Node,
    alloc_name: []const u8,

    fn emit(ctx: @This(), blk: *expr_emitter.LabeledBlock) CodegenError!void {
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
const BigIntShiftCtx = struct {
    cg: *NativeCodegen,
    left_type: NativeType,
    left: *const ast.Node,
    method: []const u8,
    right: *const ast.Node,
    alloc_name: []const u8,

    fn emit(ctx: @This(), _: *NativeCodegen) CodegenError!void {
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
const BigIntPowCtx = struct {
    cg: *NativeCodegen,
    left_type: NativeType,
    left: *const ast.Node,
    right: *const ast.Node,
    alloc_name: []const u8,

    fn emit(ctx: @This(), _: *NativeCodegen) CodegenError!void {
        try emitBigIntLeftOperand(ctx.cg, ctx.left_type, ctx.left, ctx.alloc_name);
        try ctx.cg.emit(".pow(@as(u32, @intCast(");
        try genExpr(ctx.cg, ctx.right.*);
        try ctx.cg.emit(")), ");
        try ctx.cg.emit(ctx.alloc_name);
    }
};

/// Context for large exponent pow with bool conversion
const LargeExpPowCtx = struct {
    cg: *NativeCodegen,
    binop: ast.Node.BinOp,
    left_is_bool: bool,
    right_is_bool: bool,
    alloc_name: []const u8,

    fn emit(ctx: @This(), _: *NativeCodegen) CodegenError!void {
        try ctx.cg.emit("(runtime.BigInt.fromInt(");
        try ctx.cg.emit(ctx.alloc_name);
        try ctx.cg.emit(", ");
        // Left operand with bool conversion
        if (ctx.left_is_bool) {
            try ctx.cg.emit("@as(i64, @intFromBool(");
            try genExpr(ctx.cg, ctx.binop.left.*);
            try ctx.cg.emit("))");
        } else {
            try genExpr(ctx.cg, ctx.binop.left.*);
        }
        try ctx.cg.emit(") catch @panic(\"OOM\")).pow(@as(u32, @intCast(");
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
    }
};

/// Recursively collect all parts of a string concatenation chain
fn collectConcatParts(self: *NativeCodegen, node: ast.Node, parts: *std.ArrayList(ast.Node)) CodegenError!void {
    if (node == .binop and node.binop.op == .Add) {
        const left_type = try self.inferExprScoped(node.binop.left.*);
        const right_type = try self.inferExprScoped(node.binop.right.*);

        // Only flatten if this is string concatenation
        if (string_traits.isStringLike(left_type) or string_traits.isStringLike(right_type)) {
            try collectConcatParts(self, node.binop.left.*, parts);
            try collectConcatParts(self, node.binop.right.*, parts);
            return;
        }
    }

    // Base case: not a string concatenation binop, add to parts
    try parts.append(self.allocator, node);
}

/// Generate BigInt binary operations using runtime.bigint_ops helpers
/// Pattern: runtime.bigint_ops.add(left, right, allocator)
/// No complex parenthesization needed - runtime handles OOM internally
fn genBigIntBinOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    const alloc_name = "__global_allocator";

    // Get the runtime helper function name
    const op_name = @tagName(binop.op);
    const runtime_fn = BigIntRuntimeOps.get(op_name) orelse {
        try self.emit("@compileError(\"Unsupported BigInt operation\")");
        return;
    };

    // Emit: runtime.bigint_ops.xxx(left, right, allocator)
    try self.emit("runtime.bigint_ops.");
    try self.emit(runtime_fn);
    try self.emit("(");

    // Emit left operand (convert to BigInt if needed)
    try emitBigIntOperand(self, left_type, binop.left, alloc_name);
    try self.emit(", ");

    // For shift/pow operations, right operand is a primitive (usize/u32)
    if (binop.op == .LShift or binop.op == .RShift) {
        try self.emit("@as(usize, @intCast(");
        try genExpr(self, binop.right.*);
        try self.emit("))");
    } else if (binop.op == .Pow) {
        try self.emit("@as(u32, @intCast(");
        try genExpr(self, binop.right.*);
        try self.emit("))");
    } else {
        // Standard binary ops: right operand is also BigInt
        try emitBigIntOperand(self, right_type, binop.right, alloc_name);
    }

    try self.emit(", ");
    try self.emit(alloc_name);
    try self.emit(")");
}

/// Emit an operand as a BigInt value
/// Handles conversion from i64, i128, or existing BigInt
fn emitBigIntOperand(self: *NativeCodegen, op_type: NativeType, node: *const ast.Node, alloc_name: []const u8) CodegenError!void {
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

/// Generate BigInt binary operations when RIGHT operand is BigInt (e.g., 0 - bigint)
/// Now uses the same runtime.bigint_ops helpers as genBigIntBinOp
fn genBigIntBinOpRightBig(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    // Delegate to the main function - it handles all cases now
    try genBigIntBinOp(self, binop, left_type, right_type);
}

/// Check if a type requires BigInt representation (explicit bigint or unbounded int)
fn needsBigInt(t: NativeType) bool {
    return t == .bigint or (t == .int and t.int.needsBigInt());
}

/// Check if a type is UnifiedInt (handles both small i64 and large BigInt)
fn isUnifiedInt(t: NativeType) bool {
    return t == .unified_int;
}

/// UnifiedInt method names for standard binary operations
const UnifiedIntMethods = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Add", "add" }, .{ "Sub", "sub" }, .{ "Mult", "mul" },
    .{ "FloorDiv", "floorDiv" }, .{ "Mod", "mod" },
    .{ "BitAnd", "bitAnd" }, .{ "BitOr", "bitOr" }, .{ "BitXor", "bitXor" },
});

/// Generate UnifiedInt binary operations using method calls
/// UnifiedInt handles both small (i64) and large (BigInt) integers automatically
fn genUnifiedIntBinOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    const alloc_name = "__global_allocator";

    // Helper to emit operand wrapped in UnifiedInt if needed
    const emitAsUnifiedInt = struct {
        fn emit(s: *NativeCodegen, node: *const ast.Node, t: NativeType, aname: []const u8) CodegenError!void {
            if (isUnifiedInt(t)) {
                // Already UnifiedInt
                try genExpr(s, node.*);
            } else if (t == .bigint) {
                // BigInt -> UnifiedInt.fromBigInt
                try s.emit("runtime.UnifiedInt.fromBigInt(");
                try genExpr(s, node.*);
                try s.emit(")");
            } else if (t == .int or t == .usize) {
                // i64/usize -> UnifiedInt.fromI64
                try s.emit("runtime.UnifiedInt.fromI64(@as(i64, ");
                try genExpr(s, node.*);
                try s.emit("))");
            } else {
                // Unknown - try to convert as i64
                _ = aname;
                try s.emit("runtime.UnifiedInt.fromI64(@as(i64, ");
                try genExpr(s, node.*);
                try s.emit("))");
            }
        }
    }.emit;

    // Standard operations use UnifiedInt methods
    const op_name = @tagName(binop.op);
    if (UnifiedIntMethods.get(op_name)) |method| {
        try self.emit("(try ");
        try emitAsUnifiedInt(self, binop.left, left_type, alloc_name);
        try self.emit(".");
        try self.emit(method);
        try self.emit("(");
        try emitAsUnifiedInt(self, binop.right, right_type, alloc_name);
        try self.emit(", ");
        try self.emit(alloc_name);
        try self.emit("))");
        return;
    }

    switch (binop.op) {
        .RShift => {
            // UnifiedInt.shr(shift_amount, allocator)
            try self.emit("(try ");
            try emitAsUnifiedInt(self, binop.left, left_type, alloc_name);
            try self.emit(".shr(@as(usize, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit(")), ");
            try self.emit(alloc_name);
            try self.emit("))");
        },
        .LShift => {
            // UnifiedInt.shl(shift_amount, allocator)
            try self.emit("(try ");
            try emitAsUnifiedInt(self, binop.left, left_type, alloc_name);
            try self.emit(".shl(@as(usize, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit(")), ");
            try self.emit(alloc_name);
            try self.emit("))");
        },
        .Pow => {
            // UnifiedInt.pow(exp, allocator)
            try self.emit("(try ");
            try emitAsUnifiedInt(self, binop.left, left_type, alloc_name);
            try self.emit(".pow(@as(u32, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit(")), ");
            try self.emit(alloc_name);
            try self.emit("))");
        },
        .Div => {
            // Python division always returns float
            try self.emit("try runtime.divideFloat(");
            try emitAsUnifiedInt(self, binop.left, left_type, alloc_name);
            try self.emit(".toI64(), ");
            try emitAsUnifiedInt(self, binop.right, right_type, alloc_name);
            try self.emit(".toI64())");
        },
        else => {
            // Unsupported UnifiedInt op - fall back to error
            try self.emit("@compileError(\"Unsupported UnifiedInt operation\")");
        },
    }
}

/// Generate complex number binary operations
/// Handles: complex + complex, int/float + complex, complex + int/float
fn genComplexBinOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    // Helper to emit a value as the real part of a complex number
    const emitAsComplex = struct {
        fn emit(s: *NativeCodegen, node: ast.Node, t: NativeType) CodegenError!void {
            if (t == .complex) {
                // Already complex
                try genExpr(s, node);
            } else if (t == .float) {
                // float -> complex with real part
                try s.emit("runtime.PyComplex.create(");
                try genExpr(s, node);
                try s.emit(", 0.0)");
            } else {
                // int/bool -> complex with real part
                try s.emit("runtime.PyComplex.create(@as(f64, @floatFromInt(");
                try genExpr(s, node);
                try s.emit(")), 0.0)");
            }
        }
    }.emit;

    switch (binop.op) {
        .Add => {
            // complex.add(other)
            try emitAsComplex(self, binop.left.*, left_type);
            try self.emit(".add(");
            try emitAsComplex(self, binop.right.*, right_type);
            try self.emit(")");
        },
        .Sub => {
            // complex.sub(other)
            try emitAsComplex(self, binop.left.*, left_type);
            try self.emit(".sub(");
            try emitAsComplex(self, binop.right.*, right_type);
            try self.emit(")");
        },
        .Mult => {
            // complex.mul(other)
            try emitAsComplex(self, binop.left.*, left_type);
            try self.emit(".mul(");
            try emitAsComplex(self, binop.right.*, right_type);
            try self.emit(")");
        },
        .Div => {
            // complex.div(other)
            try emitAsComplex(self, binop.left.*, left_type);
            try self.emit(".div(");
            try emitAsComplex(self, binop.right.*, right_type);
            try self.emit(")");
        },
        else => {
            // Unsupported complex operation - fall back to error
            try self.emit("@compileError(\"Unsupported complex operation\")");
        },
    }
}

/// PyValue method names for binary operations
const PyValueMethods = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Add", "add" },
    .{ "Sub", "sub" },
    .{ "Mult", "mul" },
    .{ "Div", "div" },
    .{ "FloorDiv", "floordiv" },
    .{ "Mod", "mod" },
    // Bitwise operations for Two-Flow uncertain operands
    .{ "BitAnd", "pyBitAnd" },
    .{ "BitOr", "pyBitOr" },
    .{ "BitXor", "pyBitXor" },
    .{ "LShift", "pyLShift" },
    .{ "RShift", "pyRShift" },
    .{ "Pow", "pyPow" },
});

/// Check if an expression operand is uncertain (needs PyValue)
fn isOperandUncertain(self: *NativeCodegen, expr: ast.Node) bool {
    // Check if this is a variable with uncertain confidence
    if (expr == .name) {
        const name = expr.name.id;

        // NEVER treat 'self' in class methods as uncertain - it's always the concrete class type
        if (std.mem.eql(u8, name, "self")) {
            return false;
        }

        // NEVER treat anytype parameters as uncertain - they use comptime polymorphism
        if (self.anytype_params.contains(name)) {
            return false;
        }

        // FIRST: Check scoped vars (for loop variables, function params)
        // then fall back to global var_types
        const var_type = self.type_inferrer.getScopedVar(name) orelse
            self.type_inferrer.var_types.get(name);
        if (var_type) |vt| {
            switch (vt) {
                // Explicit PyValue or unknown - always use PyValue methods
                .pyvalue, .unknown => return true,
                // Concrete types - don't use PyValue methods (loop variables, etc.)
                .string, .int, .float, .bool, .none, .bytes => return false,
                // Class instances - don't use PyValue methods
                .class_instance => return false,
                else => {},
            }
        }
        // Fall back to confidence check for variables not in var_types
        // or with unknown types
        return self.isVarUncertain(name);
    }
    return false;
}

/// Generate PyValue binary operations for uncertain operands
fn genPyValueBinOp(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    const method_name = PyValueMethods.get(@tagName(binop.op)) orelse {
        // Unsupported operation - fall back to compile error
        try self.emit("@compileError(\"Unsupported PyValue operation: ");
        try self.emit(@tagName(binop.op));
        try self.emit("\")");
        return;
    };

    // ALWAYS wrap both operands in PyValue.from() for safety
    // This handles mixed type operations like: primitive // PyValue
    // PyValue.from() is a no-op for existing PyValues, so it's safe to wrap unconditionally
    // This avoids complex type tracking issues where one operand might be uncertain
    // but the type inference doesn't detect it correctly
    try self.emit("(runtime.PyValue.from(");
    try genExpr(self, binop.left.*);
    try self.emit(")).");
    try self.emit(method_name);
    try self.emit("(runtime.PyValue.from(");
    try genExpr(self, binop.right.*);
    try self.emit("))");
}

/// Generate binary operations (+, -, *, /, %, //)
pub fn genBinOp(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    // Check for BigInt operations first
    // Use scope-aware type inference to prevent cross-function type pollution
    const bigint_left_type = try self.inferExprScoped(binop.left.*);
    const bigint_right_type = try self.inferExprScoped(binop.right.*);

    // TWO-FLOW TYPE SYSTEM: Check if either operand is uncertain (needs PyValue)
    // If so, use safe PyValue arithmetic methods instead of raw Zig operators
    const left_uncertain = isOperandUncertain(self, binop.left.*);
    const right_uncertain = isOperandUncertain(self, binop.right.*);
    if (left_uncertain or right_uncertain) {
        // Only use PyValue ops for supported arithmetic operations
        // EXCEPTION: For Mod operator, check if left is string - that's string formatting, not arithmetic
        if (PyValueMethods.get(@tagName(binop.op)) != null) {
            // Skip PyValue.mod() for string formatting - let the standard handling do it
            if (binop.op == .Mod) {
                const left_type = try self.inferExprScoped(binop.left.*);
                if (string_traits.isString(left_type) or (binop.left.* == .constant and binop.left.constant.value == .string)) {
                    // String formatting - don't use PyValue.mod(), fall through to standard handling
                } else {
                    try genPyValueBinOp(self, binop);
                    return;
                }
            } else {
                try genPyValueBinOp(self, binop);
                return;
            }
        }
    }

    // IMPORTANT: For Mod operator with string/bytes left operand, this is string formatting
    // NOT BigInt modulo. Skip BigInt handling to let the string formatting handler at line ~1039 handle it.
    const is_string_formatting = blk: {
        if (binop.op != .Mod) break :blk false;
        // Check if left operand is a string/bytes literal
        if (binop.left.* == .constant) {
            if (binop.left.constant.value == .string) break :blk true;
            if (binop.left.constant.value == .bytes) break :blk true;
        }
        // Check inferred type
        if (string_traits.isString(bigint_left_type) or string_traits.isBytes(bigint_left_type)) break :blk true;
        break :blk false;
    };

    // If left operand needs BigInt (explicit bigint or unbounded int), use BigInt method calls
    // BUT NOT for string formatting operations
    if (needsBigInt(bigint_left_type) and !is_string_formatting) {
        try genBigIntBinOp(self, binop, bigint_left_type, bigint_right_type);
        return;
    }

    // If right operand needs BigInt (e.g., 0 - bigint), convert left to BigInt and use BigInt ops
    // BUT NOT for string formatting operations
    if (needsBigInt(bigint_right_type) and !is_string_formatting) {
        try genBigIntBinOpRightBig(self, binop, bigint_left_type, bigint_right_type);
        return;
    }

    // If either operand is UnifiedInt, use UnifiedInt method calls
    // BUT NOT for string formatting operations
    if ((isUnifiedInt(bigint_left_type) or isUnifiedInt(bigint_right_type)) and !is_string_formatting) {
        try genUnifiedIntBinOp(self, binop, bigint_left_type, bigint_right_type);
        return;
    }

    // Check for custom class with dunder methods (e.g., x + 1 calls x.__add__(1))
    // Must check before other type-specific handling
    // IMPORTANT: Only call dunder methods if the CLASS operand is a KNOWN class instance (not anytype)
    // If left is a KNOWN class instance (e.g., self), call left.__add__(right) regardless of right's type
    const left_is_anytype = if (binop.left.* == .name) self.anytype_params.contains(binop.left.name.id) else false;
    const right_is_anytype = if (binop.right.* == .name) self.anytype_params.contains(binop.right.name.id) else false;

    // If left operand is a known class instance (not anytype), call dunder method on left
    if (type_traits.isClassInstance(bigint_left_type) and !left_is_anytype) {
        if (BinaryDunders.get(@tagName(binop.op))) |dunder_method| {
            try self.emit("try ");
            try genExpr(self, binop.left.*);
            try self.emit(".");
            try self.emit(dunder_method);
            try self.emit("(__global_allocator, ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
            return;
        }
    }

    // If right operand is a known class instance (not anytype) and left is not class, call __radd__ etc.
    // Only call if the class actually implements the reverse dunder method
    if (type_traits.isClassInstance(bigint_right_type) and !right_is_anytype and !type_traits.isClassInstance(bigint_left_type)) {
        if (ReverseDunders.get(@tagName(binop.op))) |rdunder_method| {
            // Generate comptime check for method existence using container_dispatch helper
            // Reduces monomorphization by centralizing @typeInfo/@hasDecl checks
            // If method exists, call it; otherwise raise TypeError at runtime
            try self.emit("radd_blk: { const _rhs = ");
            try genExpr(self, binop.right.*);
            try self.output.writer(self.allocator).print("; if (runtime.container_dispatch.hasPtrChildDecl(@TypeOf(_rhs), \"{s}\")) {{ break :radd_blk try _rhs.{s}(__global_allocator, ", .{ rdunder_method, rdunder_method });
            try genExpr(self, binop.left.*);
            try self.emit("); } else { return error.TypeError; } }");
            return;
        }
    }

    // Check for complex number operations and mixed int/float arithmetic
    // Must check BOTH Add and Sub for complex operand type coercion
    if (binop.op == .Add or binop.op == .Sub) {
        const left_type = try self.inferExprScoped(binop.left.*);
        const right_type = try self.inferExprScoped(binop.right.*);

        // Handle complex arithmetic: int/float +/- complex -> complex
        if (left_type == .complex or right_type == .complex) {
            try genComplexBinOp(self, binop, left_type, right_type);
            return;
        }

        // Handle mixed int/float arithmetic using runtime helper
        // This is needed because Zig doesn't allow direct arithmetic between int and float
        // Use runtime helper when:
        // 1. One operand is definitively int and the other is definitively float
        // 2. One operand is int and other is unknown (unknown could be any type from tuple unpack, closure param, etc.)
        // 3. One operand is float and other is unknown
        const left_is_int = type_traits.isIntegral(left_type);
        const right_is_int = type_traits.isIntegral(right_type);
        const left_is_float = type_traits.isFloating(left_type);
        const right_is_float = type_traits.isFloating(right_type);
        const left_is_unknown = type_traits.isUnknown(left_type);
        const right_is_unknown = type_traits.isUnknown(right_type);

        // Use runtime helpers when types could be mixed (any combination involving unknown or explicit int+float)
        const needs_runtime_helper = (left_is_int and right_is_float) or
            (left_is_float and right_is_int) or
            (left_is_int and right_is_unknown) or
            (left_is_unknown and right_is_int) or
            (left_is_float and right_is_unknown) or
            (left_is_unknown and right_is_float);

        if (needs_runtime_helper) {
            // Use runtime helper for potentially mixed type arithmetic
            if (binop.op == .Add) {
                try self.emit("runtime.addNum(");
            } else {
                try self.emit("runtime.subtractNum(");
            }
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
            return;
        }
    }

    // Check if this is string concatenation
    if (binop.op == .Add) {
        // Use scope-aware type inference to prevent cross-function type pollution
        const left_type = try self.inferExprScoped(binop.left.*);
        const right_type = try self.inferExprScoped(binop.right.*);

        if (string_traits.isString(left_type) or string_traits.isString(right_type)) {
            // Flatten nested concatenations to avoid intermediate allocations
            var parts = std.ArrayList(ast.Node){};
            defer parts.deinit(self.allocator);

            try collectConcatParts(self, ast.Node{ .binop = binop }, &parts);

            // Always use __global_allocator (TryHelper structs can't access outer allocator)
            const alloc_name = "__global_allocator";

            // At module level (scope 0), we can't use 'try' - use 'catch unreachable' instead
            const at_module_level = self.symbol_table.currentScopeLevel() == 0;

            // Generate single concat call with all parts
            if (at_module_level) {
                try self.emit("(std.mem.concat(");
            } else {
                try self.emit("try std.mem.concat(");
            }
            try self.emit(alloc_name);
            try self.emit(", u8, &[_][]const u8{ ");
            for (parts.items, 0..) |part, i| {
                if (i > 0) try self.emit(", ");
                try genExpr(self, part);
            }
            if (at_module_level) {
                try self.emit(" }) catch unreachable)");
            } else {
                try self.emit(" })");
            }
            return;
        }

        // Check for bytes concatenation: bytes + bytes
        // Use catch instead of try to work at module level
        if (string_traits.isBytes(left_type) or string_traits.isBytes(right_type)) {
            const alloc_name = "__global_allocator";
            try self.emit("(runtime.builtins.PyBytes.concat(");
            try self.emit(alloc_name);
            try self.emit(", ");
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(") catch @panic(\"OOM\"))");
            return;
        }

        // Check for list concatenation: list + list or array + array
        // Also check AST nodes for list literals since type inference may return .unknown
        // Also check for ArrayList variables (runtime tracking)
        const left_is_arraylist_var = binop.left.* == .name and self.isArrayListVar(binop.left.name.id);
        const right_is_arraylist_var = binop.right.* == .name and self.isArrayListVar(binop.right.name.id);
        if (container_traits.isList(left_type) or container_traits.isList(right_type) or
            binop.left.* == .list or binop.right.* == .list or
            left_is_arraylist_var or right_is_arraylist_var)
        {
            // Check if either operand might produce a runtime value (ArrayList, PyValue)
            // This includes: call expressions, nested binops, and unknown types
            const left_is_call = binop.left.* == .call;
            const right_is_call = binop.right.* == .call;
            const left_is_binop = binop.left.* == .binop;
            const right_is_binop = binop.right.* == .binop;
            const left_is_name = binop.left.* == .name;
            const right_is_name = binop.right.* == .name;

            // Use runtime concatenation for any potentially runtime values
            // This is safer and handles all edge cases (ArrayList, PyValue, etc.)
            const needs_runtime = left_is_call or right_is_call or
                left_is_binop or right_is_binop or
                left_is_name or right_is_name or
                left_type == .unknown or right_type == .unknown or
                left_type == .pyvalue or right_type == .pyvalue or
                left_is_arraylist_var or right_is_arraylist_var;

            if (needs_runtime) {
                // Use runtime concatenation for non-comptime values
                try self.emit("try runtime.concatRuntime(__global_allocator, ");
                try genExpr(self, binop.left.*);
                try self.emit(", ");
                try genExpr(self, binop.right.*);
                try self.emit(")");
            } else {
                // List/array concatenation: use runtime.concat which handles both
                try self.emit("runtime.concat(");
                try genExpr(self, binop.left.*);
                try self.emit(", ");
                try genExpr(self, binop.right.*);
                try self.emit(")");
            }
            return;
        }

        // Check for tuple concatenation: tuple + tuple
        const left_is_tuple = binop.left.* == .tuple or container_traits.isTuple(left_type);
        const right_is_tuple = binop.right.* == .tuple or container_traits.isTuple(right_type);
        if (left_is_tuple and right_is_tuple) {
            // Tuple concatenation: use comptime tuple concat (++)
            try genExpr(self, binop.left.*);
            try self.emit(" ++ ");
            try genExpr(self, binop.right.*);
            return;
        }

        // Check for complex number addition: int/float + complex -> complex
        if (left_type == .complex or right_type == .complex) {
            try genComplexBinOp(self, binop, left_type, right_type);
            return;
        }
    }

    // Check if this is string multiplication (str * n or n * str)
    if (binop.op == .Mult) {
        const left_type = try self.inferExprScoped(binop.left.*);
        const right_type = try self.inferExprScoped(binop.right.*);

        // str * n -> repeat string n times
        if (string_traits.isString(left_type) and (type_traits.isIntegral(right_type) or type_traits.isUnknown(right_type))) {
            const alloc_name = "__global_allocator";
            try self.emit("runtime.strRepeat(");
            try self.emit(alloc_name);
            try self.emit(", ");
            try genExpr(self, binop.left.*);
            try self.emit(", @as(usize, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit(")))");
            return;
        }

        // bytes * n -> repeat bytes n times
        // Use catch instead of try to work at module level
        if (string_traits.isBytes(left_type) and (type_traits.isIntegral(right_type) or type_traits.isUnknown(right_type))) {
            const alloc_name = "__global_allocator";
            try self.emit("(runtime.builtins.PyBytes.repeat(");
            try self.emit(alloc_name);
            try self.emit(", ");
            try genExpr(self, binop.left.*);
            try self.emit(", @as(usize, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit("))) catch @panic(\"OOM\"))");
            return;
        }

        // n * bytes -> repeat bytes n times
        // Use catch instead of try to work at module level
        if (string_traits.isBytes(right_type) and (type_traits.isIntegral(left_type) or type_traits.isUnknown(left_type))) {
            const alloc_name = "__global_allocator";
            try self.emit("(runtime.builtins.PyBytes.repeat(");
            try self.emit(alloc_name);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(", @as(usize, @intCast(");
            try genExpr(self, binop.left.*);
            try self.emit("))) catch @panic(\"OOM\"))");
            return;
        }

        // list * n -> repeat list n times
        const left_is_arraylist_var = binop.left.* == .name and self.isArrayListVar(binop.left.name.id);
        if ((container_traits.isList(left_type) or container_traits.isArray(left_type) or binop.left.* == .list or left_is_arraylist_var) and
            (type_traits.isIntegral(right_type) or type_traits.isUnknown(right_type)))
        {
            const alloc_name = "__global_allocator";
            try self.emit("try runtime.repeatRuntime(");
            try self.emit(alloc_name);
            try self.emit(", ");
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
            return;
        }

        // n * list -> repeat list n times
        const right_is_arraylist_var = binop.right.* == .name and self.isArrayListVar(binop.right.name.id);
        if ((container_traits.isList(right_type) or container_traits.isArray(right_type) or binop.right.* == .list or right_is_arraylist_var) and
            (type_traits.isIntegral(left_type) or type_traits.isUnknown(left_type)))
        {
            const alloc_name = "__global_allocator";
            try self.emit("try runtime.repeatRuntime(");
            try self.emit(alloc_name);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(", ");
            try genExpr(self, binop.left.*);
            try self.emit(")");
            return;
        }

        // unknown * int - could be string repeat in inline for context
        // Generate comptime type check with unique label to avoid conflicts
        if (type_traits.isUnknown(left_type) and (type_traits.isIntegral(right_type) or type_traits.isUnknown(right_type))) {
            const alloc_name = "__global_allocator";
            var em = self.exprEmitter();
            var blk = try em.labeledBlock("mul", "_lhs", binop.left.*);
            try blk.emit("const _rhs = ");
            try genExpr(self, binop.right.*);
            // For string * n with n < 0, return empty string; for numeric types, just multiply
            try blk.emit("; ");
            try blk.startBreak();
            try self.emit("if (@TypeOf(_lhs) == []const u8) (if (_rhs < 0) \"\" else runtime.strRepeat(");
            try self.emit(alloc_name);
            try self.emit(", _lhs, @as(usize, @intCast(_rhs)))) else _lhs * _rhs");
            try blk.close();
            return;
        }
        // n * str -> repeat string n times
        if (string_traits.isString(right_type) and (type_traits.isIntegral(left_type) or type_traits.isUnknown(left_type))) {
            const alloc_name = "__global_allocator";
            try self.emit("runtime.strRepeat(");
            try self.emit(alloc_name);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(", @as(usize, @intCast(");
            try genExpr(self, binop.left.*);
            try self.emit(")))");
            return;
        }

        // tuple * n -> repeat tuple n times (returns a list/slice)
        // Check both AST node type (.tuple literal) and inferred type (.tuple)
        const left_is_tuple = binop.left.* == .tuple or container_traits.isTuple(left_type);
        const right_is_tuple = binop.right.* == .tuple or container_traits.isTuple(right_type);
        if (left_is_tuple and (type_traits.isIntegral(right_type) or type_traits.isUnknown(right_type))) {
            const alloc_name = "__global_allocator";
            try self.emit("runtime.tupleRepeat(");
            try self.emit(alloc_name);
            try self.emit(", ");
            try genExpr(self, binop.left.*);
            try self.emit(", @as(usize, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit(")))");
            return;
        }
        // n * tuple -> repeat tuple n times
        if (right_is_tuple and (type_traits.isIntegral(left_type) or type_traits.isUnknown(left_type))) {
            const alloc_name = "__global_allocator";
            try self.emit("runtime.tupleRepeat(");
            try self.emit(alloc_name);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(", @as(usize, @intCast(");
            try genExpr(self, binop.left.*);
            try self.emit(")))");
            return;
        }

        // list * n -> repeat list n times
        const left_is_list = binop.left.* == .list or container_traits.isList(left_type);
        const right_is_list = binop.right.* == .list or container_traits.isList(right_type);
        if (left_is_list and (type_traits.isIntegral(right_type) or type_traits.isUnknown(right_type))) {
            const alloc_name = "__global_allocator";
            try self.emit("runtime.sliceRepeatDynamic(");
            try self.emit(alloc_name);
            try self.emit(", ");
            // Constant homogeneous list literals produce fixed arrays - use & to coerce to slice
            // Complex or dynamic lists produce ArrayList - use .items
            if (willGenerateAsFixedArray(binop.left.*)) {
                // Fixed array literal - use & to get slice
                try self.emit("&");
                try genExpr(self, binop.left.*);
            } else if (producesBlockExpression(binop.left.*)) {
                try self.emit("(");
                try genExpr(self, binop.left.*);
                try self.emit(").items");
            } else {
                try genExpr(self, binop.left.*);
                try self.emit(".items");
            }
            try self.emit(", @as(usize, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit(")))");
            return;
        }
        // n * list -> repeat list n times
        if (right_is_list and (type_traits.isIntegral(left_type) or type_traits.isUnknown(left_type))) {
            const alloc_name = "__global_allocator";
            try self.emit("runtime.sliceRepeatDynamic(");
            try self.emit(alloc_name);
            try self.emit(", ");
            // Constant homogeneous list literals produce fixed arrays - use & to coerce to slice
            // Complex or dynamic lists produce ArrayList - use .items
            if (willGenerateAsFixedArray(binop.right.*)) {
                // Fixed array literal - use & to get slice
                try self.emit("&");
                try genExpr(self, binop.right.*);
            } else if (producesBlockExpression(binop.right.*)) {
                try self.emit("(");
                try genExpr(self, binop.right.*);
                try self.emit(").items");
            } else {
                try genExpr(self, binop.right.*);
                try self.emit(".items");
            }
            try self.emit(", @as(usize, @intCast(");
            try genExpr(self, binop.left.*);
            try self.emit(")))");
            return;
        }
    }

    // Regular numeric operations
    // Special handling for floor division (//): use operator_traits for semantics
    if (binop.op == .FloorDiv) {
        const left_type = try self.inferExprScoped(binop.left.*);
        const right_type = try self.inferExprScoped(binop.right.*);
        const semantics = operator_traits.getFloorDivSemantics(left_type, right_type);
        switch (semantics) {
            .runtime_dispatch => {
                // Unknown types - use runtime dispatch
                try self.emit("runtime.pyFloorDiv(__global_allocator, ");
                try genExpr(self, binop.left.*);
                try self.emit(", ");
                try genExpr(self, binop.right.*);
                try self.emit(")");
            },
            .python_floored => {
                // Floats - floor(a / b) returns float
                try self.emit("@floor(");
                try genExpr(self, binop.left.*);
                try self.emit(" / ");
                try genExpr(self, binop.right.*);
                try self.emit(")");
            },
            .zig_native => {
                // Integers - use @divFloor with bool conversion if needed
                try self.emit("@divFloor(");
                if (type_traits.isBoolean(left_type)) {
                    try self.emit("@as(i64, @intFromBool(");
                    try genExpr(self, binop.left.*);
                    try self.emit("))");
                } else {
                    try genExpr(self, binop.left.*);
                }
                try self.emit(", ");
                if (type_traits.isBoolean(right_type)) {
                    try self.emit("@as(i64, @intFromBool(");
                    try genExpr(self, binop.right.*);
                    try self.emit("))");
                } else {
                    try genExpr(self, binop.right.*);
                }
                try self.emit(")");
            },
        }
        return;
    }

    // Special handling for modulo / string formatting
    if (binop.op == .Mod) {
        // Check if this is Python string formatting: "%d" % value
        const left_type = try self.inferExprScoped(binop.left.*);
        if (string_traits.isString(left_type) or (binop.left.* == .constant and binop.left.constant.value == .string)) {
            // Python string formatting: "format" % value(s)
            const genStringFormat = @import("./formatting.zig").genStringFormat;
            try genStringFormat(self, binop);
            return;
        }
        // Use operator_traits for modulo semantics
        const right_type = try self.inferExprScoped(binop.right.*);
        const semantics = operator_traits.getModuloSemantics(left_type, right_type);
        switch (semantics) {
            .runtime_dispatch => {
                // Unknown types - use runtime dispatch
                try self.emit("runtime.pyMod(__global_allocator, ");
                try genExpr(self, binop.left.*);
                try self.emit(", ");
                try genExpr(self, binop.right.*);
                try self.emit(")");
            },
            .python_floored => {
                // Floats - use Python's floored modulo
                try self.emit("runtime.pyFloatMod(");
                try genExpr(self, binop.left.*);
                try self.emit(", ");
                try genExpr(self, binop.right.*);
                try self.emit(")");
            },
            .zig_native => {
                // Integers - use @mod with bool conversion if needed
                try self.emit("@mod(");
                if (type_traits.isBoolean(left_type)) {
                    try self.emit("@as(i64, @intFromBool(");
                    try genExpr(self, binop.left.*);
                    try self.emit("))");
                } else {
                    try genExpr(self, binop.left.*);
                }
                try self.emit(", ");
                if (type_traits.isBoolean(right_type)) {
                    try self.emit("@as(i64, @intFromBool(");
                    try genExpr(self, binop.right.*);
                    try self.emit("))");
                } else {
                    try genExpr(self, binop.right.*);
                }
                try self.emit(")");
            },
        }
        return;
    }

    // Special handling for power
    if (binop.op == .Pow) {
        // Check types for bool handling
        const left_type = try self.inferExprScoped(binop.left.*);
        const right_type = try self.inferExprScoped(binop.right.*);
        const left_is_bool = type_traits.isBoolean(left_type);
        const right_is_bool = type_traits.isBoolean(right_type);

        // Helper to emit left operand with possible bool conversion
        const emitLeft = struct {
            fn emit(s: *NativeCodegen, binop_inner: ast.Node.BinOp, is_bool: bool) CodegenError!void {
                if (is_bool) {
                    try s.emit("@as(i64, @intFromBool(");
                    try genExpr(s, binop_inner.left.*);
                    try s.emit("))");
                } else {
                    try genExpr(s, binop_inner.left.*);
                }
            }
        }.emit;

        // Helper to emit right operand with possible bool conversion
        const emitRight = struct {
            fn emit(s: *NativeCodegen, binop_inner: ast.Node.BinOp, is_bool: bool) CodegenError!void {
                if (is_bool) {
                    try s.emit("@as(i64, @intFromBool(");
                    try genExpr(s, binop_inner.right.*);
                    try s.emit("))");
                } else {
                    try genExpr(s, binop_inner.right.*);
                }
            }
        }.emit;

        // Check if exponent is large enough to need BigInt
        if (binop.right.* == .constant and binop.right.constant.value == .int) {
            const exp = binop.right.constant.value.int;
            if (exp >= 20) {
                // Use BigInt for large exponents with callback pattern
                var em = self.exprEmitter();
                try em.withOOMCatch(LargeExpPowCtx{
                    .cg = self,
                    .binop = binop,
                    .left_is_bool = left_is_bool,
                    .right_is_bool = right_is_bool,
                    .alloc_name = "__global_allocator",
                }, LargeExpPowCtx.emit);
                return;
            }
            // Small constant positive exponent - use i64
            try self.emit("std.math.pow(i64, ");
            try emitLeft(self, binop, left_is_bool);
            try self.emit(", ");
            try emitRight(self, binop, right_is_bool);
            try self.emit(")");
            return;
        }
        // Runtime exponent (could be negative) - use f64 for safety
        // Python: 10 ** -1 = 0.1 (float), 10 ** random.randint(-100, 100) could be negative
        try self.emit("std.math.pow(f64, @as(f64, @floatFromInt(");
        try emitLeft(self, binop, left_is_bool);
        try self.emit(")), @as(f64, @floatFromInt(");
        try emitRight(self, binop, right_is_bool);
        try self.emit(")))");
        return;
    }

    // Special handling for division - can throw ZeroDivisionError
    if (binop.op == .Div) {
        // Check if this is Path / string (path join)
        const left_type = try self.inferExprScoped(binop.left.*);
        if (left_type == .path) {
            // Path / "component" -> Path.join("component")
            try genExpr(self, binop.left.*);
            try self.emit(".join(");
            try genExpr(self, binop.right.*);
            try self.emit(")");
            return;
        }

        const right_type = try self.inferExprScoped(binop.right.*);
        const left_is_bool = type_traits.isBoolean(left_type);
        const right_is_bool = type_traits.isBoolean(right_type);

        // True division (/) - always returns float
        // At module level (indent_level == 0), we can't use 'try', so use direct division
        if (self.indent_level == 0) {
            // Direct division for module-level constants (assume no divide-by-zero)
            try self.emit("(@as(f64, @floatFromInt(");
            if (left_is_bool) {
                try self.emit("@as(i64, @intFromBool(");
                try genExpr(self, binop.left.*);
                try self.emit("))");
            } else {
                try genExpr(self, binop.left.*);
            }
            try self.emit(")) / @as(f64, @floatFromInt(");
            if (right_is_bool) {
                try self.emit("@as(i64, @intFromBool(");
                try genExpr(self, binop.right.*);
                try self.emit("))");
            } else {
                try genExpr(self, binop.right.*);
            }
            try self.emit(")))");
        } else {
            try self.emit("try runtime.divideFloat(");
            if (left_is_bool) {
                try self.emit("@as(i64, @intFromBool(");
                try genExpr(self, binop.left.*);
                try self.emit("))");
            } else {
                try genExpr(self, binop.left.*);
            }
            try self.emit(", ");
            if (right_is_bool) {
                try self.emit("@as(i64, @intFromBool(");
                try genExpr(self, binop.right.*);
                try self.emit("))");
            } else {
                try genExpr(self, binop.right.*);
            }
            try self.emit(")");
        }
        return;
    }

    // Matrix multiplication (@) - call __matmul__ or __rmatmul__ method on object
    if (binop.op == .MatMul) {
        const left_type = try self.inferExprScoped(binop.left.*);
        const right_type = try self.inferExprScoped(binop.right.*);

        if (type_traits.isClassInstance(left_type) or type_traits.isUnknown(left_type)) {
            // Left is a class, call __matmul__: try left.__matmul__(allocator, right)
            try self.emit("try ");
            try genExpr(self, binop.left.*);
            try self.emit(".__matmul__(__global_allocator, ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
        } else if (type_traits.isClassInstance(right_type) or type_traits.isUnknown(right_type)) {
            // Right is a class, call __rmatmul__: try right.__rmatmul__(allocator, left)
            try self.emit("try ");
            try genExpr(self, binop.right.*);
            try self.emit(".__rmatmul__(__global_allocator, ");
            try genExpr(self, binop.left.*);
            try self.emit(")");
        } else {
            // Generic fallback - call __matmul__ on left
            try self.emit("try ");
            try genExpr(self, binop.left.*);
            try self.emit(".__matmul__(__global_allocator, ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
        }
        return;
    }

    // Check for large shifts that require BigInt
    // e.g., 1 << 100000 exceeds i64 range, needs BigInt
    // Also need BigInt when RHS is not comptime-known (Zig requires fixed-width int for LHS if RHS unknown)
    if (binop.op == .LShift) {
        const is_comptime_shift = binop.right.* == .constant and binop.right.constant.value == .int;
        const is_large_shift = is_comptime_shift and binop.right.constant.value.int >= 63;

        // Use BigInt for large shifts OR when shift amount is not comptime-known
        if (is_large_shift or !is_comptime_shift) {
            const alloc_name = "__global_allocator";
            try self.emit("(runtime.BigInt.fromInt(");
            try self.emit(alloc_name);
            try self.emit(", ");
            try genExpr(self, binop.left.*);
            try self.emit(") catch @panic(\"OOM\")).shl(@as(usize, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit(")), ");
            try self.emit(alloc_name);
            try self.emit(") catch @panic(\"OOM\")");
            return;
        }
    }

    // Check for type mismatches between usize and i64
    const left_type = try self.inferExprScoped(binop.left.*);
    const right_type = try self.inferExprScoped(binop.right.*);

    // Python 3.9+ dict merge: dict1 | dict2 creates new merged dict
    // dict1 |= dict2 is handled separately in aug_assign
    if (binop.op == .BitOr and container_traits.isDict(left_type) and container_traits.isDict(right_type)) {
        // Generate: blk: { var __merged = dict1.copy(); __merged.update(dict2); break :blk __merged; }
        var em = self.exprEmitter();
        const label_id = em.reserveLabelId();
        try self.emitFmt("(dmerge_{d}: {{\n", .{label_id});
        self.indent_level += 1;

        try self.emitIndent();
        try self.emit("var __merged = @TypeOf(");
        try genExprWrapped(self, binop.left.*);
        try self.emit("){};\n");

        // Copy left dict
        try self.emitIndent();
        try self.emit("var __left_iter = ");
        try genExprWrapped(self, binop.left.*);
        try self.emit(".iterator();\n");
        try self.emitIndent();
        try self.emit("while (__left_iter.next()) |entry| {\n");
        self.indent_level += 1;
        try self.emitIndent();
        // ArrayHashMap.put() doesn't take allocator
        try self.emit("try __merged.put(entry.key_ptr.*, entry.value_ptr.*);\n");
        self.indent_level -= 1;
        try self.emitIndent();
        try self.emit("}\n");

        // Update with right dict
        try self.emitIndent();
        try self.emit("var __right_iter = ");
        try genExprWrapped(self, binop.right.*);
        try self.emit(".iterator();\n");
        try self.emitIndent();
        try self.emit("while (__right_iter.next()) |entry| {\n");
        self.indent_level += 1;
        try self.emitIndent();
        // ArrayHashMap.put() doesn't take allocator
        try self.emit("try __merged.put(entry.key_ptr.*, entry.value_ptr.*);\n");
        self.indent_level -= 1;
        try self.emitIndent();
        try self.emit("}\n");

        try self.emitIndent();
        try self.output.writer(self.allocator).print("break :dmerge_{d} __merged;\n", .{label_id});

        self.indent_level -= 1;
        try self.emitIndent();
        try self.emit("})");
        return;
    }

    const left_is_usize = (left_type == .usize);
    const left_is_int = type_traits.isIntegral(left_type);
    const left_is_bool = type_traits.isBoolean(left_type);
    const right_is_usize = (right_type == .usize);
    const right_is_int = type_traits.isIntegral(right_type);
    const right_is_bool = type_traits.isBoolean(right_type);

    // Python: bool & bool = bool, bool | bool = bool, bool ^ bool = bool
    // When both operands are bools and op is bitwise, result is bool
    if (left_is_bool and right_is_bool and
        (binop.op == .BitAnd or binop.op == .BitOr or binop.op == .BitXor))
    {
        try self.emit("(");
        try genExprWrapped(self, binop.left.*);
        const op_str = switch (binop.op) {
            .BitAnd => " and ",
            .BitOr => " or ",
            .BitXor => " != ", // bool ^ bool = (a != b)
            else => unreachable,
        };
        try self.emit(op_str);
        try genExprWrapped(self, binop.right.*);
        try self.emit(")");
        return;
    }

    // If mixing usize and i64, cast to i64 for the operation
    const needs_cast = (left_is_usize and right_is_int) or (left_is_int and right_is_usize);

    // Handle mixed int/float multiplication - convert int to float
    // Note: unknown types (like self.field) that are multiplied with float constants
    // need runtime type dispatch
    const left_is_float = type_traits.isFloating(left_type);
    const right_is_float = type_traits.isFloating(right_type);
    const left_is_unknown = (left_type == .unknown);
    const right_is_unknown = (right_type == .unknown);
    if (binop.op == .Mult and ((left_is_int and right_is_float) or (left_is_float and right_is_int))) {
        try self.emit("(");
        if (left_is_int) {
            try self.emit("@as(f64, @floatFromInt(");
            try genExprWrapped(self, binop.left.*);
            try self.emit("))");
        } else {
            try genExprWrapped(self, binop.left.*);
        }
        try self.emit(" * ");
        if (right_is_int) {
            try self.emit("@as(f64, @floatFromInt(");
            try genExprWrapped(self, binop.right.*);
            try self.emit("))");
        } else {
            try genExprWrapped(self, binop.right.*);
        }
        try self.emit(")");
        return;
    }
    // Handle unknown type * float: use runtime conversion
    // Pattern: self.__num * 1.0 where __num could be int
    if (binop.op == .Mult and ((left_is_unknown and right_is_float) or (left_is_float and right_is_unknown))) {
        try self.emit("(runtime.toFloat(");
        try genExprWrapped(self, binop.left.*);
        try self.emit(") * runtime.toFloat(");
        try genExprWrapped(self, binop.right.*);
        try self.emit("))");
        return;
    }

    try self.emit("(");

    // Cast left operand if needed - bool or usize to i64
    if (left_is_bool) {
        try self.emit("@as(i64, @intFromBool(");
    } else if (left_is_usize and needs_cast) {
        try self.emit("@as(i64, @intCast(");
    }
    // Use genExprWrapped to add parens around comparisons, etc.
    try genExprWrapped(self, binop.left.*);
    if (left_is_bool) {
        try self.emit("))");
    } else if (left_is_usize and needs_cast) {
        try self.emit("))");
    }

    const op_str = switch (binop.op) {
        .Add => " + ",
        .Sub => " - ",
        .Mult => " * ",
        .BitAnd => " & ",
        .BitOr => " | ",
        .BitXor => " ^ ",
        .LShift => " << ",
        .RShift => " >> ",
        // Div, FloorDiv, Mod, Pow, MatMul are handled earlier with explicit returns
        else => unreachable,
    };
    try self.emit(op_str);

    // For shift operations, the RHS must be u6 for i64 (Zig requirement)
    const is_shift_op = binop.op == .LShift or binop.op == .RShift;
    if (is_shift_op) {
        // Cast shift amount to u6, handling both comptime and runtime values
        // Use @intCast with @mod to ensure value fits in u6 (0-63)
        try self.emit("@as(u6, @intCast(@mod(");
        try genExprWrapped(self, binop.right.*);
        try self.emit(", 64)))");
    } else if (right_is_bool) {
        // Cast right operand if needed - bool or usize to i64
        try self.emit("@as(i64, @intFromBool(");
        try genExprWrapped(self, binop.right.*);
        try self.emit("))");
    } else if (right_is_usize and needs_cast) {
        try self.emit("@as(i64, @intCast(");
        try genExprWrapped(self, binop.right.*);
        try self.emit("))");
    } else {
        // Use genExprWrapped to add parens around comparisons, etc.
        try genExprWrapped(self, binop.right.*);
    }

    try self.emit(")");
}

/// Generate unary operations (not, -, ~)
pub fn genUnaryOp(self: *NativeCodegen, unaryop: ast.Node.UnaryOp) CodegenError!void {
    switch (unaryop.op) {
        .Not => {
            // Python `not x` semantics depend on type:
            // - strings: empty string is falsy -> x.len == 0
            // - lists: empty list is falsy -> x.items.len == 0 (also .array type)
            // - tuples: empty tuple is falsy -> struct fields.len == 0
            // - int/float: 0 is falsy -> x == 0
            // - bool: just negate
            const operand_type = try self.inferExprScoped(unaryop.operand.*);
            if (string_traits.isString(operand_type)) {
                // not string -> string.len == 0
                try self.emit("(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(").len == 0");
            } else if (container_traits.isList(operand_type)) {
                // not list/array -> use runtime.toBool for proper truthiness
                // (handles both ArrayListUnmanaged and fixed arrays)
                try self.emit("!runtime.toBool(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(")");
            } else if (container_traits.isTuple(operand_type)) {
                // not tuple -> check if tuple is empty via comptime struct fields
                try self.emit("(@typeInfo(@TypeOf(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(")).@\"struct\".fields.len == 0)");
            } else if (shared.isEmptyTuple(unaryop.operand.*)) {
                // Empty tuple literal () - always true (not () == true)
                try self.emit("true");
            } else if (unaryop.operand.* == .tuple) {
                // Non-empty tuple literal - always false (not (1,2) == false)
                try self.emit("false");
            } else if (type_traits.isBoolean(operand_type) or type_traits.isIntegral(operand_type) or type_traits.isFloating(operand_type)) {
                // Simple bool/int/float - direct negation works
                try self.emit("!(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(")");
            } else {
                // Unknown/complex types - use runtime.toBool for proper truthiness
                try self.emit("!runtime.toBool(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(")");
            }
        },
        .USub => {
            // In Python, -bool converts to int first: -True = -1, -False = 0
            const operand_type = try self.inferExprScoped(unaryop.operand.*);

            // TWO-FLOW TYPE SYSTEM: Check if operand is a PyValue
            // If so, use PyValue.neg() method instead of Zig's negation operator
            // Use inferred type which handles: local vars, scoped vars, module constants, expressions
            // Only use .neg() for explicit PyValue types, not unknown (which may be i64)
            // Unknown types fall through to lines 1535-1544 with proper runtime dispatch
            if (operand_type == .pyvalue) {
                try self.emit("(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(").neg()");
                return;
            }

            if (type_traits.isBoolean(operand_type)) {
                try self.emit("-@as(i64, @intFromBool(");
                try genExpr(self, unaryop.operand.*);
                try self.emit("))");
            } else if (operand_type == .complex) {
                // Complex negation uses .neg() method
                try self.emit("(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(").neg()");
            } else if (operand_type == .bigint) {
                // BigInt negation: use runtime helper
                try self.emit("runtime.bigint_ops.neg(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(", __global_allocator)");
            } else if (type_traits.isUnknown(operand_type)) {
                // Unknown type (e.g., anytype parameter) - use comptime type check
                const alloc_name = "__global_allocator";
                var em = self.exprEmitter();
                try em.withBlock("unk", UnknownNegateCtx{
                    .cg = self,
                    .operand = unaryop.operand,
                    .alloc_name = alloc_name,
                }, UnknownNegateCtx.emit);
            } else {
                try self.emit("-(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(")");
            }
        },
        .UAdd => {
            // In Python, +bool converts to int: +True = 1, +False = 0
            const operand_type = try self.inferExprScoped(unaryop.operand.*);
            if (type_traits.isBoolean(operand_type)) {
                try self.emit("@as(i64, @intFromBool(");
                try genExpr(self, unaryop.operand.*);
                try self.emit("))");
            } else {
                // Non-bool: unary plus is a no-op in Python, just emit the operand
                // Note: In Zig, `+x` is not valid syntax, so we just emit `x`
                try genExpr(self, unaryop.operand.*);
            }
        },
        .Invert => {
            // Bitwise NOT: ~x in Zig
            // Cast to i64 to handle comptime_int literals
            // For booleans, need to convert to int first (Python: ~False = -1, ~True = -2)
            const operand_type = try self.inferExprScoped(unaryop.operand.*);

            // TWO-FLOW TYPE SYSTEM: Check if operand is a PyValue variable
            // If so, use PyValue.pyInvert() method instead of Zig's invert operator
            // Only use .pyInvert() for explicit PyValue types, not unknown (which may be i64)
            const is_pyvalue = if (unaryop.operand.* == .name) blk: {
                const name = unaryop.operand.name.id;
                const vt = self.type_inferrer.getScopedVar(name) orelse
                    self.type_inferrer.var_types.get(name);
                break :blk if (vt) |v| (v == .pyvalue) else false;
            } else false;
            if (is_pyvalue) {
                try self.emit("(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(").pyInvert()");
                return;
            }

            // Check if operand is a boolean constant or name (True/False)
            const is_bool = blk: {
                if (type_traits.isBoolean(operand_type)) break :blk true;
                // Check for True/False names which may not be typed as bool
                if (unaryop.operand.* == .name) {
                    const name = unaryop.operand.name.id;
                    if (std.mem.eql(u8, name, "True") or std.mem.eql(u8, name, "False")) {
                        break :blk true;
                    }
                }
                // Check for bool constants
                if (unaryop.operand.* == .constant) {
                    if (unaryop.operand.constant.value == .bool) {
                        break :blk true;
                    }
                }
                break :blk false;
            };

            if (is_bool) {
                // ~False = ~0 = -1, ~True = ~1 = -2
                try self.emit("~@as(i64, @intFromBool(");
                try genExpr(self, unaryop.operand.*);
                try self.emit("))");
            } else if (operand_type == .bigint) {
                // BigInt bitwise complement: ~n = -(n+1)
                // Implemented as: negate (n+1) -> -(n+1) = -n-1 = ~n
                const alloc_name = "__global_allocator";
                var em = self.exprEmitter();
                try em.withBlock("inv", BigIntInvertCtx{
                    .cg = self,
                    .operand = unaryop.operand,
                    .alloc_name = alloc_name,
                }, BigIntInvertCtx.emit);
            } else {
                try self.emit("~@as(i64, ");
                try genExpr(self, unaryop.operand.*);
                try self.emit(")");
            }
        },
    }
}
