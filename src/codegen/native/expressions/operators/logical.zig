/// Logical operations: and, or, not
/// Handles Python value-based semantics (returns actual values, not just booleans)
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const expr_emitter = @import("../../expr_emitter.zig");

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
            if (i > 0) try self.emit(op_str);
            try genExpr(self, value);
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
            try self.emit("runtime.toBool(");
            if (boolop.op == .Or) {
                try self.emit("(try runtime.pyOr(__global_allocator, ");
            } else {
                try self.emit("(try runtime.pyAnd(__global_allocator, ");
            }
            try genExpr(self, a);
            try self.emit(", ");
            try genExpr(self, b);
            try self.emit(")))");
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
        if (i > 0) try self.emit(op_str);
        try self.emit("runtime.toBool(");
        try genExpr(self, value);
        try self.emit(")");
    }
}
