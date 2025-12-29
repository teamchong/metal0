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
/// Check if expression contains any attribute access that involves 'self'
/// This is used to detect class field access like self.__num, self.__den
fn containsSelfAttribute(expr: ast.Node) bool {
    switch (expr) {
        .attribute => |attr| {
            // Check if the base object is 'self'
            if (attr.value.* == .name) {
                if (std.mem.eql(u8, attr.value.name.id, "self")) {
                    return true;
                }
            }
            // Also check for chained access like self.foo.bar
            return containsSelfAttribute(attr.value.*);
        },
        .binop => |binop| {
            return containsSelfAttribute(binop.left.*) or containsSelfAttribute(binop.right.*);
        },
        .unaryop => |unaryop| {
            return containsSelfAttribute(unaryop.operand.*);
        },
        else => return false,
    }
}

/// Check if any leaf expression in the tree is uncertain
/// This traverses binops recursively to find uncertain leaves
fn hasUncertainLeaf(self: *NativeCodegen, expr: ast.Node) bool {
    switch (expr) {
        .binop => |binop| {
            // Recursively check both operands for uncertain leaves
            return hasUncertainLeaf(self, binop.left.*) or hasUncertainLeaf(self, binop.right.*);
        },
        .unaryop => |unaryop| {
            return hasUncertainLeaf(self, unaryop.operand.*);
        },
        else => {
            // For leaf nodes, use the standard uncertainty check
            return isOperandUncertainLeaf(self, expr);
        },
    }
}

/// Check if a leaf expression is uncertain (non-recursive)
fn isOperandUncertainLeaf(self: *NativeCodegen, expr: ast.Node) bool {
    // Check if this is a variable with uncertain confidence
    if (expr == .name) {
        const name = expr.name.id;
        if (std.mem.eql(u8, name, "self")) return false;
        if (self.anytype_params.contains(name)) return false;

        const var_type = self.type_inferrer.getScopedVar(name) orelse
            self.type_inferrer.var_types.get(name);
        if (var_type) |vt| {
            switch (vt) {
                .pyvalue, .unknown => return true,
                .string, .int, .float, .bool, .none, .bytes => {
                    if (self.type_inferrer.hasTrackedConfidence(name)) {
                        return self.isVarUncertain(name);
                    }
                    return false;
                },
                .class_instance => return false,
                else => {},
            }
        }
        return self.isVarUncertain(name);
    }

    // Check attribute access - only treat as uncertain if type is pyvalue/unknown
    if (expr == .attribute) {
        const attr = expr.attribute;

        // FIRST: Check if base is an anytype parameter - if so, NOT uncertain
        // Anytype parameters use comptime polymorphism, so attribute access is resolved at compile time
        if (attr.value.* == .name) {
            const base_name = attr.value.name.id;
            if (self.anytype_params.contains(base_name)) {
                return false; // Anytype attribute access is NOT uncertain
            }
            // Also check for "_converted" suffix variables derived from anytype params
            // e.g., other_converted is created from anytype param "other" during comptime type dispatch
            if (std.mem.endsWith(u8, base_name, "_converted")) {
                const original_name = base_name[0 .. base_name.len - "_converted".len];
                if (self.anytype_params.contains(original_name)) {
                    return false; // Converted anytype param attribute access is NOT uncertain
                }
            }
        }

        // For self.xxx access in class methods, check if the field has a known type
        // from the class field registry. If so, use the field type, not inference.
        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
            if (self.current_class_name) |class_name| {
                if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                    if (class_info.fields.get(attr.attr)) |field_type| {
                        // Field has a known type - only uncertain if pyvalue/unknown
                        return field_type == .pyvalue or field_type == .unknown;
                    }
                }
                // If we're in a class context but field not found, assume it's NOT uncertain
                // (self.xxx access in class methods should use native types)
                return false;
            }
        }
        // For other variable access, check if the variable is a known class instance
        // This handles cases like other_converted.__den where other_converted is of type Rat
        if (attr.value.* == .name) {
            const var_name = attr.value.name.id;
            const var_type = self.type_inferrer.getScopedVar(var_name) orelse
                self.type_inferrer.var_types.get(var_name);
            if (var_type) |vt| {
                if (vt == .class_instance) {
                    const class_name = vt.class_instance;
                    if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                        if (class_info.fields.get(attr.attr)) |field_type| {
                            // Field has a known type - only uncertain if pyvalue/unknown
                            return field_type == .pyvalue or field_type == .unknown;
                        }
                    }
                }
            }
        }
        // For other attribute access, use type inference
        const attr_type = self.type_inferrer.inferExpr(expr) catch return false;
        return attr_type == .pyvalue or attr_type == .unknown;
    }

    return false;
}

pub fn isOperandUncertain(self: *NativeCodegen, expr: ast.Node) bool {
    // Check if operand is a binary operation that would return PyValue
    // This handles nested operations like: (a * b) + (c * d) where inner ops use PyValue
    if (expr == .binop) {
        const binop = expr.binop;
        // If this binop has a PyValue method (Add, Sub, Mul, etc.), check if EITHER
        // operand is uncertain. If so, the codegen will use PyValue ops, returning PyValue.
        if (PyValueMethods.get(@tagName(binop.op)) != null) {
            // Recursively check operands - if either would trigger PyValue ops, result is PyValue
            if (isOperandUncertain(self, binop.left.*) or isOperandUncertain(self, binop.right.*)) {
                return true;
            }
            // Even if operands aren't uncertain, check the inferred result type
            // This catches cases where type inference marks the result as uncertain
            // due to context the recursive check doesn't see
            const result_type = self.type_inferrer.inferExpr(expr) catch return false;
            if (result_type == .pyvalue or result_type == .unknown) {
                return true;
            }
            return false;
        }
        // For non-PyValueMethods ops (comparison, etc.), check inferred result type
        const result_type = self.type_inferrer.inferExpr(expr) catch return false;
        if (result_type == .pyvalue or result_type == .unknown) {
            return true;
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

    // Check attribute access - must be consistent with builder's exprToValue confidence tracking
    // The builder marks class instance attributes and unknown type attributes as uncertain
    if (expr == .attribute) {
        const attr = expr.attribute;

        if (attr.value.* == .name) {
            const base_name = attr.value.name.id;

            // For self.xxx in class methods - check field type rather than marking all as uncertain
            // Only mark as uncertain if the field type is actually unknown/pyvalue
            if (std.mem.eql(u8, base_name, "self")) {
                if (self.current_class_name) |class_name| {
                    if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                        if (class_info.fields.get(attr.attr)) |field_type| {
                            // Field has a known type - only uncertain if pyvalue/unknown
                            return field_type == .pyvalue or field_type == .unknown;
                        }
                    }
                    // Field not found in registry - assume NOT uncertain (use native ops)
                    return false;
                }
            }

            // For anytype param attributes - uncertain because the param's type is unknown
            // (builder's exprToValue marks unknown type attributes as uncertain at line 2532-2533)
            if (self.anytype_params.contains(base_name)) {
                return true; // Anytype attribute access IS uncertain in binop context
            }

            // Also check for "_converted" suffix variables derived from anytype params
            if (std.mem.endsWith(u8, base_name, "_converted")) {
                const original_name = base_name[0 .. base_name.len - "_converted".len];
                if (self.anytype_params.contains(original_name)) {
                    // Converted anytype has known class type, check if field is primitive
                    const var_type = self.type_inferrer.getScopedVar(base_name) orelse
                        self.type_inferrer.var_types.get(base_name);
                    if (var_type) |vt| {
                        if (vt == .class_instance) {
                            // Class instance - check field type in class registry
                            const class_name = vt.class_instance;
                            if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                                if (class_info.fields.get(attr.attr)) |field_type| {
                                    // Field has a known type - only uncertain if pyvalue/unknown
                                    return field_type == .pyvalue or field_type == .unknown;
                                }
                            }
                            // Field not found - assume NOT uncertain
                            return false;
                        }
                    }
                    // If not registered as class_instance, fall through to check field type
                }
            }

            // For other variable access, check if the variable is a known class instance
            const var_type = self.type_inferrer.getScopedVar(base_name) orelse
                self.type_inferrer.var_types.get(base_name);
            if (var_type) |vt| {
                if (vt == .class_instance) {
                    // Class instance - check field type in class registry
                    const class_name = vt.class_instance;
                    if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                        if (class_info.fields.get(attr.attr)) |field_type| {
                            // Field has a known type - only uncertain if pyvalue/unknown
                            return field_type == .pyvalue or field_type == .unknown;
                        }
                    }
                    // Field not found - assume NOT uncertain
                    return false;
                }
                if (vt == .unknown) {
                    // Unknown type attributes are uncertain
                    return true;
                }
            }
        }

        // For other attribute access, use type inference
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
