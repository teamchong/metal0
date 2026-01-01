/// Power, division, and special binary operations
/// Handles: **, /, @, floor division, modulo, shifts, dict merge
///
/// MIGRATION STATUS: Partially migrated to ZigBuilder pattern
/// - Uses captureExpr() to bridge AST expressions to ZigValue
/// - Uses builder.write() for direct output where possible
/// - withParensCtx callbacks still use emit() for compatibility
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;
const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
const operator_traits = @import("../../../../analysis/traits/operator_traits.zig");
const string_traits = @import("../../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../../analysis/traits/container_traits.zig");
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const collection_ops = @import("collection_ops.zig");
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;
const ZigBuilder = builder_mod.ZigBuilder;

// ============================================
// Arithmetic helper functions - builder pattern (auto-closing)
// ============================================

/// DEPRECATED: Use emitBinaryRuntimeCall instead
/// Kept for backwards compatibility during migration
fn emitBinaryCall(self: *NativeCodegen, func_prefix: []const u8, left: ast.Node, right: ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    try b.emitRaw(func_prefix);
    const left_val = try self.exprToValue(left);
    try self.emitZigValue(left_val);
    try b.emitRaw(", ");
    const right_val = try self.exprToValue(right);
    try self.emitZigValue(right_val);
    try b.emitRaw(")");
}

/// Emit expression with bool-to-i64 coercion if needed: @as(i64, @intFromBool(expr))
/// Uses builder pattern for auto-closing brackets
fn emitExprBoolCoerced(self: *NativeCodegen, expr: ast.Node, is_bool: bool) CodegenError!void {
    const b = try self.getBuilder();
    if (is_bool) {
        try b.emitRaw("@as(i64, @intFromBool(");
        const val = try self.exprToValue(expr);
        try self.emitZigValue(val);
        try b.emitRaw("))");
    } else {
        const val = try self.exprToValue(expr);
        try self.emitZigValue(val);
    }
}

/// Emit two-argument runtime call: func(left, right) or func(__global_allocator, left, right)
/// Uses builder.emitCallExpr for auto-closing brackets
fn emitBinaryRuntimeCall(self: *NativeCodegen, func: []const u8, left: ast.Node, right: ast.Node, needs_allocator: bool) CodegenError!void {
    const b = try self.getBuilder();
    const left_val = try self.exprToValue(left);
    const right_val = try self.exprToValue(right);

    try b.emitRaw(func);
    try b.emitRaw("(");
    if (needs_allocator) {
        try b.emitRaw("__global_allocator, ");
    }
    try self.emitZigValue(left_val);
    try b.emitRaw(", ");
    try self.emitZigValue(right_val);
    try b.emitRaw(")");
}

/// Generate power operation using builder pattern
/// Python semantics: negative base with non-integer exponent returns complex
pub fn genPowOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    const b = try self.getBuilder();
    const left_is_bool = type_traits.isBoolean(left_type);
    const right_is_bool = type_traits.isBoolean(right_type);
    const left_is_int = type_traits.isIntegral(left_type) or left_is_bool;
    const right_is_int = type_traits.isIntegral(right_type) or right_is_bool;
    const right_is_float = type_traits.isFloating(right_type);

    // Check if exponent is a constant integer
    const is_constant_int_exp = binop.right.* == .constant and binop.right.constant.value == .int;

    // Case 1: Large constant integer exponent - use UnifiedInt for arbitrary precision
    if (is_constant_int_exp) {
        const exp = binop.right.constant.value.int;
        if (exp >= 20) {
            try b.emitRaw("runtime.unified_int_ops.pow(runtime.unified_int_ops.fromI64(");
            try emitExprBoolCoerced(self, binop.left.*, left_is_bool);
            try b.emitRaw("), @as(u32, @intCast(");
            try emitExprBoolCoerced(self, binop.right.*, right_is_bool);
            try b.emitRaw(")), __global_allocator)");
            return;
        }

        // Case 2: Small constant positive integer exponent - use i64 fast path
        try b.emitRaw("std.math.pow(i64, ");
        try emitExprBoolCoerced(self, binop.left.*, left_is_bool);
        try b.emitRaw(", ");
        try emitExprBoolCoerced(self, binop.right.*, right_is_bool);
        try b.emitRaw(")");
        return;
    }

    // Case 3: Float exponent OR runtime exponent - could produce complex
    const needs_complex_support = blk: {
        if (!right_is_float and right_is_int) break :blk false;
        if (binop.right.* == .constant and binop.right.constant.value == .float) {
            const fexp = binop.right.constant.value.float;
            if (fexp == @trunc(fexp)) break :blk false;
        }
        if (binop.right.* == .unaryop and binop.right.unaryop.op == .USub) {
            if (binop.right.unaryop.operand.* == .constant and
                binop.right.unaryop.operand.constant.value == .float)
            {
                const fexp = binop.right.unaryop.operand.constant.value.float;
                if (fexp == @trunc(fexp)) break :blk false;
            }
        }
        break :blk true;
    };

    if (needs_complex_support) {
        try b.emitRaw("(try runtime.builtins.pyPow(");
        // Convert base to f64
        if (left_is_int) {
            try b.emitRaw("@as(f64, @floatFromInt(");
            try emitExprBoolCoerced(self, binop.left.*, left_is_bool);
            try b.emitRaw("))");
        } else {
            try b.emitRaw("@as(f64, ");
            const left_val = try self.exprToValue(binop.left.*);
            try self.emitZigValue(left_val);
            try b.emitRaw(")");
        }
        try b.emitRaw(", ");
        // Convert exponent to f64
        if (right_is_int) {
            try b.emitRaw("@as(f64, @floatFromInt(");
            try emitExprBoolCoerced(self, binop.right.*, right_is_bool);
            try b.emitRaw("))");
        } else {
            try b.emitRaw("@as(f64, ");
            const right_val = try self.exprToValue(binop.right.*);
            try self.emitZigValue(right_val);
            try b.emitRaw(")");
        }
        try b.emitRaw("))");
        return;
    }

    // Case 3b: Float exponent that's a whole number - use std.math.pow(f64)
    if (right_is_float) {
        try b.emitRaw("std.math.pow(f64, ");
        const left_val = try self.exprToValue(binop.left.*);
        try self.emitZigValue(left_val);
        try b.emitRaw(", ");
        const right_val = try self.exprToValue(binop.right.*);
        try self.emitZigValue(right_val);
        try b.emitRaw(")");
        return;
    }

    // Case 4: Runtime integer exponent - use f64 for safety
    try b.emitRaw("std.math.pow(f64, @as(f64, @floatFromInt(");
    try emitExprBoolCoerced(self, binop.left.*, left_is_bool);
    try b.emitRaw(")), @as(f64, @floatFromInt(");
    try emitExprBoolCoerced(self, binop.right.*, right_is_bool);
    try b.emitRaw(")))");
}

/// Generate division operation using builder pattern
pub fn genDivOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    const b = try self.getBuilder();

    // Check if this is Path / string (path join)
    if (left_type == .path) {
        const left_val = try self.exprToValue(binop.left.*);
        try self.emitZigValue(left_val);
        try b.emitRaw(".join(");
        const right_val = try self.exprToValue(binop.right.*);
        try self.emitZigValue(right_val);
        try b.emitRaw(")");
        return;
    }

    // For C extension values (PyObject), use PyValue's div method
    // This handles Path objects (NUMPY_ROOT / '_core'), numpy arrays, etc.
    // The __truediv__ method will be dispatched at runtime
    if (left_type == .pyobject or left_type == .unknown) {
        try b.emitRaw("(runtime.PyValue.from(");
        const left_val = try self.exprToValue(binop.left.*);
        try self.emitZigValue(left_val);
        try b.emitRaw(")).div(runtime.PyValue.from(");
        const right_val = try self.exprToValue(binop.right.*);
        try self.emitZigValue(right_val);
        try b.emitRaw("))");
        return;
    }

    const left_is_bool = type_traits.isBoolean(left_type);
    const right_is_bool = type_traits.isBoolean(right_type);

    // At module level or inside defer, we can't use 'try'
    if (self.indent_level == 0 or self.inside_defer) {
        try b.emitRaw("(@as(f64, @floatFromInt(");
        try emitExprBoolCoerced(self, binop.left.*, left_is_bool);
        try b.emitRaw(")) / @as(f64, @floatFromInt(");
        try emitExprBoolCoerced(self, binop.right.*, right_is_bool);
        try b.emitRaw(")))");
    } else {
        try b.emitRaw("try runtime.divideFloat(");
        try emitExprBoolCoerced(self, binop.left.*, left_is_bool);
        try b.emitRaw(", ");
        try emitExprBoolCoerced(self, binop.right.*, right_is_bool);
        try b.emitRaw(")");
    }
}

/// Generate matrix multiplication operation using builder pattern
pub fn genMatMulOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    const b = try self.getBuilder();
    const left_val = try self.exprToValue(binop.left.*);
    const right_val = try self.exprToValue(binop.right.*);

    if (type_traits.isClassInstance(left_type) or type_traits.isUnknown(left_type)) {
        try b.emitRaw("try ");
        try self.emitZigValue(left_val);
        try b.emitRaw(".__matmul__(__global_allocator, ");
        try self.emitZigValue(right_val);
        try b.emitRaw(")");
    } else if (type_traits.isClassInstance(right_type) or type_traits.isUnknown(right_type)) {
        try b.emitRaw("try ");
        try self.emitZigValue(right_val);
        try b.emitRaw(".__rmatmul__(__global_allocator, ");
        try self.emitZigValue(left_val);
        try b.emitRaw(")");
    } else {
        try b.emitRaw("try ");
        try self.emitZigValue(left_val);
        try b.emitRaw(".__matmul__(__global_allocator, ");
        try self.emitZigValue(right_val);
        try b.emitRaw(")");
    }
}

/// Generate floor division operation using builder pattern
pub fn genFloorDivOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    const b = try self.getBuilder();
    const semantics = operator_traits.getFloorDivSemantics(left_type, right_type);
    switch (semantics) {
        .runtime_dispatch => {
            try emitBinaryRuntimeCall(self, "runtime.pyFloorDiv", binop.left.*, binop.right.*, true);
        },
        .python_floored => {
            try b.emitRaw("@floor(");
            const left_val = try self.exprToValue(binop.left.*);
            try self.emitZigValue(left_val);
            try b.emitRaw(" / ");
            const right_val = try self.exprToValue(binop.right.*);
            try self.emitZigValue(right_val);
            try b.emitRaw(")");
        },
        .zig_native => {
            const left_is_bool = type_traits.isBoolean(left_type);
            const right_is_bool = type_traits.isBoolean(right_type);
            try b.emitRaw("@divFloor(");
            try emitExprBoolCoerced(self, binop.left.*, left_is_bool);
            try b.emitRaw(", ");
            try emitExprBoolCoerced(self, binop.right.*, right_is_bool);
            try b.emitRaw(")");
        },
    }
}

/// Generate modulo operation (or string formatting)
/// Uses builder pattern for type-aware emission
pub fn genModOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    // String formatting: if left operand is string or bytes, use formatting not modulo
    if (string_traits.isString(left_type) or string_traits.isBytes(left_type) or
        (binop.left.* == .constant and binop.left.constant.value == .string))
    {
        const genStringFormat = @import("./formatting.zig").genStringFormat;
        try genStringFormat(self, binop);
        return;
    }

    const b = try self.getBuilder();

    // CRITICAL: If left operand is an anytype parameter (closure/nested function param),
    // we MUST use runtime dispatch because it could be a string (formatting) or number (modulo).
    // The type at call-site might be string, but inside the closure we only know it's anytype.
    const left_is_anytype = if (binop.left.* == .name) self.anytype_params.contains(binop.left.name.id) else false;
    if (left_is_anytype) {
        try emitBinaryRuntimeCall(self, "runtime.pyMod", binop.left.*, binop.right.*, true);
        return;
    }

    // For unknown types, use runtime dispatch which handles both string formatting and modulo
    // This is critical for function parameters without type annotations
    if (type_traits.isUnknown(left_type) or type_traits.isUnknown(right_type)) {
        try emitBinaryRuntimeCall(self, "runtime.pyMod", binop.left.*, binop.right.*, true);
        return;
    }
    const semantics = operator_traits.getModuloSemantics(left_type, right_type);
    switch (semantics) {
        .runtime_dispatch => {
            try emitBinaryRuntimeCall(self, "runtime.pyMod", binop.left.*, binop.right.*, true);
        },
        .python_floored => {
            try emitBinaryRuntimeCall(self, "runtime.pyFloatMod", binop.left.*, binop.right.*, false);
        },
        .zig_native => {
            // Python uses floored modulo, not Zig's truncated @mod
            // -10 % 3 = 2 in Python (floored), not -1 (truncated)
            const left_is_bool = type_traits.isBoolean(left_type);
            const right_is_bool = type_traits.isBoolean(right_type);
            try b.emitRaw("runtime.pyFlooredModInt(");
            try emitExprBoolCoerced(self, binop.left.*, left_is_bool);
            try b.emitRaw(", ");
            try emitExprBoolCoerced(self, binop.right.*, right_is_bool);
            try b.emitRaw(")");
        },
    }
}

/// Generate large left shift using UnifiedInt
pub fn genLargeShiftOp(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    const alloc_name = "__global_allocator";

    // Capture operands as ZigValues
    const left_operand = try self.captureExpr(binop.left.*);
    const right_operand = try self.captureExpr(binop.right.*);

    const b = try self.getBuilder();
    try b.emitRaw("runtime.unified_int_ops.shl(runtime.unified_int_ops.fromI64(");
    try self.emitZigValue(left_operand);
    try b.emitRaw("), @as(u32, @intCast(");
    try self.emitZigValue(right_operand);
    try b.emitRaw(")), ");
    try b.emitRaw(alloc_name);
    try b.emitRaw(")");
    try self.flushBuilder();
}

/// Generate dict merge operation (Python 3.9+)
pub fn genDictMerge(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();
    const b = try self.getBuilder();
    try b.writeFmt("(dmerge_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try b.emitRaw("var __merged = @TypeOf(");
    try self.flushBuilder();
    try collection_ops.genExprWrapped(self, binop.left.*);
    const b2 = try self.getBuilder();
    try b2.write("){};\n");

    try self.emitIndent();
    try b2.write("var __left_iter = ");
    try self.flushBuilder();
    try collection_ops.genExprWrapped(self, binop.left.*);
    const b3 = try self.getBuilder();
    try b3.write(".iterator();\n");
    try self.emitIndent();
    try b3.write("while (__left_iter.next()) |entry| {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try b3.write("try __merged.put(entry.key_ptr.*, entry.value_ptr.*);\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try b3.write("}\n");

    try self.emitIndent();
    try b3.write("var __right_iter = ");
    try self.flushBuilder();
    try collection_ops.genExprWrapped(self, binop.right.*);
    const b4 = try self.getBuilder();
    try b4.write(".iterator();\n");
    try self.emitIndent();
    try b4.write("while (__right_iter.next()) |entry| {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try b4.write("try __merged.put(entry.key_ptr.*, entry.value_ptr.*);\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try b4.write("}\n");

    try self.emitIndent();
    try b4.writeFmt("break :dmerge_{d} __merged;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try b4.write("})");
    try self.flushBuilder();
}

/// Generate simple binary operations (+, -, *, &, |, ^, <<, >>)
/// Uses builder pattern for type-aware emission
pub fn genSimpleBinOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    const b = try self.getBuilder();
    const left_is_usize = (left_type == .usize);
    const left_is_int = type_traits.isIntegral(left_type);
    const left_is_bool = type_traits.isBoolean(left_type);
    const right_is_usize = (right_type == .usize);
    const right_is_int = type_traits.isIntegral(right_type);
    const right_is_bool = type_traits.isBoolean(right_type);

    // Python: bool & bool = bool, bool | bool = bool, bool ^ bool = bool
    if (left_is_bool and right_is_bool and
        (binop.op == .BitAnd or binop.op == .BitOr or binop.op == .BitXor))
    {
        const op_str = switch (binop.op) {
            .BitAnd => " and ",
            .BitOr => " or ",
            .BitXor => " != ",
            else => unreachable,
        };
        try b.emitRaw("(");
        const left_val = try self.exprToValue(binop.left.*);
        try self.emitZigValue(left_val);
        try b.emitRaw(op_str);
        const right_val = try self.exprToValue(binop.right.*);
        try self.emitZigValue(right_val);
        try b.emitRaw(")");
        return;
    }

    const needs_cast = (left_is_usize and right_is_int) or (left_is_int and right_is_usize);

    // Handle mixed int/float multiplication
    const left_is_float = type_traits.isFloating(left_type);
    const right_is_float = type_traits.isFloating(right_type);
    const left_is_unknown = (left_type == .unknown);
    const right_is_unknown = (right_type == .unknown);
    if (binop.op == .Mult and ((left_is_int and right_is_float) or (left_is_float and right_is_int))) {
        try b.emitRaw("(");
        if (left_is_int) {
            try b.emitRaw("@as(f64, @floatFromInt(");
            const left_val = try self.exprToValue(binop.left.*);
            try self.emitZigValue(left_val);
            try b.emitRaw("))");
        } else {
            const left_val = try self.exprToValue(binop.left.*);
            try self.emitZigValue(left_val);
        }
        try b.emitRaw(" * ");
        if (right_is_int) {
            try b.emitRaw("@as(f64, @floatFromInt(");
            const right_val = try self.exprToValue(binop.right.*);
            try self.emitZigValue(right_val);
            try b.emitRaw("))");
        } else {
            const right_val = try self.exprToValue(binop.right.*);
            try self.emitZigValue(right_val);
        }
        try b.emitRaw(")");
        return;
    }

    // Handle unknown type * float
    if (binop.op == .Mult and ((left_is_unknown and right_is_float) or (left_is_float and right_is_unknown))) {
        try b.emitRaw("(runtime.toFloat(");
        const left_val = try self.exprToValue(binop.left.*);
        try self.emitZigValue(left_val);
        try b.emitRaw(") * runtime.toFloat(");
        const right_val = try self.exprToValue(binop.right.*);
        try self.emitZigValue(right_val);
        try b.emitRaw("))");
        return;
    }

    // Main case: wrap entire binop in parens
    const op_str = switch (binop.op) {
        .Add => " + ",
        .Sub => " - ",
        .Mult => " * ",
        .BitAnd => " & ",
        .BitOr => " | ",
        .BitXor => " ^ ",
        .LShift => " << ",
        .RShift => " >> ",
        else => unreachable,
    };
    const is_shift_op = binop.op == .LShift or binop.op == .RShift;

    try b.emitRaw("(");

    // Emit left operand with appropriate casting
    if (left_is_bool) {
        try b.emitRaw("@as(i64, @intFromBool(");
        const left_val = try self.exprToValue(binop.left.*);
        try self.emitZigValue(left_val);
        try b.emitRaw("))");
    } else if (left_is_usize and needs_cast) {
        try b.emitRaw("@as(i64, @intCast(");
        const left_val = try self.exprToValue(binop.left.*);
        try self.emitZigValue(left_val);
        try b.emitRaw("))");
    } else {
        const left_val = try self.exprToValue(binop.left.*);
        try self.emitZigValue(left_val);
    }

    try b.emitRaw(op_str);

    // Emit right operand with appropriate casting
    if (is_shift_op) {
        // For shift operations, the RHS must be u6 for i64
        try b.emitRaw("@as(u6, @intCast(@mod(");
        const right_val = try self.exprToValue(binop.right.*);
        try self.emitZigValue(right_val);
        try b.emitRaw(", 64)))");
    } else if (right_is_bool) {
        try b.emitRaw("@as(i64, @intFromBool(");
        const right_val = try self.exprToValue(binop.right.*);
        try self.emitZigValue(right_val);
        try b.emitRaw("))");
    } else if (right_is_usize and needs_cast) {
        try b.emitRaw("@as(i64, @intCast(");
        const right_val = try self.exprToValue(binop.right.*);
        try self.emitZigValue(right_val);
        try b.emitRaw("))");
    } else {
        const right_val = try self.exprToValue(binop.right.*);
        try self.emitZigValue(right_val);
    }

    try b.emitRaw(")");
}
