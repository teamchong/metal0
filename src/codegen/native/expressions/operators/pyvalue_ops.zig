/// PyValue (Two-Flow) operations for uncertain type operands
/// Handles runtime-polymorphic arithmetic using runtime.PyValue methods
///
/// MIGRATION STATUS: Fully migrated to ZigBuilder pattern
/// - Uses captureExpr() to bridge AST expressions to ZigValue
/// - Uses builder.write() for all output
/// - Uses self.emitZigValue() for ZigValue emission
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;

/// PyValue method names for binary operations
pub const PyValueMethods = std.StaticStringMap([]const u8).initComptime(.{
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
/// TWO-FLOW TYPE SYSTEM: Check type and confidence together.
///
/// Decision logic:
/// 1. If operand is a binary op that would use PyValue methods → uncertain (result is PyValue)
/// 2. If type is explicitly PyValue or unknown → use PyValue (uncertain)
/// 3. If type is concrete (int/float/etc.) AND confidence is explicitly tracked as uncertain → use PyValue
/// 4. If type is concrete AND confidence is NOT tracked or is certain → use native ops
///
/// NOTE: The confidence map defaults to `.uncertain` for untracked variables, so we need
/// to distinguish between "explicitly uncertain" and "not tracked". We check if confidence
/// is in the map before trusting the uncertain default.
pub fn isOperandUncertain(self: *NativeCodegen, expr: ast.Node) bool {
    // Check if operand is a binary operation that would return PyValue
    // This handles nested operations like: (a * b) + (c * d) where inner ops use PyValue
    if (expr == .binop) {
        const binop = expr.binop;
        // If this binary op has a PyValue method, recursively check its operands
        // If either operand of the nested binop is uncertain, the nested binop returns PyValue
        if (PyValueMethods.get(@tagName(binop.op)) != null) {
            const left_uncertain = isOperandUncertain(self, binop.left.*);
            const right_uncertain = isOperandUncertain(self, binop.right.*);
            if (left_uncertain or right_uncertain) {
                return true;
            }
        }
    }

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

        // Check type first
        const var_type = self.type_inferrer.getScopedVar(name) orelse
            self.type_inferrer.var_types.get(name);
        if (var_type) |vt| {
            switch (vt) {
                // Explicit PyValue or unknown - always use PyValue methods
                .pyvalue, .unknown => return true,
                // Concrete types - check if confidence is EXPLICITLY tracked as uncertain
                // If confidence is not tracked, default to using native ops (not uncertain)
                .string, .int, .float, .bool, .none, .bytes => {
                    // Check if this variable has explicitly tracked confidence
                    if (self.type_inferrer.hasTrackedConfidence(name)) {
                        return self.isVarUncertain(name);
                    }
                    // Not tracked - assume certain (use native ops)
                    return false;
                },
                // Class instances - don't use PyValue methods
                .class_instance => return false,
                else => {},
            }
        }
        // Fall back to confidence check for variables not in var_types
        return self.isVarUncertain(name);
    }

    // Check attribute access - if the inferred type is PyValue, treat as uncertain
    if (expr == .attribute) {
        const attr_type = self.type_inferrer.inferExpr(expr) catch return false;
        return attr_type == .pyvalue or attr_type == .unknown;
    }

    return false;
}

/// Check if an expression is a comptime literal (int or float constant)
/// Comptime literals need explicit type casting before wrapping in PyValue.from()
pub fn isComptimeLiteral(expr: ast.Node) bool {
    return switch (expr) {
        .constant => |c| c.value == .int or c.value == .float,
        .unaryop => |u| (u.op == .USub or u.op == .UAdd) and isComptimeLiteral(u.operand.*),
        else => false,
    };
}

/// Check if a comptime literal is a float
pub fn isComptimeFloat(expr: ast.Node) bool {
    return switch (expr) {
        .constant => |c| c.value == .float,
        .unaryop => |u| (u.op == .USub or u.op == .UAdd) and isComptimeFloat(u.operand.*),
        else => false,
    };
}

/// Generate PyValue binary operations for uncertain operands
/// Pattern: (runtime.PyValue.from(left)).method(runtime.PyValue.from(right))
pub fn genPyValueBinOp(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    const method_name = PyValueMethods.get(@tagName(binop.op)) orelse {
        // Unsupported operation - use VM fallback for drop-in CPython replacement
        try self.emitVMFallback(.{ .binop = binop });
        return;
    };

    const b = try self.getBuilder();

    // Capture operands as ZigValues
    const left_operand = try self.captureExpr(binop.left.*);
    const right_operand = try self.captureExpr(binop.right.*);

    // ALWAYS wrap both operands in PyValue.from() for safety
    // This handles mixed type operations like: primitive // PyValue
    // PyValue.from() is a no-op for existing PyValues, so it's safe to wrap unconditionally

    // Emit: (runtime.PyValue.from(...)).method(runtime.PyValue.from(...))
    try b.emitRaw("(runtime.PyValue.from(");
    // Handle comptime literal casting for left operand
    if (isComptimeLiteral(binop.left.*)) {
        if (isComptimeFloat(binop.left.*)) {
            try b.emitRaw("@as(f64, ");
        } else {
            try b.emitRaw("@as(i64, ");
        }
        try self.emitZigValue(left_operand);
        try b.emitRaw(")");
    } else {
        try self.emitZigValue(left_operand);
    }
    try b.emitRaw(")).");
    try b.emitRaw(method_name);
    try b.emitRaw("(runtime.PyValue.from(");
    // Handle comptime literal casting for right operand
    if (isComptimeLiteral(binop.right.*)) {
        if (isComptimeFloat(binop.right.*)) {
            try b.emitRaw("@as(f64, ");
        } else {
            try b.emitRaw("@as(i64, ");
        }
        try self.emitZigValue(right_operand);
        try b.emitRaw(")");
    } else {
        try self.emitZigValue(right_operand);
    }
    try b.emitRaw("))");

    try self.flushBuilder();
}
