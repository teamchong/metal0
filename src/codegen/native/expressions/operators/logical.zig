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
            if (a_tag == .class_instance) {
                break :blk std.mem.eql(u8, a_type.class_instance, b_type.class_instance);
            }
            break :blk true;
        };

        if (!types_compatible) {
            // Types incompatible - generate bool-returning version
            // Python's `x or y` where x and y have different types, when used as bool,
            // is equivalent to `bool(x) or bool(y)`
            const op_str = if (boolop.op == .And) " and " else " or ";
            try self.emit("(runtime.toBool(");
            try genExpr(self, a);
            try self.emit(")");
            try self.emit(op_str);
            try self.emit("runtime.toBool(");
            try genExpr(self, b);
            try self.emit("))");
            return;
        }

        // Use unique label to avoid redefinition with nested boolean ops
        const label_id = self.block_label_counter;
        self.block_label_counter += 1;

        try self.emitFmt("boolop_{d}: {{\n", .{label_id});
        try self.emit("const _a = ");
        try genExpr(self, a);
        try self.emit(";\n");
        try self.emit("const _b = ");
        try genExpr(self, b);
        try self.emit(";\n");

        // Generate type-appropriate truthiness check
        // Note: string is a tagged union with payload StringKind, so we check the tag
        // Use runtime.toBool for unknown types (handles __bool__ duck typing)
        const truthy_check: []const u8 = switch (a_tag) {
            .string => "_a.len > 0",
            .int, .usize => "_a != 0",
            .float => "_a != 0.0",
            .bool => "_a",
            .bigint => "!_a.isZero()",
            else => "runtime.toBool(_a)",
        };

        if (boolop.op == .Or) {
            // "a or b": return a if truthy, else b
            try self.emitFmt("break :boolop_{d} if ({s}) _a else _b;\n", .{ label_id, truthy_check });
        } else {
            // "a and b": return a if falsy, else b
            try self.emitFmt("break :boolop_{d} if (!({s})) _a else _b;\n", .{ label_id, truthy_check });
        }
        try self.emit("}");
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
