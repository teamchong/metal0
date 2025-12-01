/// Logical operations: and, or, not
/// Handles Python value-based semantics (returns actual values, not just booleans)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;

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

        // Infer type of first value to generate appropriate truthiness check
        const a_type = try self.inferExprScoped(a);

        try self.emit("blk: {\n");
        try self.emit("const _a = ");
        try genExpr(self, a);
        try self.emit(";\n");
        try self.emit("const _b = ");
        try genExpr(self, b);
        try self.emit(";\n");

        // Generate type-appropriate truthiness check
        // Note: string is a tagged union with payload StringKind, so we check the tag
        const truthy_check: []const u8 = switch (@as(std.meta.Tag(@TypeOf(a_type)), a_type)) {
            .string => "_a.len > 0",
            .int, .usize => "_a != 0",
            .float => "_a != 0.0",
            .bool => "_a",
            .bigint => "!_a.isZero()",
            else => "runtime.pyTruthy(_a)",
        };

        if (boolop.op == .Or) {
            // "a or b": return a if truthy, else b
            try self.emitFmt("break :blk if ({s}) _a else _b;\n", .{truthy_check});
        } else {
            // "a and b": return a if falsy, else b
            try self.emitFmt("break :blk if (!({s})) _a else _b;\n", .{truthy_check});
        }
        try self.emit("}");
        return;
    }

    // For more than 2 values, use simple approach (may not be fully correct but handles common cases)
    const op_str = if (boolop.op == .And) " and " else " or ";
    for (boolop.values, 0..) |value, i| {
        if (i > 0) try self.emit(op_str);
        try self.emit("runtime.pyTruthy(");
        try genExpr(self, value);
        try self.emit(")");
    }
}
