//! Comprehension condition generation - truthiness conversion for if clauses
//! Split from comprehensions.zig for maintainability

const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const hashmap_helper = @import("utils.hashmap_helper");
const zig_keywords = @import("utils.zig_keywords");

// Trait imports for type checking
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const operator_traits = @import("../../../analysis/traits/operator_traits.zig");

const comp_utils = @import("comp_utils.zig");
const comp_expr_subs = @import("comp_expr_subs.zig");

/// Emit a for-loop target variable name (raw identifier, no closure transformation)
/// For-loop targets create new local bindings, not references to captured variables
/// Checks for shadowing against imported modules and uses unique names if needed
/// Returns the mangled name if shadowing occurred, null otherwise
pub fn emitForLoopTarget(self: *NativeCodegen, target: ast.Node, unique_id: usize) CodegenError!?[]const u8 {
    switch (target) {
        .name => |n| {
            const var_name = n.id;
            // Check if this name shadows an imported module
            const shadows_import = self.imported_modules.contains(var_name);
            if (shadows_import) {
                // Use unique capture name to avoid shadowing imported module
                const mangled_name = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}__", .{ var_name, unique_id });
                try self.emit(mangled_name);
                return mangled_name;
            } else {
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                return null;
            }
        },
        else => {
            // Fallback for complex targets - shouldn't happen in practice
            // since tuple targets are handled separately
            const parent = @import("../expressions.zig");
            try parent.genExpr(self, target);
            return null;
        },
    }
}

/// Generate a truthiness-wrapped condition for comprehension `if` clauses
/// Python truthiness: 0, "", [], {}, None are False; everything else is True
pub fn genComprehensionCondition(
    self: *NativeCodegen,
    if_cond: ast.Node,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
    // Check condition type to determine if we need truthiness conversion
    const cond_type = self.type_inferrer.inferExpr(if_cond) catch .unknown;

    // For comparisons and boolean expressions, no conversion needed
    const is_already_bool = switch (if_cond) {
        .compare => true,
        .boolop => true,
        .unaryop => |u| u.op == .Not,
        .call => |c| blk: {
            if (c.func.* == .name) {
                break :blk comp_utils.BoolReturningBuiltins.has(c.func.name.id);
            }
            break :blk false;
        },
        else => type_traits.isBoolean(cond_type),
    };

    if (is_already_bool) {
        // Boolean expression - use directly
        try comp_expr_subs.genExprWithSubs(self, if_cond, subs);
    } else if (type_traits.isUnknown(cond_type) or cond_type == .pyvalue) {
        // Two-Flow: Unknown/PyValue type - use runtime truthiness check
        try self.emit("runtime.pyTruthy(");
        try comp_expr_subs.genExprWithSubs(self, if_cond, subs);
        try self.emit(")");
    } else {
        // Other types (int, float, string, list, etc.) - use runtime.toBool
        // This handles Python truthiness semantics (0 is false, "" is false, [] is false, etc.)
        // Special case: modulo should use proper operator semantics (not pyMod which returns string)
        if (if_cond == .binop and if_cond.binop.op == .Mod) {
            const left_type = self.type_inferrer.inferExpr(if_cond.binop.left.*) catch .unknown;
            const right_type = self.type_inferrer.inferExpr(if_cond.binop.right.*) catch .unknown;
            const semantics = operator_traits.getModuloSemantics(left_type, right_type);
            switch (semantics) {
                .zig_native => {
                    // Integer modulo - use @mod
                    try self.emit("runtime.toBool(@mod(");
                    try comp_expr_subs.genExprWithSubs(self, if_cond.binop.left.*, subs);
                    try self.emit(", ");
                    try comp_expr_subs.genExprWithSubs(self, if_cond.binop.right.*, subs);
                    try self.emit("))");
                },
                .python_floored => {
                    // Float modulo - use Python semantics
                    try self.emit("runtime.toBool(runtime.pyFloatMod(");
                    try comp_expr_subs.genExprWithSubs(self, if_cond.binop.left.*, subs);
                    try self.emit(", ");
                    try comp_expr_subs.genExprWithSubs(self, if_cond.binop.right.*, subs);
                    try self.emit("))");
                },
                .runtime_dispatch => {
                    // Unknown types - use runtime helper
                    try self.emit("runtime.toBool(runtime.moduloRuntime(");
                    try comp_expr_subs.genExprWithSubs(self, if_cond.binop.left.*, subs);
                    try self.emit(", ");
                    try comp_expr_subs.genExprWithSubs(self, if_cond.binop.right.*, subs);
                    try self.emit("))");
                },
            }
        } else {
            try self.emit("runtime.toBool(");
            try comp_expr_subs.genExprWithSubs(self, if_cond, subs);
            try self.emit(")");
        }
    }
}

/// Generate a truthiness-wrapped condition without substitutions
/// For dictcomp and genexp which don't use variable substitutions
pub fn genComprehensionConditionNoSubs(
    self: *NativeCodegen,
    if_cond: ast.Node,
) CodegenError!void {
    const genExpr = @import("../expressions.zig").genExpr;

    // Check condition type to determine if we need truthiness conversion
    const cond_type = self.type_inferrer.inferExpr(if_cond) catch .unknown;

    // For comparisons and boolean expressions, no conversion needed
    const is_already_bool = switch (if_cond) {
        .compare => true,
        .boolop => true,
        .unaryop => |u| u.op == .Not,
        .call => |c| blk: {
            if (c.func.* == .name) {
                break :blk comp_utils.BoolReturningBuiltins.has(c.func.name.id);
            }
            break :blk false;
        },
        else => type_traits.isBoolean(cond_type),
    };

    if (is_already_bool) {
        // Boolean expression - use directly
        try genExpr(self, if_cond);
    } else if (type_traits.isUnknown(cond_type) or cond_type == .pyvalue) {
        // Two-Flow: Unknown/PyValue type - use runtime truthiness check
        try self.emit("runtime.pyTruthy(");
        try genExpr(self, if_cond);
        try self.emit(")");
    } else {
        // Other types (int, float, string, list, etc.) - use runtime.toBool
        // This handles Python truthiness semantics (0 is false, "" is false, [] is false, etc.)
        // Special case: modulo should use @mod to return int (not pyMod which returns string)
        if (if_cond == .binop and if_cond.binop.op == .Mod) {
            try self.emit("runtime.toBool(@mod(");
            try genExpr(self, if_cond.binop.left.*);
            try self.emit(", ");
            try genExpr(self, if_cond.binop.right.*);
            try self.emit("))");
        } else {
            try self.emit("runtime.toBool(");
            try genExpr(self, if_cond);
            try self.emit(")");
        }
    }
}
