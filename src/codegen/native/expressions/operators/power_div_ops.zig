/// Power, division, and special binary operations
/// Handles: **, /, @, floor division, modulo, shifts, dict merge
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
const operator_traits = @import("../../../../analysis/traits/operator_traits.zig");
const string_traits = @import("../../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../../analysis/traits/container_traits.zig");
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const collection_ops = @import("collection_ops.zig");
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;

/// Generate power operation
pub fn genPowOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    const left_is_bool = type_traits.isBoolean(left_type);
    const right_is_bool = type_traits.isBoolean(right_type);

    // Check if exponent is large enough to need UnifiedInt
    if (binop.right.* == .constant and binop.right.constant.value == .int) {
        const exp = binop.right.constant.value.int;
        if (exp >= 20) {
            const alloc_name = "__global_allocator";
            try self.emit("runtime.unified_int_ops.pow(runtime.unified_int_ops.fromI64(");
            if (left_is_bool) {
                try self.emit("@as(i64, @intFromBool(");
                try genExpr(self, binop.left.*);
                try self.emit("))");
            } else {
                try genExpr(self, binop.left.*);
            }
            try self.emit("), @as(u32, @intCast(");
            if (right_is_bool) {
                try self.emit("@as(i64, @intFromBool(");
                try genExpr(self, binop.right.*);
                try self.emit("))");
            } else {
                try genExpr(self, binop.right.*);
            }
            try self.emit(")), ");
            try self.emit(alloc_name);
            try self.emit(")");
            return;
        }
        // Small constant positive exponent - use i64
        try self.emit("std.math.pow(i64, ");
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
        return;
    }
    // Runtime exponent - use f64 for safety
    try self.emit("std.math.pow(f64, @as(f64, @floatFromInt(");
    if (left_is_bool) {
        try self.emit("@as(i64, @intFromBool(");
        try genExpr(self, binop.left.*);
        try self.emit("))");
    } else {
        try genExpr(self, binop.left.*);
    }
    try self.emit(")), @as(f64, @floatFromInt(");
    if (right_is_bool) {
        try self.emit("@as(i64, @intFromBool(");
        try genExpr(self, binop.right.*);
        try self.emit("))");
    } else {
        try genExpr(self, binop.right.*);
    }
    try self.emit(")))");
}

/// Generate division operation
pub fn genDivOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    // Check if this is Path / string (path join)
    if (left_type == .path) {
        try genExpr(self, binop.left.*);
        try self.emit(".join(");
        try genExpr(self, binop.right.*);
        try self.emit(")");
        return;
    }

    const left_is_bool = type_traits.isBoolean(left_type);
    const right_is_bool = type_traits.isBoolean(right_type);

    // At module level or inside defer, we can't use 'try'
    if (self.indent_level == 0 or self.inside_defer) {
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
}

/// Generate matrix multiplication operation
pub fn genMatMulOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    if (type_traits.isClassInstance(left_type) or type_traits.isUnknown(left_type)) {
        try self.emit("try ");
        try genExpr(self, binop.left.*);
        try self.emit(".__matmul__(__global_allocator, ");
        try genExpr(self, binop.right.*);
        try self.emit(")");
    } else if (type_traits.isClassInstance(right_type) or type_traits.isUnknown(right_type)) {
        try self.emit("try ");
        try genExpr(self, binop.right.*);
        try self.emit(".__rmatmul__(__global_allocator, ");
        try genExpr(self, binop.left.*);
        try self.emit(")");
    } else {
        try self.emit("try ");
        try genExpr(self, binop.left.*);
        try self.emit(".__matmul__(__global_allocator, ");
        try genExpr(self, binop.right.*);
        try self.emit(")");
    }
}

/// Generate floor division operation
pub fn genFloorDivOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    const semantics = operator_traits.getFloorDivSemantics(left_type, right_type);
    switch (semantics) {
        .runtime_dispatch => {
            try self.emit("runtime.pyFloorDiv(__global_allocator, ");
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
        },
        .python_floored => {
            try self.emit("@floor(");
            try genExpr(self, binop.left.*);
            try self.emit(" / ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
        },
        .zig_native => {
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
}

/// Generate modulo operation (or string formatting)
pub fn genModOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    if (string_traits.isString(left_type) or (binop.left.* == .constant and binop.left.constant.value == .string)) {
        const genStringFormat = @import("./formatting.zig").genStringFormat;
        try genStringFormat(self, binop);
        return;
    }
    const semantics = operator_traits.getModuloSemantics(left_type, right_type);
    switch (semantics) {
        .runtime_dispatch => {
            try self.emit("runtime.pyMod(__global_allocator, ");
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
        },
        .python_floored => {
            try self.emit("runtime.pyFloatMod(");
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
        },
        .zig_native => {
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
}

/// Generate large left shift using UnifiedInt
pub fn genLargeShiftOp(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    const alloc_name = "__global_allocator";

    // Capture operands as ZigValues
    const left_operand = try self.captureExpr(binop.left.*);
    const right_operand = try self.captureExpr(binop.right.*);

    try self.emit("runtime.unified_int_ops.shl(runtime.unified_int_ops.fromI64(");
    try self.emitZigValue(left_operand);
    try self.emit("), @as(u32, @intCast(");
    try self.emitZigValue(right_operand);
    try self.emit(")), ");
    try self.emit(alloc_name);
    try self.emit(")");
}

/// Generate dict merge operation (Python 3.9+)
pub fn genDictMerge(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();
    try self.emitFmt("(dmerge_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try self.emit("var __merged = @TypeOf(");
    try collection_ops.genExprWrapped(self, binop.left.*);
    try self.emit("){};\n");

    try self.emitIndent();
    try self.emit("var __left_iter = ");
    try collection_ops.genExprWrapped(self, binop.left.*);
    try self.emit(".iterator();\n");
    try self.emitIndent();
    try self.emit("while (__left_iter.next()) |entry| {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("try __merged.put(entry.key_ptr.*, entry.value_ptr.*);\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.emit("var __right_iter = ");
    try collection_ops.genExprWrapped(self, binop.right.*);
    try self.emit(".iterator();\n");
    try self.emitIndent();
    try self.emit("while (__right_iter.next()) |entry| {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try self.emit("try __merged.put(entry.key_ptr.*, entry.value_ptr.*);\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dmerge_{d} __merged;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("})");
}

/// Generate simple binary operations (+, -, *, &, |, ^, <<, >>)
pub fn genSimpleBinOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
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
        try self.emit("(");
        try collection_ops.genExprWrapped(self, binop.left.*);
        const op_str = switch (binop.op) {
            .BitAnd => " and ",
            .BitOr => " or ",
            .BitXor => " != ",
            else => unreachable,
        };
        try self.emit(op_str);
        try collection_ops.genExprWrapped(self, binop.right.*);
        try self.emit(")");
        return;
    }

    const needs_cast = (left_is_usize and right_is_int) or (left_is_int and right_is_usize);

    // Handle mixed int/float multiplication
    const left_is_float = type_traits.isFloating(left_type);
    const right_is_float = type_traits.isFloating(right_type);
    const left_is_unknown = (left_type == .unknown);
    const right_is_unknown = (right_type == .unknown);
    if (binop.op == .Mult and ((left_is_int and right_is_float) or (left_is_float and right_is_int))) {
        try self.emit("(");
        if (left_is_int) {
            try self.emit("@as(f64, @floatFromInt(");
            try collection_ops.genExprWrapped(self, binop.left.*);
            try self.emit("))");
        } else {
            try collection_ops.genExprWrapped(self, binop.left.*);
        }
        try self.emit(" * ");
        if (right_is_int) {
            try self.emit("@as(f64, @floatFromInt(");
            try collection_ops.genExprWrapped(self, binop.right.*);
            try self.emit("))");
        } else {
            try collection_ops.genExprWrapped(self, binop.right.*);
        }
        try self.emit(")");
        return;
    }
    // Handle unknown type * float
    if (binop.op == .Mult and ((left_is_unknown and right_is_float) or (left_is_float and right_is_unknown))) {
        try self.emit("(runtime.toFloat(");
        try collection_ops.genExprWrapped(self, binop.left.*);
        try self.emit(") * runtime.toFloat(");
        try collection_ops.genExprWrapped(self, binop.right.*);
        try self.emit("))");
        return;
    }

    try self.emit("(");

    // Cast left operand if needed
    if (left_is_bool) {
        try self.emit("@as(i64, @intFromBool(");
    } else if (left_is_usize and needs_cast) {
        try self.emit("@as(i64, @intCast(");
    }
    try collection_ops.genExprWrapped(self, binop.left.*);
    if (left_is_bool or (left_is_usize and needs_cast)) {
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
        else => unreachable,
    };
    try self.emit(op_str);

    // For shift operations, the RHS must be u6 for i64
    const is_shift_op = binop.op == .LShift or binop.op == .RShift;
    if (is_shift_op) {
        try self.emit("@as(u6, @intCast(@mod(");
        try collection_ops.genExprWrapped(self, binop.right.*);
        try self.emit(", 64)))");
    } else if (right_is_bool) {
        try self.emit("@as(i64, @intFromBool(");
        try collection_ops.genExprWrapped(self, binop.right.*);
        try self.emit("))");
    } else if (right_is_usize and needs_cast) {
        try self.emit("@as(i64, @intCast(");
        try collection_ops.genExprWrapped(self, binop.right.*);
        try self.emit("))");
    } else {
        try collection_ops.genExprWrapped(self, binop.right.*);
    }

    try self.emit(")");
}
