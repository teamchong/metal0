/// Logical operations: and, or, not
/// Handles Python value-based semantics (returns actual values, not just booleans)
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
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const expr_emitter = @import("../../expr_emitter.zig");
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
// Logical operation helpers - auto-closing patterns
// ============================================

/// Emit runtime.toBool(operand)
/// Uses auto-close pattern to guarantee matching parentheses
fn emitToBool(self: *NativeCodegen, operand: ZigValue) CodegenError!void {
    try emitConst(self, "runtime.toBool");
    const Ctx = struct { o: ZigValue };
    try self.withParensCtx(Ctx{ .o = operand }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emitZigValue(ctx.o);
        }
    }.f);
}

/// Emit runtime.toBool((try runtime.pyOr/pyAnd(alloc, a, b)))
/// Uses auto-close pattern to guarantee matching parentheses
fn emitRuntimePyBoolOp(self: *NativeCodegen, is_or: bool, a_operand: ZigValue, b_operand: ZigValue) CodegenError!void {
    try emitConst(self, "runtime.toBool");
    const Ctx = struct { a: ZigValue, b: ZigValue, or_op: bool };
    try self.withParensCtx(Ctx{ .a = a_operand, .b = b_operand, .or_op = is_or }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            const Inner = struct { a: ZigValue, b: ZigValue };
            if (ctx.or_op) {
                try emitConst(s, "try runtime.pyOr");
            } else {
                try emitConst(s, "try runtime.pyAnd");
            }
            try s.withParensCtx(Inner{ .a = ctx.a, .b = ctx.b }, struct {
                pub fn g(si: *NativeCodegen, inner: Inner) CodegenError!void {
                    try emitConst(si, "__global_allocator, ");
                    try si.emitZigValue(inner.a);
                    try emitConst(si, ", ");
                    try si.emitZigValue(inner.b);
                }
            }.g);
        }
    }.f);
}



/// Generate boolean operations (and, or)
/// Python's and/or return the actual values, not booleans:
/// - "a or b" returns a if truthy, else b
/// - "a and b" returns a if falsy, else b
pub fn genBoolOp(self: *NativeCodegen, boolop: ast.Node.BoolOp) CodegenError!void {
    // Check if all values are booleans - can use simple Zig and/or
    var all_bool = true;
    for (boolop.values) |value| {
        const val_type = self.inferExprScoped(value) catch .unknown;
        if (val_type != .bool) {
            all_bool = false;
            break;
        }
    }

    if (all_bool) {
        const op_str = if (boolop.op == .And) " and " else " or ";
        for (boolop.values, 0..) |value, i| {
            if (i > 0) try emitConst(self, op_str);
            const operand = try self.captureExpr(value);
            try self.emitZigValue(operand);
        }
        return;
    }

    // Non-boolean types need Python semantics
    // For "a or b": if truthy(a) then a else b
    // For "a and b": if not truthy(a) then a else b
    // We generate nested ternary expressions
    if (boolop.values.len == 2) {
        const a = boolop.values[0];
        const b = boolop.values[1];

        // Infer types of both values
        const a_type = try self.inferExprScoped(a);
        const b_type = try self.inferExprScoped(b);
        const a_tag = @as(std.meta.Tag(@TypeOf(a_type)), a_type);
        const b_tag = @as(std.meta.Tag(@TypeOf(b_type)), b_type);

        // If types are incompatible (different), we can't use value-returning semantics
        // Instead, return bool (which is what Python would do at runtime when used in bool context)
        // Check for type compatibility:
        // - Same tag = compatible
        // - class_instance types are only compatible if same class name
        const types_compatible = blk: {
            if (a_tag != b_tag) break :blk false;
            if (type_traits.isClassInstance(a_type)) {
                break :blk std.mem.eql(u8, a_type.class_instance, b_type.class_instance);
            }
            break :blk true;
        };

        if (!types_compatible) {
            // Types incompatible - use runtime helper for Python or/and semantics
            // Python's `x or y` returns x if truthy, else y (preserving actual value)
            // Use runtime.pyOr/pyAnd which returns PyValue
            // Wrap with runtime.toBool so result can be used in boolean contexts (if, while, etc.)

            // Capture operands as ZigValues
            const a_operand = try self.captureExpr(a);
            const b_operand = try self.captureExpr(b);

            try emitRuntimePyBoolOp(self, boolop.op == .Or, a_operand, b_operand);
            return;
        }

        // Use unique label to avoid redefinition with nested boolean ops
        var em = self.exprEmitter();
        var blk = try em.labeledBlock("boolop", "_a", a);
        try blk.emit("const _b = ");
        try genExpr(self, b);
        try blk.emit("; ");

        // Generate type-appropriate truthiness check
        // Note: string is a tagged union with payload StringKind, so we check the tag
        // Use runtime.toBool for unknown types (handles __bool__ duck typing)
        // Two-Flow: explicit .pyvalue/.unknown cases for safety on uncertain types
        const truthy_check: []const u8 = switch (a_tag) {
            .string => "_a.len > 0",
            .int, .usize => "_a != 0",
            .float => "_a != 0.0",
            .bool => "_a",
            .bigint => "!_a.isZero()",
            .pyvalue, .unknown => "runtime.toBool(_a)", // Two-Flow: uncertain types use runtime
            else => "runtime.toBool(_a)",
        };

        if (boolop.op == .Or) {
            // "a or b": return a if truthy, else b
            try blk.emitFmt("break :{s}_{d} if ({s}) _a else _b", .{ blk.getPrefix(), blk.getLabelId(), truthy_check });
        } else {
            // "a and b": return a if falsy, else b
            try blk.emitFmt("break :{s}_{d} if (!({s})) _a else _b", .{ blk.getPrefix(), blk.getLabelId(), truthy_check });
        }
        try blk.close();
        return;
    }

    // For more than 2 values, use simple approach (may not be fully correct but handles common cases)
    const op_str = if (boolop.op == .And) " and " else " or ";
    for (boolop.values, 0..) |value, i| {
        if (i > 0) try emitConst(self, op_str);
        const operand = try self.captureExpr(value);
        try emitToBool(self, operand);
    }
}
