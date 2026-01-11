//! Comprehension condition generation - truthiness conversion for if clauses
//! Split from comprehensions.zig for maintainability

const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const hashmap_helper = @import("utils.hashmap_helper");
const zig_keywords = @import("utils.zig_keywords");

// MIGRATED TO ZIGBUILDER

// Trait imports for type checking
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const operator_traits = @import("../../../analysis/traits/operator_traits.zig");

const comp_utils = @import("comp_utils.zig");
const comp_expr_subs = @import("comp_expr_subs.zig");

// === Structured emission helpers ===

/// Helper context for truthiness calls with substitutions
const TruthySubsCtx = struct {
    cond: ast.Node,
    subs: *const hashmap_helper.StringHashMap([]const u8),
};

/// Helper: emit runtime.pyTruthy(genExprWithSubs(cond))
fn emitPyTruthyWithSubs(self: *NativeCodegen, cond: ast.Node, subs: *const hashmap_helper.StringHashMap([]const u8)) CodegenError!void {
    try self.emitCallCtx("runtime.pyTruthy", TruthySubsCtx{ .cond = cond, .subs = subs }, struct {
        pub fn f(s: *NativeCodegen, ctx: TruthySubsCtx) CodegenError!void {
            try comp_expr_subs.genExprWithSubs(s, ctx.cond, ctx.subs);
        }
    }.f);
}

/// Helper: emit runtime.toBool(genExprWithSubs(cond))
fn emitToBoolWithSubs(self: *NativeCodegen, cond: ast.Node, subs: *const hashmap_helper.StringHashMap([]const u8)) CodegenError!void {
    try self.emitCallCtx("runtime.toBool", TruthySubsCtx{ .cond = cond, .subs = subs }, struct {
        pub fn f(s: *NativeCodegen, ctx: TruthySubsCtx) CodegenError!void {
            try comp_expr_subs.genExprWithSubs(s, ctx.cond, ctx.subs);
        }
    }.f);
}

/// Helper: emit runtime.pyTruthy(genExpr(cond))
fn emitPyTruthy(self: *NativeCodegen, cond: ast.Node) CodegenError!void {
    try self.emitCallCtx("runtime.pyTruthy", cond, struct {
        pub fn f(s: *NativeCodegen, c: ast.Node) CodegenError!void {
            const genExpr = @import("../expressions.zig").genExpr;
            try genExpr(s, c);
        }
    }.f);
}

/// Helper: emit runtime.toBool(genExpr(cond))
fn emitToBool(self: *NativeCodegen, cond: ast.Node) CodegenError!void {
    try self.emitCallCtx("runtime.toBool", cond, struct {
        pub fn f(s: *NativeCodegen, c: ast.Node) CodegenError!void {
            const genExpr = @import("../expressions.zig").genExpr;
            try genExpr(s, c);
        }
    }.f);
}

/// Emit a for-loop target variable name (raw identifier, no closure transformation)
/// For-loop targets create new local bindings, not references to captured variables
/// Checks for shadowing against imported modules and function parameters, uses unique names if needed
/// Returns the mangled name if shadowing occurred, null otherwise
pub fn emitForLoopTarget(self: *NativeCodegen, target: ast.Node, unique_id: usize) CodegenError!?[]const u8 {
    switch (target) {
        .name => |n| {
            const var_name = n.id;
            // Get the Pass 2.5 name for this loop variable (if available)
            // This ensures declaration matches references which use getZigName()
            const zig_name = self.getZigName(var_name);

            // Check if this name shadows an imported module or a declared variable (like function params)
            // In Zig, for-loop captures cannot shadow outer scope variables
            const shadows_import = self.imported_modules.contains(var_name);
            const shadows_param = self.isDeclared(var_name);
            if (shadows_import or shadows_param) {
                // Use unique capture name to avoid shadowing imported module or function parameter
                const mangled_name = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}__", .{ var_name, unique_id });
                try self.emit(mangled_name);
                return mangled_name;
            } else {
                // Use Pass 2.5 name to match what references will use via getZigName()
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), zig_name);
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
        try emitPyTruthyWithSubs(self, if_cond, subs);
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
            try emitToBoolWithSubs(self, if_cond, subs);
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
        try emitPyTruthy(self, if_cond);
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
            try emitToBool(self, if_cond);
        }
    }
}
