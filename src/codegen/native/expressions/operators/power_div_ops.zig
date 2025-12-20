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
/// Uses auto-close pattern to guarantee matching parentheses
fn emitExprBoolCoerced(self: *NativeCodegen, expr: ast.Node, is_bool: bool) CodegenError!void {
    if (is_bool) {
        try emitConst(self, "@as(i64, @intFromBool");
        try self.emitParens(expr);
        try emitConst(self, ")");
    } else {
        try genExpr(self, expr);
    }
}

/// Emit two-argument function call: func(expr1, expr2)
/// NOTE: func string should include opening paren and any prefix args with trailing comma
/// Example: "runtime.pyFloorDiv(__global_allocator, " generates: pyFloorDiv(__global_allocator, left, right)
fn emitBinaryCall(self: *NativeCodegen, func: []const u8, left: ast.Node, right: ast.Node) CodegenError!void {
    try emitConst(self, func);
    // Don't use withParensCtx - func string already has opening paren if needed
    // Just emit the two arguments and closing paren
    try genExpr(self, left);
    try emitConst(self, ", ");
    try genExpr(self, right);
    try emitConst(self, ")");
}

/// Generate power operation
/// Uses auto-close patterns to guarantee matching parentheses
pub fn genPowOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    const left_is_bool = type_traits.isBoolean(left_type);
    const right_is_bool = type_traits.isBoolean(right_type);

    // Check if exponent is large enough to need UnifiedInt
    if (binop.right.* == .constant and binop.right.constant.value == .int) {
        const exp = binop.right.constant.value.int;
        if (exp >= 20) {
            const Ctx = struct { b: ast.Node.BinOp, lb: bool, rb: bool };
            try emitConst(self, "runtime.unified_int_ops.pow");
            try self.withParensCtx(Ctx{ .b = binop, .lb = left_is_bool, .rb = right_is_bool }, struct {
                pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
                    try emitConst(s, "runtime.unified_int_ops.fromI64");
                    const Inner = struct { e: ast.Node, ib: bool };
                    try s.withParensCtx(Inner{ .e = ctx.b.left.*, .ib = ctx.lb }, struct {
                        pub fn g(si: *NativeCodegen, inner: Inner) CodegenError!void {
                            try emitExprBoolCoerced(si, inner.e, inner.ib);
                        }
                    }.g);
                    try emitConst(s, ", @as(u32, @intCast");
                    try s.withParensCtx(Inner{ .e = ctx.b.right.*, .ib = ctx.rb }, struct {
                        pub fn g(si: *NativeCodegen, inner: Inner) CodegenError!void {
                            try emitExprBoolCoerced(si, inner.e, inner.ib);
                        }
                    }.g);
                    try emitConst(s, "), __global_allocator");
                }
            }.f);
            return;
        }
        // Small constant positive exponent - use i64
        const Ctx = struct { b: ast.Node.BinOp, lb: bool, rb: bool };
        try emitConst(self, "std.math.pow");
        try self.withParensCtx(Ctx{ .b = binop, .lb = left_is_bool, .rb = right_is_bool }, struct {
            pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
                try emitConst(s, "i64, ");
                try emitExprBoolCoerced(s, ctx.b.left.*, ctx.lb);
                try emitConst(s, ", ");
                try emitExprBoolCoerced(s, ctx.b.right.*, ctx.rb);
            }
        }.f);
        return;
    }
    // Runtime exponent - use f64 for safety
    const Ctx = struct { b: ast.Node.BinOp, lb: bool, rb: bool };
    try emitConst(self, "std.math.pow");
    try self.withParensCtx(Ctx{ .b = binop, .lb = left_is_bool, .rb = right_is_bool }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try emitConst(s, "f64, @as(f64, @floatFromInt");
            const Inner = struct { e: ast.Node, ib: bool };
            try s.withParensCtx(Inner{ .e = ctx.b.left.*, .ib = ctx.lb }, struct {
                pub fn g(si: *NativeCodegen, inner: Inner) CodegenError!void {
                    try emitExprBoolCoerced(si, inner.e, inner.ib);
                }
            }.g);
            try emitConst(s, "), @as(f64, @floatFromInt");
            try s.withParensCtx(Inner{ .e = ctx.b.right.*, .ib = ctx.rb }, struct {
                pub fn g(si: *NativeCodegen, inner: Inner) CodegenError!void {
                    try emitExprBoolCoerced(si, inner.e, inner.ib);
                }
            }.g);
            try emitConst(s, ")");
        }
    }.f);
}

/// Generate division operation
/// Uses auto-close patterns to guarantee matching parentheses
pub fn genDivOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    // Check if this is Path / string (path join)
    if (left_type == .path) {
        try genExpr(self, binop.left.*);
        try emitConst(self, ".join");
        try self.emitParens(binop.right.*);
        return;
    }

    const left_is_bool = type_traits.isBoolean(left_type);
    const right_is_bool = type_traits.isBoolean(right_type);

    // At module level or inside defer, we can't use 'try'
    if (self.indent_level == 0 or self.inside_defer) {
        const Ctx = struct { b: ast.Node.BinOp, lb: bool, rb: bool };
        try self.withParensCtx(Ctx{ .b = binop, .lb = left_is_bool, .rb = right_is_bool }, struct {
            pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
                try emitConst(s, "@as(f64, @floatFromInt");
                const Inner = struct { e: ast.Node, ib: bool };
                try s.withParensCtx(Inner{ .e = ctx.b.left.*, .ib = ctx.lb }, struct {
                    pub fn g(si: *NativeCodegen, inner: Inner) CodegenError!void {
                        try emitExprBoolCoerced(si, inner.e, inner.ib);
                    }
                }.g);
                try emitConst(s, ") / @as(f64, @floatFromInt");
                try s.withParensCtx(Inner{ .e = ctx.b.right.*, .ib = ctx.rb }, struct {
                    pub fn g(si: *NativeCodegen, inner: Inner) CodegenError!void {
                        try emitExprBoolCoerced(si, inner.e, inner.ib);
                    }
                }.g);
                try emitConst(s, ")");
            }
        }.f);
    } else {
        const Ctx = struct { b: ast.Node.BinOp, lb: bool, rb: bool };
        try emitConst(self, "try runtime.divideFloat");
        try self.withParensCtx(Ctx{ .b = binop, .lb = left_is_bool, .rb = right_is_bool }, struct {
            pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
                try emitExprBoolCoerced(s, ctx.b.left.*, ctx.lb);
                try emitConst(s, ", ");
                try emitExprBoolCoerced(s, ctx.b.right.*, ctx.rb);
            }
        }.f);
    }
}

/// Generate matrix multiplication operation
/// Uses auto-close patterns to guarantee matching parentheses
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
/// Uses auto-close patterns to guarantee matching parentheses
pub fn genFloorDivOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    const semantics = operator_traits.getFloorDivSemantics(left_type, right_type);
    switch (semantics) {
        .runtime_dispatch => {
            try emitBinaryCall(self, "runtime.pyFloorDiv(__global_allocator, ", binop.left.*, binop.right.*);
        },
        .python_floored => {
            try emitConst(self, "@floor");
            try self.emitBinOp(binop.left.*, " / ", binop.right.*);
        },
        .zig_native => {
            const left_is_bool = type_traits.isBoolean(left_type);
            const right_is_bool = type_traits.isBoolean(right_type);
            const Ctx = struct { b: ast.Node.BinOp, lb: bool, rb: bool };
            try emitConst(self, "@divFloor");
            try self.withParensCtx(Ctx{ .b = binop, .lb = left_is_bool, .rb = right_is_bool }, struct {
                pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
                    try emitExprBoolCoerced(s, ctx.b.left.*, ctx.lb);
                    try emitConst(s, ", ");
                    try emitExprBoolCoerced(s, ctx.b.right.*, ctx.rb);
                }
            }.f);
        },
    }
}

/// Generate modulo operation (or string formatting)
/// Uses auto-close patterns to guarantee matching parentheses
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
            const Ctx = struct { b: ast.Node.BinOp, lb: bool, rb: bool };
            try emitConst(self, "@mod");
            try self.withParensCtx(Ctx{ .b = binop, .lb = left_is_bool, .rb = right_is_bool }, struct {
                pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
                    try emitExprBoolCoerced(s, ctx.b.left.*, ctx.lb);
                    try emitConst(s, ", ");
                    try emitExprBoolCoerced(s, ctx.b.right.*, ctx.rb);
                }
            }.f);
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
    // Uses emitBinOp for auto-close brackets (via genExprWrapped -> genExpr)
    if (left_is_bool and right_is_bool and
        (binop.op == .BitAnd or binop.op == .BitOr or binop.op == .BitXor))
    {
        const op_str = switch (binop.op) {
            .BitAnd => " and ",
            .BitOr => " or ",
            .BitXor => " != ",
            else => unreachable,
        };
        try self.emitBinOp(binop.left.*, op_str, binop.right.*);
        return;
    }

    const needs_cast = (left_is_usize and right_is_int) or (left_is_int and right_is_usize);

    // Handle mixed int/float multiplication - uses withParens for outer bracket
    const left_is_float = type_traits.isFloating(left_type);
    const right_is_float = type_traits.isFloating(right_type);
    const left_is_unknown = (left_type == .unknown);
    const right_is_unknown = (right_type == .unknown);
    if (binop.op == .Mult and ((left_is_int and right_is_float) or (left_is_float and right_is_int))) {
        const Ctx = struct { b: ast.Node.BinOp, li: bool, ri: bool };
        try self.withParensCtx(Ctx{ .b = binop, .li = left_is_int, .ri = right_is_int }, struct {
            pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
                if (ctx.li) {
                    try emitConst(s, "@as(f64, @floatFromInt");
                    try s.emitParens(ctx.b.left.*);
                    try emitConst(s, ")");
                } else {
                    try collection_ops.genExprWrapped(s, ctx.b.left.*);
                }
                try emitConst(s, " * ");
                if (ctx.ri) {
                    try emitConst(s, "@as(f64, @floatFromInt");
                    try s.emitParens(ctx.b.right.*);
                    try emitConst(s, ")");
                } else {
                    try collection_ops.genExprWrapped(s, ctx.b.right.*);
                }
            }
        }.f);
        return;
    }
    // Handle unknown type * float - uses withParens for outer bracket
    if (binop.op == .Mult and ((left_is_unknown and right_is_float) or (left_is_float and right_is_unknown))) {
        const Ctx = struct { b: ast.Node.BinOp };
        try self.withParensCtx(Ctx{ .b = binop }, struct {
            pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
                try emitConst(s, "runtime.toFloat");
                try s.emitParens(ctx.b.left.*);
                try emitConst(s, " * runtime.toFloat");
                try s.emitParens(ctx.b.right.*);
            }
        }.f);
        return;
    }

    // Main case: wrap entire binop in parens using withParens callback
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

    const Ctx = struct {
        b: ast.Node.BinOp,
        op: []const u8,
        lb: bool,
        rb: bool,
        lu: bool,
        ru: bool,
        nc: bool,
        shift: bool,
    };
    try self.withParensCtx(Ctx{
        .b = binop,
        .op = op_str,
        .lb = left_is_bool,
        .rb = right_is_bool,
        .lu = left_is_usize,
        .ru = right_is_usize,
        .nc = needs_cast,
        .shift = is_shift_op,
    }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            // Cast left operand if needed
            if (ctx.lb) {
                try emitConst(s, "@as(i64, @intFromBool");
                try s.emitParens(ctx.b.left.*);
                try emitConst(s, ")");
            } else if (ctx.lu and ctx.nc) {
                try emitConst(s, "@as(i64, @intCast");
                try s.emitParens(ctx.b.left.*);
                try emitConst(s, ")");
            } else {
                try collection_ops.genExprWrapped(s, ctx.b.left.*);
            }

            try emitConst(s, ctx.op);

            // For shift operations, the RHS must be u6 for i64
            if (ctx.shift) {
                try emitConst(s, "@as(u6, @intCast(@mod(");
                try s.genExpr(ctx.b.right.*);
                try emitConst(s, ", 64)))");
            } else if (ctx.rb) {
                try emitConst(s, "@as(i64, @intFromBool");
                try s.emitParens(ctx.b.right.*);
                try emitConst(s, ")");
            } else if (ctx.ru and ctx.nc) {
                try emitConst(s, "@as(i64, @intCast");
                try s.emitParens(ctx.b.right.*);
                try emitConst(s, ")");
            } else {
                try collection_ops.genExprWrapped(s, ctx.b.right.*);
            }
        }
    }.f);
}
