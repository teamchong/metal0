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

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// ============================================
// Arithmetic helper functions - auto-closing patterns
// ============================================

/// Emit expression with bool-to-i64 coercion if needed: @as(i64, @intFromBool(expr))
fn emitExprBoolCoerced(self: *NativeCodegen, expr: ast.Node, is_bool: bool) CodegenError!void {
    if (is_bool) {
        try emitConst(self, "@as(i64, @intFromBool(");
        try genExpr(self, expr);
        try emitConst(self, "))");
    } else {
        try genExpr(self, expr);
    }
}

/// Emit two-argument function call: func(expr1, expr2)
fn emitBinaryCall(self: *NativeCodegen, func: []const u8, left: ast.Node, right: ast.Node) CodegenError!void {
    try emitConst(self, func);
    try emitConst(self, "(");
    try genExpr(self, left);
    try emitConst(self, ", ");
    try genExpr(self, right);
    try emitConst(self, ")");
}

/// Generate power operation
pub fn genPowOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    const left_is_bool = type_traits.isBoolean(left_type);
    const right_is_bool = type_traits.isBoolean(right_type);

    // Check if exponent is large enough to need UnifiedInt
    if (binop.right.* == .constant and binop.right.constant.value == .int) {
        const exp = binop.right.constant.value.int;
        if (exp >= 20) {
            try emitConst(self, "runtime.unified_int_ops.pow(runtime.unified_int_ops.fromI64(");
            try emitExprBoolCoerced(self, binop.left.*, left_is_bool);
            try emitConst(self, "), @as(u32, @intCast(");
            try emitExprBoolCoerced(self, binop.right.*, right_is_bool);
            try emitConst(self, ")), __global_allocator)");
            return;
        }
        // Small constant positive exponent - use i64
        try emitConst(self, "std.math.pow(i64, ");
        try emitExprBoolCoerced(self, binop.left.*, left_is_bool);
        try emitConst(self, ", ");
        try emitExprBoolCoerced(self, binop.right.*, right_is_bool);
        try emitConst(self, ")");
        return;
    }
    // Runtime exponent - use f64 for safety
    try emitConst(self, "std.math.pow(f64, @as(f64, @floatFromInt(");
    try emitExprBoolCoerced(self, binop.left.*, left_is_bool);
    try emitConst(self, ")), @as(f64, @floatFromInt(");
    try emitExprBoolCoerced(self, binop.right.*, right_is_bool);
    try emitConst(self, ")))");
}

/// Generate division operation
pub fn genDivOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    // Check if this is Path / string (path join)
    if (left_type == .path) {
        try genExpr(self, binop.left.*);
        try emitConst(self, ".join(");
        try genExpr(self, binop.right.*);
        try emitConst(self, ")");
        return;
    }

    const left_is_bool = type_traits.isBoolean(left_type);
    const right_is_bool = type_traits.isBoolean(right_type);

    // At module level or inside defer, we can't use 'try'
    if (self.indent_level == 0 or self.inside_defer) {
        try emitConst(self, "(@as(f64, @floatFromInt(");
        try emitExprBoolCoerced(self, binop.left.*, left_is_bool);
        try emitConst(self, ")) / @as(f64, @floatFromInt(");
        try emitExprBoolCoerced(self, binop.right.*, right_is_bool);
        try emitConst(self, ")))");
    } else {
        try emitConst(self, "try runtime.divideFloat(");
        try emitExprBoolCoerced(self, binop.left.*, left_is_bool);
        try emitConst(self, ", ");
        try emitExprBoolCoerced(self, binop.right.*, right_is_bool);
        try emitConst(self, ")");
    }
}

/// Generate matrix multiplication operation
pub fn genMatMulOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    if (type_traits.isClassInstance(left_type) or type_traits.isUnknown(left_type)) {
        try emitConst(self, "try ");
        try genExpr(self, binop.left.*);
        try emitConst(self, ".__matmul__(__global_allocator, ");
        try genExpr(self, binop.right.*);
        try emitConst(self, ")");
    } else if (type_traits.isClassInstance(right_type) or type_traits.isUnknown(right_type)) {
        try emitConst(self, "try ");
        try genExpr(self, binop.right.*);
        try emitConst(self, ".__rmatmul__(__global_allocator, ");
        try genExpr(self, binop.left.*);
        try emitConst(self, ")");
    } else {
        try emitConst(self, "try ");
        try genExpr(self, binop.left.*);
        try emitConst(self, ".__matmul__(__global_allocator, ");
        try genExpr(self, binop.right.*);
        try emitConst(self, ")");
    }
}

/// Generate floor division operation
pub fn genFloorDivOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    const semantics = operator_traits.getFloorDivSemantics(left_type, right_type);
    switch (semantics) {
        .runtime_dispatch => {
            try emitBinaryCall(self, "runtime.pyFloorDiv(__global_allocator, ", binop.left.*, binop.right.*);
        },
        .python_floored => {
            try emitConst(self, "@floor(");
            try genExpr(self, binop.left.*);
            try emitConst(self, " / ");
            try genExpr(self, binop.right.*);
            try emitConst(self, ")");
        },
        .zig_native => {
            const left_is_bool = type_traits.isBoolean(left_type);
            const right_is_bool = type_traits.isBoolean(right_type);
            try emitConst(self, "@divFloor(");
            try emitExprBoolCoerced(self, binop.left.*, left_is_bool);
            try emitConst(self, ", ");
            try emitExprBoolCoerced(self, binop.right.*, right_is_bool);
            try emitConst(self, ")");
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
            try emitBinaryCall(self, "runtime.pyMod(__global_allocator, ", binop.left.*, binop.right.*);
        },
        .python_floored => {
            try emitBinaryCall(self, "runtime.pyFloatMod(", binop.left.*, binop.right.*);
        },
        .zig_native => {
            const left_is_bool = type_traits.isBoolean(left_type);
            const right_is_bool = type_traits.isBoolean(right_type);
            try emitConst(self, "@mod(");
            try emitExprBoolCoerced(self, binop.left.*, left_is_bool);
            try emitConst(self, ", ");
            try emitExprBoolCoerced(self, binop.right.*, right_is_bool);
            try emitConst(self, ")");
        },
    }
}

/// Generate large left shift using UnifiedInt
pub fn genLargeShiftOp(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    const alloc_name = "__global_allocator";

    // Capture operands as ZigValues
    const left_operand = try self.captureExpr(binop.left.*);
    const right_operand = try self.captureExpr(binop.right.*);

    try emitConst(self, "runtime.unified_int_ops.shl(runtime.unified_int_ops.fromI64(");
    try self.emitZigValue(left_operand);
    try emitConst(self, "), @as(u32, @intCast(");
    try self.emitZigValue(right_operand);
    try emitConst(self, ")), ");
    try emitConst(self, alloc_name);
    try emitConst(self, ")");
}

/// Generate dict merge operation (Python 3.9+)
pub fn genDictMerge(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();
    try emitFmtConst(self, "(dmerge_{d}: {{\n", .{label_id});
    self.indent_level += 1;

    try self.emitIndent();
    try emitConst(self, "var __merged = @TypeOf(");
    try collection_ops.genExprWrapped(self, binop.left.*);
    try emitConst(self, "){};\n");

    try self.emitIndent();
    try emitConst(self, "var __left_iter = ");
    try collection_ops.genExprWrapped(self, binop.left.*);
    try emitConst(self, ".iterator();\n");
    try self.emitIndent();
    try emitConst(self, "while (__left_iter.next()) |entry| {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try emitConst(self, "try __merged.put(entry.key_ptr.*, entry.value_ptr.*);\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self, "}\n");

    try self.emitIndent();
    try emitConst(self, "var __right_iter = ");
    try collection_ops.genExprWrapped(self, binop.right.*);
    try emitConst(self, ".iterator();\n");
    try self.emitIndent();
    try emitConst(self, "while (__right_iter.next()) |entry| {\n");
    self.indent_level += 1;
    try self.emitIndent();
    try emitConst(self, "try __merged.put(entry.key_ptr.*, entry.value_ptr.*);\n");
    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self, "}\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :dmerge_{d} __merged;\n", .{label_id});

    self.indent_level -= 1;
    try self.emitIndent();
    try emitConst(self, "})");
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
        try emitConst(self, "(");
        try collection_ops.genExprWrapped(self, binop.left.*);
        const op_str = switch (binop.op) {
            .BitAnd => " and ",
            .BitOr => " or ",
            .BitXor => " != ",
            else => unreachable,
        };
        try emitConst(self, op_str);
        try collection_ops.genExprWrapped(self, binop.right.*);
        try emitConst(self, ")");
        return;
    }

    const needs_cast = (left_is_usize and right_is_int) or (left_is_int and right_is_usize);

    // Handle mixed int/float multiplication
    const left_is_float = type_traits.isFloating(left_type);
    const right_is_float = type_traits.isFloating(right_type);
    const left_is_unknown = (left_type == .unknown);
    const right_is_unknown = (right_type == .unknown);
    if (binop.op == .Mult and ((left_is_int and right_is_float) or (left_is_float and right_is_int))) {
        try emitConst(self, "(");
        if (left_is_int) {
            try emitConst(self, "@as(f64, @floatFromInt(");
            try collection_ops.genExprWrapped(self, binop.left.*);
            try emitConst(self, "))");
        } else {
            try collection_ops.genExprWrapped(self, binop.left.*);
        }
        try emitConst(self, " * ");
        if (right_is_int) {
            try emitConst(self, "@as(f64, @floatFromInt(");
            try collection_ops.genExprWrapped(self, binop.right.*);
            try emitConst(self, "))");
        } else {
            try collection_ops.genExprWrapped(self, binop.right.*);
        }
        try emitConst(self, ")");
        return;
    }
    // Handle unknown type * float
    if (binop.op == .Mult and ((left_is_unknown and right_is_float) or (left_is_float and right_is_unknown))) {
        try emitConst(self, "(runtime.toFloat(");
        try collection_ops.genExprWrapped(self, binop.left.*);
        try emitConst(self, ") * runtime.toFloat(");
        try collection_ops.genExprWrapped(self, binop.right.*);
        try emitConst(self, "))");
        return;
    }

    try emitConst(self, "(");

    // Cast left operand if needed
    if (left_is_bool) {
        try emitConst(self, "@as(i64, @intFromBool(");
    } else if (left_is_usize and needs_cast) {
        try emitConst(self, "@as(i64, @intCast(");
    }
    try collection_ops.genExprWrapped(self, binop.left.*);
    if (left_is_bool or (left_is_usize and needs_cast)) {
        try emitConst(self, "))");
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
    try emitConst(self, op_str);

    // For shift operations, the RHS must be u6 for i64
    const is_shift_op = binop.op == .LShift or binop.op == .RShift;
    if (is_shift_op) {
        try emitConst(self, "@as(u6, @intCast(@mod(");
        try collection_ops.genExprWrapped(self, binop.right.*);
        try emitConst(self, ", 64)))");
    } else if (right_is_bool) {
        try emitConst(self, "@as(i64, @intFromBool(");
        try collection_ops.genExprWrapped(self, binop.right.*);
        try emitConst(self, "))");
    } else if (right_is_usize and needs_cast) {
        try emitConst(self, "@as(i64, @intCast(");
        try collection_ops.genExprWrapped(self, binop.right.*);
        try emitConst(self, "))");
    } else {
        try collection_ops.genExprWrapped(self, binop.right.*);
    }

    try emitConst(self, ")");
}
