/// List and dict comprehension code generation
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const hashmap_helper = @import("utils.hashmap_helper");
const shared = @import("../shared_maps.zig");
const BinOpStrings = shared.BinOpStrings;
const function_traits = @import("analysis.function_traits");
const zig_keywords = @import("utils.zig_keywords");

// Trait imports for type checking
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const string_traits = @import("../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../analysis/traits/container_traits.zig");
const operator_traits = @import("../../../analysis/traits/operator_traits.zig");

/// Builtins that return int for type inference
const IntReturningBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "len", {} }, .{ "int", {} }, .{ "ord", {} },
});

/// Emit a for-loop target variable name (raw identifier, no closure transformation)
/// For-loop targets create new local bindings, not references to captured variables
fn emitForLoopTarget(self: *NativeCodegen, target: ast.Node) CodegenError!void {
    switch (target) {
        .name => |n| try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), n.id),
        else => {
            // Fallback for complex targets - shouldn't happen in practice
            // since tuple targets are handled separately
            const parent = @import("../expressions.zig");
            try parent.genExpr(self, target);
        },
    }
}

/// Builtins that return bool for type inference
const BoolReturningBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "isinstance", {} }, .{ "callable", {} }, .{ "hasattr", {} }, .{ "bool", {} },
});

/// Generate a truthiness-wrapped condition for comprehension `if` clauses
/// Python truthiness: 0, "", [], {}, None are False; everything else is True
fn genComprehensionCondition(
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
                break :blk BoolReturningBuiltins.has(c.func.name.id);
            }
            break :blk false;
        },
        else => type_traits.isBoolean(cond_type),
    };

    if (is_already_bool) {
        // Boolean expression - use directly
        try genExprWithSubs(self, if_cond, subs);
    } else if (type_traits.isUnknown(cond_type) or cond_type == .pyvalue) {
        // Two-Flow: Unknown/PyValue type - use runtime truthiness check
        try self.emit("runtime.pyTruthy(");
        try genExprWithSubs(self, if_cond, subs);
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
                    try genExprWithSubs(self, if_cond.binop.left.*, subs);
                    try self.emit(", ");
                    try genExprWithSubs(self, if_cond.binop.right.*, subs);
                    try self.emit("))");
                },
                .python_floored => {
                    // Float modulo - use Python semantics
                    try self.emit("runtime.toBool(runtime.pyFloatMod(");
                    try genExprWithSubs(self, if_cond.binop.left.*, subs);
                    try self.emit(", ");
                    try genExprWithSubs(self, if_cond.binop.right.*, subs);
                    try self.emit("))");
                },
                .runtime_dispatch => {
                    // Unknown types - use runtime helper
                    try self.emit("runtime.toBool(runtime.moduloRuntime(");
                    try genExprWithSubs(self, if_cond.binop.left.*, subs);
                    try self.emit(", ");
                    try genExprWithSubs(self, if_cond.binop.right.*, subs);
                    try self.emit("))");
                },
            }
        } else {
            try self.emit("runtime.toBool(");
            try genExprWithSubs(self, if_cond, subs);
            try self.emit(")");
        }
    }
}

/// Generate a truthiness-wrapped condition without substitutions
/// For dictcomp and genexp which don't use variable substitutions
fn genComprehensionConditionNoSubs(
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
                break :blk BoolReturningBuiltins.has(c.func.name.id);
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

/// Generate expression with variable substitutions for comprehensions
fn genExprWithSubs(
    self: *NativeCodegen,
    expr: ast.Node,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
    switch (expr) {
        .name => |n| {
            // Check if this name should be substituted
            if (subs.get(n.id)) |sub_name| {
                try self.emit(sub_name);
            } else {
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), n.id);
            }
        },
        .binop => |b| {
            // Use @mod for modulo to handle signed integers properly
            if (b.op == .Mod) {
                try self.emit("@mod(");
                try genExprWithSubs(self, b.left.*, subs);
                try self.emit(", ");
                try genExprWithSubs(self, b.right.*, subs);
                try self.emit(")");
            } else if (b.op == .Pow) {
                // Zig doesn't have ** operator, use std.math.pow
                try self.emit("std.math.pow(i64, ");
                try genExprWithSubs(self, b.left.*, subs);
                try self.emit(", ");
                try genExprWithSubs(self, b.right.*, subs);
                try self.emit(")");
            } else if (b.op == .FloorDiv) {
                // Floor division uses @divFloor for Python semantics
                try self.emit("@divFloor(");
                try genExprWithSubs(self, b.left.*, subs);
                try self.emit(", ");
                try genExprWithSubs(self, b.right.*, subs);
                try self.emit(")");
            } else if (b.op == .LShift or b.op == .RShift) {
                // Bit shifts need RHS cast to u6 (Zig requires unsigned shift amount)
                try self.emit("(");
                try genExprWithSubs(self, b.left.*, subs);
                try self.emit(if (b.op == .LShift) " << " else " >> ");
                try self.emit("@as(u6, @intCast(@mod(");
                try genExprWithSubs(self, b.right.*, subs);
                try self.emit(", 64))))");
            } else {
                try self.emit("(");
                try genExprWithSubs(self, b.left.*, subs);
                try self.emit(BinOpStrings.get(@tagName(b.op)) orelse " ? ");
                try genExprWithSubs(self, b.right.*, subs);
                try self.emit(")");
            }
        },
        .constant => |c| {
            // Use proper constant generation to handle string escaping correctly
            const constants = @import("constants.zig");
            try constants.genConstant(self, c);
        },
        .call => |c| {
            // For calls, we need to use the full call dispatch for proper handling
            // But we also need substitutions for the arguments
            // Check if this is a simple local function call (not builtin/stdlib)
            const builtins_dispatch = @import("../dispatch/builtins.zig");
            const is_simple_call = if (c.func.* == .name) blk: {
                const func_name = c.func.name.id;
                // If it's a builtin, use full dispatch
                if (builtins_dispatch.BuiltinMap.get(func_name) != null) break :blk false;
                // If it's a known type/class, use full dispatch
                if (std.mem.eql(u8, func_name, "list") or
                    std.mem.eql(u8, func_name, "dict") or
                    std.mem.eql(u8, func_name, "set") or
                    std.mem.eql(u8, func_name, "tuple") or
                    std.mem.eql(u8, func_name, "str") or
                    std.mem.eql(u8, func_name, "int") or
                    std.mem.eql(u8, func_name, "float") or
                    std.mem.eql(u8, func_name, "bool"))
                    break :blk false;
                // Simple local function call
                break :blk true;
            } else false;

            if (is_simple_call) {
                const func_name = c.func.name.id;
                // Check if this is a closure that needs .call() syntax
                if (self.closure_vars.contains(func_name)) {
                    // Use renamed name if available (for closures that shadow imports)
                    const output_name = self.var_renames.get(func_name) orelse func_name;
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), output_name);
                    try self.emit(".call(");
                    var first = true;
                    for (c.args) |arg| {
                        if (!first) try self.emit(", ");
                        first = false;
                        try genExprWithSubs(self, arg, subs);
                    }
                    try self.emit(")");
                } else {
                    // Simple local function - generate with substituted arguments
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), func_name);
                    try self.emit("(__global_allocator, ");
                    var first = true;
                    for (c.args) |arg| {
                        if (!first) try self.emit(", ");
                        first = false;
                        try genExprWithSubs(self, arg, subs);
                    }
                    try self.emit(")");
                }
            } else if (c.func.* == .attribute) {
                // Attribute call (e.g., random.sample, struct.unpack_from)
                // We need to substitute comprehension variables in the arguments
                // Generate: module.func(arg1_subst, arg2_subst, ...)
                try genExprWithSubs(self, c.func.*, subs);
                try self.emit("(");
                var first_arg = true;
                for (c.args) |arg| {
                    if (!first_arg) try self.emit(", ");
                    first_arg = false;
                    try genExprWithSubs(self, arg, subs);
                }
                try self.emit(")");
            } else if (c.func.* == .name and std.mem.eql(u8, c.func.name.id, "bool") and c.args.len == 1) {
                // bool(x) in comprehension - use runtime.toBool with substitution
                try self.emit("runtime.toBool(");
                try genExprWithSubs(self, c.args[0], subs);
                try self.emit(")");
            } else if (c.func.* == .name and std.mem.eql(u8, c.func.name.id, "int") and c.args.len >= 1) {
                // int(x) or int(x, base) in comprehension - cast with substitution
                try self.emit("@as(i64, @intCast(");
                try genExprWithSubs(self, c.args[0], subs);
                try self.emit("))");
            } else if (c.func.* == .name and std.mem.eql(u8, c.func.name.id, "str") and c.args.len == 1) {
                // str(x) in comprehension - use runtime.format with substitution
                try self.emit("runtime.format(\"{}\", .{");
                try genExprWithSubs(self, c.args[0], subs);
                try self.emit("})");
            } else if (c.func.* == .name and std.mem.eql(u8, c.func.name.id, "len") and c.args.len == 1) {
                // len(x) in comprehension - use .len with substitution
                try self.emit("@as(i64, @intCast((");
                try genExprWithSubs(self, c.args[0], subs);
                try self.emit(").len))");
            } else if (c.func.* == .name and std.mem.eql(u8, c.func.name.id, "abs") and c.args.len == 1) {
                // abs(x) in comprehension - use @abs with substitution
                try self.emit("@abs(");
                try genExprWithSubs(self, c.args[0], subs);
                try self.emit(")");
            } else if (c.func.* == .name and std.mem.eql(u8, c.func.name.id, "float") and c.args.len == 1) {
                // float(x) in comprehension - use runtime.floatBuiltinCall with substitution
                try self.emit("(runtime.floatBuiltinCall(");
                try genExprWithSubs(self, c.args[0], subs);
                try self.emit(", .{}) catch 0.0)");
            } else if (c.func.* == .name and std.mem.eql(u8, c.func.name.id, "complex") and c.args.len >= 1) {
                // complex(x) or complex(x, y) in comprehension - use runtime.PyComplex.create
                try self.emit("runtime.PyComplex.create(");
                try genExprWithSubs(self, c.args[0], subs);
                try self.emit(", ");
                if (c.args.len >= 2) {
                    try genExprWithSubs(self, c.args[1], subs);
                } else {
                    try self.emit("0.0");
                }
                try self.emit(")");
            } else if (c.func.* == .name and std.mem.eql(u8, c.func.name.id, "bytes") and c.args.len > 0) {
                // Special case: bytes([x]) in comprehension needs substitution for list elements
                // bytes([x]) creates a single-byte bytes object from integer x
                // We need to generate the list with proper variable substitution
                if (c.args[0] == .list and c.args[0].list.elts.len == 1) {
                    // bytes([x]) -> &[_]u8{@intCast(x)} for single element
                    try self.emit("&[_]u8{@intCast(");
                    try genExprWithSubs(self, c.args[0].list.elts[0], subs);
                    try self.emit(")}");
                } else {
                    // General case: generate list with substitution
                    try self.emit("blk: { var _bytes_list = std.ArrayListUnmanaged(u8){}; ");
                    if (c.args[0] == .list) {
                        for (c.args[0].list.elts) |elt| {
                            try self.emit("try _bytes_list.append(__global_allocator, @intCast(");
                            try genExprWithSubs(self, elt, subs);
                            try self.emit(")); ");
                        }
                    } else {
                        try self.emit("for ((");
                        try genExprWithSubs(self, c.args[0], subs);
                        try self.emit(").items) |_item| try _bytes_list.append(__global_allocator, @intCast(_item)); ");
                    }
                    try self.emit("break :blk _bytes_list.items; }");
                }
            } else if (c.func.* == .name and (std.mem.eql(u8, c.func.name.id, "set") or std.mem.eql(u8, c.func.name.id, "frozenset")) and c.args.len == 1) {
                // set([x]) or frozenset([x]) in comprehension - needs argument substitution
                // Generate: set_blk: { var _set = std.AutoHashMap(i64, void).init(__global_allocator); for (<arg>) |_item| { try _set.put(_item, {}); } break :set_blk _set; }
                const set_label = self.block_label_counter;
                self.block_label_counter += 1;
                try self.output.writer(self.allocator).print("set_{d}: {{\n", .{set_label});
                self.indent();
                try self.emitIndent();
                try self.emit("var _set = std.AutoHashMap(i64, void).init(__global_allocator);\n");

                // Check if arg is a list literal - iterate over elements
                if (c.args[0] == .list) {
                    const list_elts = c.args[0].list.elts;
                    for (list_elts) |elt| {
                        try self.emitIndent();
                        try self.emit("try _set.put(");
                        try genExprWithSubs(self, elt, subs);
                        try self.emit(", {});\n");
                    }
                } else {
                    // General case - iterate over the expression
                    try self.emitIndent();
                    try self.emit("for (");
                    try genExprWithSubs(self, c.args[0], subs);
                    try self.emit(") |_item| {\n");
                    self.indent();
                    try self.emitIndent();
                    try self.emit("try _set.put(_item, {});\n");
                    self.dedent();
                    try self.emitIndent();
                    try self.emit("}\n");
                }
                try self.emitIndent();
                try self.output.writer(self.allocator).print("break :set_{d} _set;\n", .{set_label});
                self.dedent();
                try self.emitIndent();
                try self.emit("}");
            } else if (c.func.* == .name and std.mem.eql(u8, c.func.name.id, "bytearray") and c.args.len > 0) {
                // bytearray(n) in comprehension - allocates n zero-filled bytes
                // Generate: blk_ba: { const _n: usize = @intCast(<arg>); const _buf = try __global_allocator.alloc(u8, _n); @memset(_buf, 0); break :blk_ba _buf; }
                try self.emit("blk_ba: { const _n: usize = @intCast(");
                try genExprWithSubs(self, c.args[0], subs);
                try self.emit("); const _buf = try __global_allocator.alloc(u8, _n); @memset(_buf, 0); break :blk_ba _buf; }");
            } else {
                // Generic builtin/call handling with substitutions
                // Generate the call using dispatch but with substituted arguments
                if (c.func.* == .name) {
                    const func_name = c.func.name.id;
                    // Use builtin dispatch for the function, but substitute arguments
                    const builtins = @import("../dispatch/builtins.zig");
                    if (builtins.BuiltinMap.get(func_name)) |handler| {
                        // For builtins, we need to generate with proper patterns
                        // Create substituted argument expressions by generating to temp then referencing
                        // For now, use genExpr but recursively handle argument substitutions
                        // This is a fallback - specific builtins should be added above for proper handling
                        _ = handler;
                    }
                    // Fallback: generate call with substituted args
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), func_name);
                    try self.emit("(");
                    var first_arg = true;
                    for (c.args) |arg| {
                        if (!first_arg) try self.emit(", ");
                        first_arg = false;
                        try genExprWithSubs(self, arg, subs);
                    }
                    try self.emit(")");
                } else {
                    // Non-name func (lambda, etc.) - fall back to genExpr
                    const parent = @import("../expressions.zig");
                    try parent.genExpr(self, expr);
                }
            }
        },
        .list => |l| {
            // Handle list literals with substitution
            // Python: [x] in comprehension element -> generate inline array or ArrayList
            // For single-element lists like bytes([x]), generate Zig array: &[_]u8{x}
            try self.emit("list_");
            const list_id = self.output.items.len;
            try self.output.writer(self.allocator).print("{d}: {{\n", .{list_id});
            self.indent();
            try self.emitIndent();
            try self.emit("var _list = std.ArrayListUnmanaged(i64){};\n");
            for (l.elts) |elt| {
                try self.emitIndent();
                try self.emit("try _list.append(__global_allocator, ");
                try genExprWithSubs(self, elt, subs);
                try self.emit(");\n");
            }
            try self.emitIndent();
            try self.output.writer(self.allocator).print("break :list_{d} _list;\n", .{list_id});
            self.dedent();
            try self.emitIndent();
            try self.emit("}");
        },
        .subscript => |sub| {
            // Handle slicing/indexing with substitution: mem[i:i+itemsize]
            switch (sub.slice) {
                .slice => |sr| {
                    // It's a slice - generate slice with substitutions
                    const label_id = self.block_label_counter;
                    self.block_label_counter += 1;
                    try self.output.writer(self.allocator).print("slice_{d}: {{ const __s = ", .{label_id});
                    try genExprWithSubs(self, sub.value.*, subs);
                    try self.emit("; const __start = @min(");
                    if (sr.lower) |lower| {
                        try genExprWithSubs(self, lower.*, subs);
                    } else {
                        try self.emit("0");
                    }
                    try self.emit(", __s.len); const __end = @min(");
                    if (sr.upper) |upper| {
                        try genExprWithSubs(self, upper.*, subs);
                    } else {
                        try self.emit("__s.len");
                    }
                    try self.output.writer(self.allocator).print(", __s.len); break :slice_{d} if (__start < __end) __s[__start..__end] else \"\"; }}", .{label_id});
                },
                .index => |idx| {
                    // Simple index with substitution
                    try genExprWithSubs(self, sub.value.*, subs);
                    try self.emit("[");
                    try genExprWithSubs(self, idx.*, subs);
                    try self.emit("]");
                },
            }
        },
        .unaryop => |u| {
            // Handle unary operations with substitution
            switch (u.op) {
                .USub => {
                    try self.emit("(-");
                    try genExprWithSubs(self, u.operand.*, subs);
                    try self.emit(")");
                },
                .UAdd => {
                    try self.emit("(+");
                    try genExprWithSubs(self, u.operand.*, subs);
                    try self.emit(")");
                },
                .Not => {
                    try self.emit("(!");
                    try genExprWithSubs(self, u.operand.*, subs);
                    try self.emit(")");
                },
                .Invert => {
                    try self.emit("(~");
                    try genExprWithSubs(self, u.operand.*, subs);
                    try self.emit(")");
                },
            }
        },
        .attribute => |a| {
            // Handle attribute access with substitution: x.attr
            try genExprWithSubs(self, a.value.*, subs);
            try self.emit(".");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), a.attr);
        },
        .tuple => |t| {
            // Handle tuple with substitution - use named fields for struct compatibility
            try self.emit(".{ ");
            for (t.elts, 0..) |elt, idx| {
                if (idx > 0) try self.emit(", ");
                try self.output.writer(self.allocator).print(".@\"{d}\" = ", .{idx});
                try genExprWithSubs(self, elt, subs);
            }
            try self.emit(" }");
        },
        .if_expr => |ie| {
            // Handle ternary: x if cond else y
            // Check condition type - need to convert non-bool to bool
            const cond_type = self.type_inferrer.inferExpr(ie.condition.*) catch .unknown;

            try self.emit("(if (");
            if (type_traits.isIntegral(cond_type) or type_traits.isFloating(cond_type)) {
                // Integer/float condition - check != 0
                try genExprWithSubs(self, ie.condition.*, subs);
                try self.emit(" != 0");
            } else if (type_traits.isUnknown(cond_type) or cond_type == .pyvalue) {
                // Two-Flow: Unknown/PyValue type - use runtime truthiness check
                try self.emit("runtime.pyTruthy(");
                try genExprWithSubs(self, ie.condition.*, subs);
                try self.emit(")");
            } else {
                // Boolean or other type - use directly
                try genExprWithSubs(self, ie.condition.*, subs);
            }
            try self.emit(") ");
            try genExprWithSubs(self, ie.body.*, subs);
            try self.emit(" else ");
            try genExprWithSubs(self, ie.orelse_value.*, subs);
            try self.emit(")");
        },
        .compare => |cmp| {
            // For complex comparisons (in, not in, is, is not) OR chained comparisons (a < b < c),
            // delegate to main genExpr which handles these properly.
            // Zig doesn't support chained comparisons, so 0 < x < 3 must become ((0 < x) and (x < 3))
            const needs_delegation = blk: {
                // Chained comparisons need special handling
                if (cmp.ops.len > 1) break :blk true;
                // Complex operators need special handling
                for (cmp.ops) |op| {
                    if (op == .In or op == .NotIn or op == .Is or op == .IsNot) {
                        break :blk true;
                    }
                }
                break :blk false;
            };

            if (needs_delegation) {
                // Apply substitutions first by setting up temp vars, then delegate
                // For now, just delegate directly - the loop var will be found
                const parent = @import("../expressions.zig");
                try parent.genExpr(self, expr);
            } else {
                // Simple single-operator comparisons can be handled inline with substitution
                try self.emit("(");
                try genExprWithSubs(self, cmp.left.*, subs);
                for (cmp.ops, 0..) |op, idx| {
                    const op_str = switch (op) {
                        .Eq => " == ",
                        .NotEq => " != ",
                        .Lt => " < ",
                        .LtEq => " <= ",
                        .Gt => " > ",
                        .GtEq => " >= ",
                        else => " == ", // Fallback (shouldn't reach here)
                    };
                    try self.emit(op_str);
                    try genExprWithSubs(self, cmp.comparators[idx], subs);
                }
                try self.emit(")");
            }
        },
        else => {
            // For other expressions, fallback to regular genExpr
            const parent = @import("../expressions.zig");
            try parent.genExpr(self, expr);
        },
    }
}

/// Generate SIMD-vectorized list comprehension when possible
/// Pattern: [x * 2 for x in range(N)] → SIMD vector operations
fn genSimdListComp(self: *NativeCodegen, listcomp: ast.Node.ListComp, simd: function_traits.SimdInfo) CodegenError!void {
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    const gen = listcomp.generators[0];
    const loop_var = gen.target.name.id;

    // Get range bounds
    const start = simd.range_start orelse 0;
    const end = simd.range_end orelse return genListCompScalar(self, listcomp); // Fallback if dynamic
    const count = end - start;
    if (count <= 0) return genListCompScalar(self, listcomp);

    const vec_width: i64 = simd.vector_width;

    // Generate SIMD block
    try self.emit(try std.fmt.allocPrint(self.allocator, "(simd_{d}: {{\n", .{label_id}));
    self.indent();

    // Allocate result array
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var __result: [{d}]i64 = undefined;\n", .{count});

    // Generate constant vector if needed
    if (simd.op != .neg and simd.op != .square) {
        // Get the constant from the expression
        const c = getConstantFromExpr(listcomp.elt.*, loop_var) orelse 0;
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __c_vec: @Vector({d}, i64) = @splat({d});\n", .{ vec_width, c });
    }

    // Main vectorized loop
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var __i: usize = 0;\n", .{});
    try self.emitIndent();
    try self.output.writer(self.allocator).print("while (__i + {d} <= {d}) : (__i += {d}) {{\n", .{ vec_width, count, vec_width });
    self.indent();

    // Load input vector (for range, it's just sequential indices)
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const __base: @Vector({d}, i64) = .{{ ", .{vec_width});
    var i: i64 = 0;
    while (i < vec_width) : (i += 1) {
        if (i > 0) try self.emit(", ");
        try self.output.writer(self.allocator).print("{d}", .{i});
    }
    try self.emit(" };\n");

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const __idx: @Vector({d}, i64) = __base +% @as(@Vector({d}, i64), @splat(@as(i64, @intCast(__i)) + {d}));\n", .{ vec_width, vec_width, start });

    // Apply operation
    try self.emitIndent();
    const op_str = switch (simd.op) {
        .add => "const __r = __idx +% __c_vec;\n",
        .sub => "const __r = __idx -% __c_vec;\n",
        .mul => "const __r = __idx *% __c_vec;\n",
        .neg => try std.fmt.allocPrint(self.allocator, "const __r = -%__idx;\n", .{}),
        .square => "const __r = __idx *% __idx;\n",
        .bit_and => "const __r = __idx & __c_vec;\n",
        .bit_or => "const __r = __idx | __c_vec;\n",
        .bit_xor => "const __r = __idx ^ __c_vec;\n",
        .shl => "const __r = __idx << @intCast(__c_vec);\n",
        .shr => "const __r = __idx >> @intCast(__c_vec);\n",
        else => "const __r = __idx;\n",
    };
    try self.emit(op_str);

    // Store result
    try self.emitIndent();
    try self.output.writer(self.allocator).print("inline for (0..{d}) |__j| {{\n", .{vec_width});
    self.indent();
    try self.emitIndent();
    try self.emit("__result[__i + __j] = __r[__j];\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // Scalar cleanup for remaining elements
    try self.emitIndent();
    try self.output.writer(self.allocator).print("while (__i < {d}) : (__i += 1) {{\n", .{count});
    self.indent();
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s}: i64 = @as(i64, @intCast(__i)) + {d};\n", .{ loop_var, start });
    try self.emitIndent();
    try self.emit("__result[__i] = ");
    const parent = @import("../expressions.zig");
    try parent.genExpr(self, listcomp.elt.*);
    try self.emit(";\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // Convert to ArrayList for compatibility
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var __list = std.ArrayListUnmanaged(i64){{}};\n", .{});
    try self.emitIndent();
    try self.output.writer(self.allocator).print("try __list.appendSlice(__global_allocator, &__result);\n", .{});
    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :simd_{d} __list;\n", .{label_id});

    self.dedent();
    try self.emitIndent();
    try self.emit("})");
}

/// Get constant value from binop expression
fn getConstantFromExpr(expr: ast.Node, loop_var: []const u8) ?i64 {
    if (expr != .binop) return null;
    const b = expr.binop;
    const left_is_var = b.left.* == .name and std.mem.eql(u8, b.left.name.id, loop_var);
    const right_is_const = b.right.* == .constant and b.right.constant.value == .int;
    const left_is_const = b.left.* == .constant and b.left.constant.value == .int;

    if (left_is_var and right_is_const) return b.right.constant.value.int;
    if (left_is_const) return b.left.constant.value.int;
    return null;
}

/// Scalar fallback for list comprehension
fn genListCompScalar(self: *NativeCodegen, listcomp: ast.Node.ListComp) CodegenError!void {
    // Call the regular implementation
    return genListCompImpl(self, listcomp);
}

/// Generate parallel list comprehension using runtime.parallel
fn genParallelListComp(self: *NativeCodegen, listcomp: ast.Node.ListComp, parallel: function_traits.ParallelInfo, simd: function_traits.SimdInfo) CodegenError!void {
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    const start = simd.range_start orelse 0;
    const end = simd.range_end orelse return genListCompImpl(self, listcomp);

    // Map SimdOp to runtime.parallel.ParallelOp
    const op_name: []const u8 = switch (parallel.op) {
        .add => "add",
        .sub => "sub",
        .mul => "mul",
        .div => "div",
        .neg => "neg",
        .square => "square",
        .bit_and => "bit_and",
        .bit_or => "bit_or",
        .bit_xor => "bit_xor",
        else => return genSimdListComp(self, listcomp, simd), // Fallback to SIMD
    };

    const gen = listcomp.generators[0];
    const loop_var = gen.target.name.id;
    const constant = getConstantFromExpr(listcomp.elt.*, loop_var) orelse 0;

    // Generate parallel execution block
    try self.emit(try std.fmt.allocPrint(self.allocator, "(parallel_{d}: {{\n", .{label_id}));
    self.indent();

    // Call runtime.parallel.parallelRangeMap
    try self.emitIndent();
    try self.output.writer(self.allocator).print(
        "const __slice = try runtime.parallel.parallelRangeMap({d}, {d}, .{s}, {d}, __global_allocator);\n",
        .{ start, end, op_name, constant },
    );

    // Convert to ArrayList for compatibility
    try self.emitIndent();
    try self.emit("var __list = std.ArrayListUnmanaged(i64){};\n");
    try self.emitIndent();
    try self.emit("__list.items = __slice;\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("__list.capacity = {d};\n", .{end - start});

    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :parallel_{d} __list;\n", .{label_id});

    self.dedent();
    try self.emitIndent();
    try self.emit("})");
}

/// Generate list comprehension: [x * 2 for x in range(5)]
/// Generates as imperative loop that builds ArrayList (or SIMD/parallel when possible)
pub fn genListComp(self: *NativeCodegen, listcomp: ast.Node.ListComp) CodegenError!void {
    // Check for SIMD vectorization opportunity
    const simd = function_traits.analyzeListCompForSimd(listcomp);
    if (simd.vectorizable and simd.is_range and simd.range_end != null) {
        const count = (simd.range_end orelse 0) - (simd.range_start orelse 0);

        // Check for parallelization opportunity (large workloads)
        const parallel = function_traits.analyzeListCompForParallel(listcomp);
        if (parallel.parallelizable and parallel.worth_parallelizing and count >= 1024) {
            return genParallelListComp(self, listcomp, parallel, simd);
        }

        // Use SIMD for medium arrays (16-1023 elements)
        if (count >= 16) {
            return genSimdListComp(self, listcomp, simd);
        }
    }

    return genListCompImpl(self, listcomp);
}

/// Internal list comprehension implementation (scalar)
fn genListCompImpl(self: *NativeCodegen, listcomp: ast.Node.ListComp) CodegenError!void {
    // Forward declare genExpr - it's in parent module
    const parent = @import("../expressions.zig");
    const genExpr = parent.genExpr;

    // Generate unique ID for this comprehension to avoid variable shadowing
    const comp_id = self.output.items.len;

    // Get unique block label to avoid nested block conflicts
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Build variable substitution map for this comprehension
    var subs = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer subs.deinit();

    // Track variables added to var_renames for cleanup at the end
    var renamed_vars: std.ArrayListUnmanaged([]const u8) = .{};
    defer renamed_vars.deinit(self.allocator);

    // Check if any generator iterates over PyValue - if so, skip the entire comprehension
    for (listcomp.generators) |gen| {
        const is_range = gen.iter.* == .call and gen.iter.call.func.* == .name and
            std.mem.eql(u8, gen.iter.call.func.name.id, "range");
        if (!is_range) {
            const iter_type = self.type_inferrer.inferExpr(gen.iter.*) catch .unknown;
            // Check if iter_type is PyValue (using tag comparison since there's no trait for it yet)
            if (iter_type == .pyvalue) {
                // PyValue iteration - emit empty PyValue list directly
                try self.emit("std.ArrayListUnmanaged(runtime.PyValue){}\n");
                return;
            }
        }
    }

    // Generate: (comp_N: { ... })
    // Wrap in parentheses to prevent "label:" from being parsed as named argument
    try self.emit(try std.fmt.allocPrint(self.allocator, "(comp_{d}: {{\n", .{label_id}));
    self.indent();

    // Check if element is a lambda - requires special handling for closure type
    // We need to define the closure type ONCE before the loop, then instantiate in the loop
    var lambda_closure_type_name: ?[]const u8 = null;
    var lambda_capture_var_name: ?[]const u8 = null;
    var lambda_capture_field_name: ?[]const u8 = null;  // The struct field name in closure

    if (listcomp.elt.* == .lambda) {
        const lambda = listcomp.elt.lambda;

        // For lambdas that capture loop variables, generate:
        // 1. Capture struct type
        // 2. Implementation function
        // 3. Closure type using runtime.Closure0
        //
        // Two patterns:
        // 1. (lambda i=i: i) - default param captures value
        // 2. (lambda: i) - body references outer scope variable

        // Check if first generator target is referenced in lambda body
        if (listcomp.generators.len > 0) {
            const first_gen = listcomp.generators[0];
            if (first_gen.target.* == .name) {
                const orig_var = first_gen.target.name.id;

                // Check if this variable is used in the lambda (either default or body)
                var is_captured = false;
                var capture_name: []const u8 = orig_var;

                // Check default params (lambda i=i: i)
                if (lambda.args.len > 0 and lambda.args[0].default != null) {
                    is_captured = true;
                    capture_name = lambda.args[0].name;
                }

                // Check body for reference to loop variable (lambda: i)
                if (!is_captured and lambda.body.* == .name) {
                    if (std.mem.eql(u8, lambda.body.name.id, orig_var)) {
                        is_captured = true;
                    }
                }

                if (is_captured) {
                    const mangled_var = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}", .{ orig_var, comp_id });

                    // Pre-add to var_renames so lambda body generation can reference it
                    try subs.put(orig_var, mangled_var);
                    try self.var_renames.put(orig_var, mangled_var);

                    lambda_capture_var_name = mangled_var;
                    lambda_capture_field_name = capture_name;  // Store for element generation

                    // Generate closure type definitions
                    const closure_type_name = try std.fmt.allocPrint(self.allocator, "__ClosureType_{d}", .{label_id});
                    lambda_closure_type_name = closure_type_name;

                    // Generate: const __CaptureType_N = struct { <capture_name>: i64 };
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("const __CaptureType_{d} = struct {{ ", .{label_id});
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), capture_name);
                    try self.emit(": i64 };\n");

                    // Generate impl function wrapped in struct (can't have bare fn in block)
                    // const __ClosureImpl_N = struct { fn call(__cap: __CaptureType_N) i64 { return __cap.<capture_name>; } };
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("const __ClosureImpl_{d} = struct {{ fn call(__cap: __CaptureType_{d}) i64 {{ return __cap.", .{ label_id, label_id });
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), capture_name);
                    try self.emit("; } };\n");

                    // Generate: const __ClosureType_N = runtime.Closure0(__CaptureType_N, i64, __ClosureImpl_N.call);
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("const {s} = runtime.Closure0(__CaptureType_{d}, i64, __ClosureImpl_{d}.call);\n", .{ closure_type_name, label_id, label_id });
                }
            }
        }
    }

    // Determine element type from the expression
    // For tuple elements, we need to generate a struct type dynamically
    const element_type: []const u8 = blk: {
        // Check if we already have a lambda closure type
        if (lambda_closure_type_name) |closure_type| {
            break :blk closure_type;
        }

        // Only access .tuple if it's actually a tuple AST node
        if (listcomp.elt.* == .tuple) {
            // Tuple element like (a,) - need to infer types of each element
            const tuple = listcomp.elt.tuple;
            var type_buf = std.ArrayListUnmanaged(u8){};
            const writer = type_buf.writer(self.allocator);
            writer.writeAll("struct { ") catch {};
            for (tuple.elts, 0..) |elt, idx| {
                if (idx > 0) writer.writeAll(", ") catch {};
                writer.print("@\"{d}\": ", .{idx}) catch {};
                // Infer type of each tuple element
                const tuple_elt_type = self.type_inferrer.inferExpr(elt) catch .unknown;
                const type_str: []const u8 = if (string_traits.isString(tuple_elt_type))
                    "[]const u8"
                else if (type_traits.isBoolean(tuple_elt_type))
                    "bool"
                else if (type_traits.isFloating(tuple_elt_type))
                    "f64"
                else if (tuple_elt_type == .pyvalue)
                    "runtime.PyValue"
                else
                    "i64";
                writer.writeAll(type_str) catch {};
            }
            writer.writeAll(" }") catch {};
            break :blk type_buf.items;
        } else if (listcomp.elt.* == .call) {
            const call = listcomp.elt.call;
            if (call.func.* == .name) {
                const func_name = call.func.name.id;
                if (self.async_functions.contains(func_name)) {
                    break :blk "*runtime.GreenThread";
                }
            } else if (call.func.* == .attribute) {
                // Method call - check if it's a string method that returns string
                const method_name = call.func.attribute.attr;
                if (isStringReturningMethod(method_name)) {
                    break :blk "[]u8";
                }
            }
        } else if (listcomp.elt.* == .constant) {
            // Constant element
            const const_type = self.type_inferrer.inferExpr(listcomp.elt.*) catch .unknown;
            if (string_traits.isString(const_type)) {
                break :blk "[]const u8";
            } else if (string_traits.isBytes(const_type)) {
                break :blk "runtime.builtins.PyBytes";
            } else if (type_traits.isBoolean(const_type)) {
                break :blk "bool";
            } else if (type_traits.isFloating(const_type)) {
                break :blk "f64";
            }
        } else if (listcomp.elt.* == .fstring) {
            // F-string element produces string
            break :blk "[]u8";
        } else if (listcomp.elt.* == .if_expr) {
            // Ternary expression - check body and orelse types
            const if_expr = listcomp.elt.if_expr;
            // Check if both body and orelse are bool literals
            if (if_expr.body.* == .constant and if_expr.orelse_value.* == .constant) {
                const body_const_type = self.type_inferrer.inferExpr(if_expr.body.*) catch .unknown;
                const orelse_const_type = self.type_inferrer.inferExpr(if_expr.orelse_value.*) catch .unknown;
                if (type_traits.isBoolean(body_const_type) and type_traits.isBoolean(orelse_const_type)) {
                    break :blk "bool";
                }
            }
            // Use type inference for the body expression
            const body_type = self.type_inferrer.inferExpr(if_expr.body.*) catch .unknown;
            if (type_traits.isBoolean(body_type)) {
                break :blk "bool";
            } else if (string_traits.isString(body_type)) {
                break :blk "[]const u8";
            } else if (type_traits.isFloating(body_type)) {
                break :blk "f64";
            }
        }
        break :blk "i64";
    };

    // Generate: var __comp_result_N = std.ArrayListUnmanaged(ElementType){};
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var __comp_result_{d} = std.ArrayListUnmanaged(", .{label_id});
    try self.emit(element_type);
    try self.emit("){};\n");

    // Generate nested loops for each generator
    for (listcomp.generators, 0..) |gen, gen_idx| {
        // Check if this is a range() call
        const is_range = gen.iter.* == .call and gen.iter.call.func.* == .name and
            std.mem.eql(u8, gen.iter.call.func.name.id, "range");

        if (is_range) {
            // Generate range loop as while loop
            // Use unique mangled name to avoid shadowing outer variables
            const orig_var_name = gen.target.name.id;
            const args = gen.iter.call.args;

            // Create mangled name and add to substitution map
            const mangled_name = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}", .{ orig_var_name, comp_id });
            try subs.put(orig_var_name, mangled_name);
            // Also add to var_renames so lambdas and other nested expressions can see it
            try self.var_renames.put(orig_var_name, mangled_name);
            // Track for cleanup at end of comprehension
            try renamed_vars.append(self.allocator, orig_var_name);

            // Parse range arguments - handle both constants and variable expressions
            const start_expr: ?ast.Node = if (args.len >= 2) args[0] else null;
            const stop_expr: ast.Node = if (args.len >= 2) args[1] else args[0];
            const step_val: i64 = 1;

            // Generate: var __comp_<orig>_<id>: i64 = <start>;
            try self.emitIndent();
            try self.output.writer(self.allocator).print("var {s}: i64 = ", .{mangled_name});
            if (start_expr) |start| {
                try genExpr(self, start);
            } else {
                try self.emit("0");
            }
            try self.emit(";\n");

            // Generate: while (__comp_<orig>_<id> < <stop>) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("while ({s} < ", .{mangled_name});
            try genExpr(self, stop_expr);
            try self.emit(") {\n");
            self.indent();

            // Defer increment: defer __comp_<orig>_<id> += <step>;
            try self.emitIndent();
            try self.output.writer(self.allocator).print("defer {s} += {d};\n", .{ mangled_name, step_val });
        } else {
            // Regular iteration - check if source is constant array, ArrayList, or anytype param
            // (PyValue iteration is already handled upfront before the comprehension block is opened)
            const is_direct_iterable = blk: {
                // String literals are directly iterable (they're Zig arrays)
                if (gen.iter.* == .constant) {
                    const iter_const_type = self.type_inferrer.inferExpr(gen.iter.*) catch .unknown;
                    if (string_traits.isString(iter_const_type)) break :blk true;
                }
                if (gen.iter.* == .name) {
                    const var_name = gen.iter.name.id;
                    // Const array variables can be iterated directly
                    if (self.isArrayVar(var_name)) break :blk true;
                    // anytype parameters should also be iterated directly (no .items)
                    if (self.anytype_params.contains(var_name)) break :blk true;
                    // String variables are directly iterable
                    if (self.getVarType(var_name)) |vt| {
                        if (string_traits.isString(vt)) break :blk true;
                    }
                }
                break :blk false;
            };

            try self.emitIndent();
            if (is_direct_iterable) {
                // Constant array variable, string literal, or anytype param - iterate directly
                try self.output.writer(self.allocator).print("const __iter_{d}_{d} = ", .{ label_id, gen_idx });
                try genExpr(self, gen.iter.*);
                try self.emit(";\n");
            } else {
                // ArrayList - use .items
                // First emit the list to an intermediate variable, then access .items
                try self.output.writer(self.allocator).print("const __list_{d}_{d} = ", .{ label_id, gen_idx });
                try genExpr(self, gen.iter.*);
                try self.emit(";\n");
                try self.emitIndent();
                try self.output.writer(self.allocator).print("const __iter_{d}_{d} = __list_{d}_{d}.items;\n", .{ label_id, gen_idx, label_id, gen_idx });
            }

            try self.emitIndent();
            // Check if target is a tuple (for tuple unpacking like `for a, b in zip(...)`)
            const is_tuple_target = switch (gen.target.*) {
                .tuple => true,
                .list => true,
                else => false,
            };
            if (is_tuple_target) {
                // Capture as single variable, unpack inside loop
                try self.output.writer(self.allocator).print("for (__iter_{d}_{d}) |__tuple_{d}_{d}__| {{\n", .{ label_id, gen_idx, label_id, gen_idx });
                self.indent();

                // Unpack tuple elements
                const elements = switch (gen.target.*) {
                    .tuple => |t| t.elts,
                    .list => |l| l.elts,
                    else => &[_]ast.Node{},
                };
                for (elements, 0..) |elt, idx| {
                    try self.emitIndent();
                    if (elt == .name) {
                        const var_name = elt.name.id;
                        // Handle underscore discard pattern
                        if (std.mem.eql(u8, var_name, "_")) {
                            try self.output.writer(self.allocator).print("_ = __tuple_{d}_{d}__.@\"{d}\";\n", .{ label_id, gen_idx, idx });
                        } else {
                            // Check if this would shadow an outer variable - use unique name if so
                            if (self.isDeclared(var_name)) {
                                const renamed = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}", .{ var_name, label_id });
                                // Register rename so references within comprehension use the new name
                                try self.var_renames.put(var_name, renamed);
                                // Track for cleanup at end of comprehension
                                try renamed_vars.append(self.allocator, var_name);
                                try self.output.writer(self.allocator).print("const {s} = __tuple_{d}_{d}__.@\"{d}\";\n", .{ renamed, label_id, gen_idx, idx });
                            } else {
                                try self.output.writer(self.allocator).print("const {s} = __tuple_{d}_{d}__.@\"{d}\";\n", .{ var_name, label_id, gen_idx, idx });
                            }
                        }
                    }
                }
            } else {
                try self.output.writer(self.allocator).print("for (__iter_{d}_{d}) |", .{ label_id, gen_idx });
                try emitForLoopTarget(self, gen.target.*);
                try self.emit("| {\n");
                self.indent();

                // Check if iterator source is a closure list - if so, register loop var as closure
                // This enables x.call() syntax instead of x() when calling the element
                if (gen.target.* == .name) {
                    const target_name = gen.target.name.id;

                    // First, check if iterator is a known closure list variable
                    var is_closure_list = false;
                    if (gen.iter.* == .name) {
                        const iter_var_name = gen.iter.name.id;
                        // Check both original name and renamed name
                        if (self.closure_list_vars.contains(iter_var_name)) {
                            is_closure_list = true;
                        } else if (self.var_renames.get(iter_var_name)) |renamed| {
                            if (self.closure_list_vars.contains(renamed)) {
                                is_closure_list = true;
                            }
                        }
                    }

                    // Also check type inference as fallback
                    if (!is_closure_list) {
                        const iter_type = self.type_inferrer.inferExpr(gen.iter.*) catch .unknown;
                        if (iter_type == .list) {
                            const elem_type = iter_type.list.*;
                            if (elem_type == .closure or elem_type == .function) {
                                is_closure_list = true;
                            }
                        }
                    }

                    if (is_closure_list) {
                        try self.closure_vars.put(target_name, {});
                    }
                }
            }
        }

        // Generate if conditions for this generator
        // Use truthiness conversion for Python semantics (0, "", [], etc. are False)
        for (gen.ifs) |if_cond| {
            try self.emitIndent();
            try self.emit("if (");
            try genComprehensionCondition(self, if_cond, &subs);
            try self.emit(") {\n");
            self.indent();
        }
    }

    // Generate: try __comp_result_N.append(__global_allocator, <elt_expr>);
    try self.emitIndent();
    try self.output.writer(self.allocator).print("try __comp_result_{d}.append(__global_allocator, ", .{label_id});

    // For lambda elements with pre-defined closure type, generate instantiation
    if (lambda_closure_type_name != null and lambda_capture_var_name != null and lambda_capture_field_name != null) {
        // Generate: __ClosureType_N{ .captures = .{ .i = __comp_i_N } }
        try self.output.writer(self.allocator).print("{s}{{ .captures = .{{ .", .{lambda_closure_type_name.?});
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), lambda_capture_field_name.?);
        try self.output.writer(self.allocator).print(" = {s} }} }}", .{lambda_capture_var_name.?});
    } else {
        try genExprWithSubs(self, listcomp.elt.*, &subs);
    }
    try self.emit(");\n");

    // Close all if conditions and for loops
    for (listcomp.generators) |gen| {
        // Close if conditions for this generator
        for (gen.ifs) |_| {
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
        }

        // Close for loop
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    // Generate: break :comp_N __comp_result_N;
    // Return the ArrayList itself (not a slice) so caller can use .items or .append
    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :comp_{d} __comp_result_{d};\n", .{ label_id, label_id });

    self.dedent();
    try self.emitIndent();
    try self.emit("})");

    // Clean up var_renames so outer scope sees original variable names
    for (renamed_vars.items) |var_name| {
        _ = self.var_renames.swapRemove(var_name);
    }
}

pub fn genDictComp(self: *NativeCodegen, dictcomp: ast.Node.DictComp) CodegenError!void {
    // Forward declare genExpr - it's in parent module
    const parent = @import("../expressions.zig");
    const genExpr = parent.genExpr;

    // NOTE: key_is_int is determined AFTER setting up temp vars for loop variables
    // so that type inference can properly resolve function call return types.
    // See below after temp vars are set up.

    // Generate unique ID for this comprehension to avoid variable shadowing
    const comp_id = self.output.items.len;

    // Get unique block label to avoid nested block conflicts
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Infer value type using TypeInferrer
    // First, set up temp vars for loop variables so type inference can see them
    const NativeType = @import("../../../analysis/native_types/core.zig").NativeType;
    var saved_types: [8]struct { name: []const u8, old_type: ?NativeType } = undefined;
    var saved_count: usize = 0;

    for (dictcomp.generators) |gen| {
        if (gen.target.* == .name) {
            const var_name = gen.target.name.id;
            var loop_var_type: NativeType = .{ .int = .bounded }; // Default to i64

            // Check if iterator is range() - gives i64 loop variable
            if (gen.iter.* == .call and gen.iter.call.func.* == .name) {
                const func_name = gen.iter.call.func.name.id;
                if (std.mem.eql(u8, func_name, "range")) {
                    loop_var_type = .{ .int = .bounded };
                }
            }
            // Check if iterator is [*range(n)] pattern - also gives i64
            else if (gen.iter.* == .list) {
                const list = gen.iter.list;
                if (list.elts.len == 1 and list.elts[0] == .starred) {
                    const starred_val = list.elts[0].starred.value;
                    if (starred_val.* == .call and starred_val.call.func.* == .name and
                        std.mem.eql(u8, starred_val.call.func.name.id, "range"))
                    {
                        loop_var_type = .{ .int = .bounded };
                    }
                } else if (list.elts.len > 0 and list.elts[0] != .starred) {
                    // Pattern: for j in [i+1] - list literal with elements
                    // Infer element type directly from first element
                    const elem_type = self.type_inferrer.inferExpr(list.elts[0]) catch .unknown;
                    if (type_traits.isIntegral(elem_type)) {
                        loop_var_type = .{ .int = .bounded };
                    } else {
                        loop_var_type = elem_type;
                    }
                } else {
                    // Empty or other list - infer from list type
                    const iter_type = self.type_inferrer.inferExpr(gen.iter.*) catch .unknown;
                    if (iter_type == .list) {
                        loop_var_type = iter_type.list.*;
                    }
                }
            }
            // Check if iterator is (*range(n),) pattern - also gives i64
            else if (gen.iter.* == .tuple) {
                const tup = gen.iter.tuple;
                if (tup.elts.len == 1 and tup.elts[0] == .starred) {
                    const starred_val = tup.elts[0].starred.value;
                    if (starred_val.* == .call and starred_val.call.func.* == .name and
                        std.mem.eql(u8, starred_val.call.func.name.id, "range"))
                    {
                        loop_var_type = .{ .int = .bounded };
                    }
                }
            }
            // Check if iterator is a listcomp - infer element type
            else if (gen.iter.* == .listcomp) {
                const iter_type = self.type_inferrer.inferExpr(gen.iter.*) catch .unknown;
                if (iter_type == .list) {
                    loop_var_type = iter_type.list.*;
                }
            }
            // For any other iterator, try to infer it
            else {
                const iter_type = self.type_inferrer.inferExpr(gen.iter.*) catch .unknown;
                if (iter_type == .list) {
                    loop_var_type = iter_type.list.*;
                } else if (iter_type == .array) {
                    loop_var_type = iter_type.array.element_type.*;
                }
            }

            if (saved_count < saved_types.len) {
                saved_types[saved_count] = .{
                    .name = var_name,
                    .old_type = self.type_inferrer.putTempVar(var_name, loop_var_type) catch null,
                };
                saved_count += 1;
            }
        }
        // Handle tuple unpacking: for j, k in [(i+1, i+2)]
        else if (gen.target.* == .tuple or gen.target.* == .list) {
            const target_elts = if (gen.target.* == .tuple) gen.target.tuple.elts else gen.target.list.elts;

            // Get first element of iterator to infer tuple element types
            // For [(i+1, i+2)], we infer from (i+1, i+2)
            if (gen.iter.* == .list and gen.iter.list.elts.len > 0) {
                const first_elem = gen.iter.list.elts[0];
                // If first element is a tuple, type each target var from corresponding tuple element
                if (first_elem == .tuple) {
                    const tuple_elts = first_elem.tuple.elts;
                    for (target_elts, 0..) |target_elt, idx| {
                        if (target_elt == .name and idx < tuple_elts.len) {
                            const var_name = target_elt.name.id;
                            const elem_type = self.type_inferrer.inferExpr(tuple_elts[idx]) catch .unknown;
                            const loop_var_type: NativeType = if (type_traits.isIntegral(elem_type))
                                .{ .int = .bounded }
                            else
                                elem_type;

                            if (saved_count < saved_types.len) {
                                saved_types[saved_count] = .{
                                    .name = var_name,
                                    .old_type = self.type_inferrer.putTempVar(var_name, loop_var_type) catch null,
                                };
                                saved_count += 1;
                            }
                        }
                    }
                }
            }
        }
    }

    // Now infer key and value types with loop vars visible
    // Use type inferrer to properly resolve function call return types
    const key_type = self.type_inferrer.inferExpr(dictcomp.key.*) catch .unknown;
    const key_classification = type_traits.getDictKeyType(key_type);

    // Check for target_dict_value_type context (set when assigning to widened dict variable)
    const value_type_str = if (self.target_dict_value_type) |target_type|
        target_type
    else blk: {
        const value_type = self.type_inferrer.inferExpr(dictcomp.value.*) catch .unknown;
        break :blk nativeTypeToZigStr(value_type);
    };

    // NOTE: We keep temp vars active during code generation so that genExpr calls
    // for key/value expressions can access the correct types for loop variables.
    // Temp vars are restored at the end of this function.

    // Generate: (dict_N: { ... })
    // Wrap in parentheses to prevent "label:" from being parsed as named argument
    try self.emit(try std.fmt.allocPrint(self.allocator, "(dict_{d}: {{\n", .{label_id}));
    self.indent();

    // Generate HashMap with properly inferred key/value types
    // Use getDictKeyType to select correct HashMap type based on key type
    try self.emitIndent();
    switch (key_classification) {
        .int => {
            try self.output.writer(self.allocator).print("var __dict_result = std.AutoArrayHashMap(i64, {s}).init(__global_allocator);\n", .{value_type_str});
        },
        .string => {
            try self.output.writer(self.allocator).print("var __dict_result = hashmap_helper.StringHashMap({s}).init(__global_allocator);\n", .{value_type_str});
        },
        .pyvalue => {
            // For unknown/mixed key types, use PyValue keys
            try self.output.writer(self.allocator).print("var __dict_result = hashmap_helper.StringHashMap(runtime.PyValue).init(__global_allocator);\n", .{});
        },
    }

    // Track variables renamed in this comprehension so we can restore them after
    var renamed_vars: std.ArrayListUnmanaged([]const u8) = .{};
    defer renamed_vars.deinit(self.allocator);

    // Generate nested loops for each generator
    for (dictcomp.generators, 0..) |gen, gen_idx| {
        // Check if this is a range() call
        const is_range = gen.iter.* == .call and gen.iter.call.func.* == .name and
            std.mem.eql(u8, gen.iter.call.func.name.id, "range");

        // Check if this is [*range(n)] pattern - list with single starred range call
        const is_starred_range = blk: {
            if (gen.iter.* == .list) {
                const list = gen.iter.list;
                if (list.elts.len == 1 and list.elts[0] == .starred) {
                    const starred_val = list.elts[0].starred.value;
                    if (starred_val.* == .call and starred_val.call.func.* == .name and
                        std.mem.eql(u8, starred_val.call.func.name.id, "range"))
                    {
                        break :blk true;
                    }
                }
            }
            // Also check (*range(n),) tuple pattern
            if (gen.iter.* == .tuple) {
                const tup = gen.iter.tuple;
                if (tup.elts.len == 1 and tup.elts[0] == .starred) {
                    const starred_val = tup.elts[0].starred.value;
                    if (starred_val.* == .call and starred_val.call.func.* == .name and
                        std.mem.eql(u8, starred_val.call.func.name.id, "range"))
                    {
                        break :blk true;
                    }
                }
            }
            break :blk false;
        };

        // Get range args for starred patterns
        const range_args_for_starred: ?[]ast.Node = blk: {
            if (!is_starred_range) break :blk null;
            if (gen.iter.* == .list) {
                break :blk gen.iter.list.elts[0].starred.value.call.args;
            }
            if (gen.iter.* == .tuple) {
                break :blk gen.iter.tuple.elts[0].starred.value.call.args;
            }
            break :blk null;
        };

        if (is_range or is_starred_range) {
            // Generate range loop as while loop
            // Use unique mangled name to avoid shadowing outer variables
            const orig_var_name = gen.target.name.id;
            // Get args from direct range() or from starred range
            const args = if (is_starred_range) range_args_for_starred.? else gen.iter.call.args;

            // Create mangled name and add to var_renames so key/value expressions use it
            const mangled_name = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}", .{ orig_var_name, comp_id });
            try self.var_renames.put(orig_var_name, mangled_name);
            try renamed_vars.append(self.allocator, orig_var_name);

            // Parse range arguments - support non-constant expressions
            var start_val: i64 = 0;
            var stop_val: i64 = 0;
            var step_val: i64 = 1;
            var has_constant_start = false;
            var has_constant_stop = false;
            var has_constant_step = false;

            if (args.len >= 1) {
                if (args.len == 1) {
                    // range(stop)
                    if (args[0] == .constant and args[0].constant.value == .int) {
                        stop_val = args[0].constant.value.int;
                        has_constant_stop = true;
                    }
                } else {
                    // range(start, stop) or range(start, stop, step)
                    if (args[0] == .constant and args[0].constant.value == .int) {
                        start_val = args[0].constant.value.int;
                        has_constant_start = true;
                    }
                    if (args[1] == .constant and args[1].constant.value == .int) {
                        stop_val = args[1].constant.value.int;
                        has_constant_stop = true;
                    }
                    if (args.len >= 3 and args[2] == .constant and args[2].constant.value == .int) {
                        step_val = args[2].constant.value.int;
                        has_constant_step = true;
                    }
                }
            }

            // Generate: var __comp_<orig>_<id>: i64 = <start>;
            try self.emitIndent();
            if (has_constant_start or args.len == 1) {
                try self.output.writer(self.allocator).print("var {s}: i64 = {d};\n", .{ mangled_name, start_val });
            } else {
                try self.output.writer(self.allocator).print("var {s}: i64 = @intCast(", .{mangled_name});
                try genExpr(self, args[0]);
                try self.emit(");\n");
            }

            // Generate: const __stop_<id>: i64 = <stop>;
            if (!has_constant_stop) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("const __stop_{d}_{d}: i64 = @intCast(", .{ label_id, gen_idx });
                if (args.len == 1) {
                    try genExpr(self, args[0]);
                } else {
                    try genExpr(self, args[1]);
                }
                try self.emit(");\n");
            }

            // Generate: while (__comp_<orig>_<id> < <stop>) {
            try self.emitIndent();
            if (has_constant_stop) {
                try self.output.writer(self.allocator).print("while ({s} < {d}) {{\n", .{ mangled_name, stop_val });
            } else {
                try self.output.writer(self.allocator).print("while ({s} < __stop_{d}_{d}) {{\n", .{ mangled_name, label_id, gen_idx });
            }
            self.indent();

            // Defer increment: defer __comp_<orig>_<id> += <step>;
            try self.emitIndent();
            if (has_constant_step or args.len < 3) {
                try self.output.writer(self.allocator).print("defer {s} += {d};\n", .{ mangled_name, step_val });
            } else {
                try self.output.writer(self.allocator).print("defer {s} += @intCast(", .{mangled_name});
                try genExpr(self, args[2]);
                try self.emit(");\n");
            }
        } else {
            // Regular iteration - check if source is constant array, ArrayList, or anytype param
            const is_direct_iterable = blk: {
                // String literals are directly iterable (they're Zig arrays)
                if (gen.iter.* == .constant) {
                    const iter_const_type = self.type_inferrer.inferExpr(gen.iter.*) catch .unknown;
                    if (string_traits.isString(iter_const_type)) break :blk true;
                }
                if (gen.iter.* == .name) {
                    const var_name_inner = gen.iter.name.id;
                    // Const array variables can be iterated directly
                    if (self.isArrayVar(var_name_inner)) break :blk true;
                    // anytype parameters should also be iterated directly (no .items)
                    if (self.anytype_params.contains(var_name_inner)) break :blk true;
                    // String variables are directly iterable
                    if (self.getVarType(var_name_inner)) |vt| {
                        if (string_traits.isString(vt)) break :blk true;
                    }
                }
                break :blk false;
            };

            try self.emitIndent();
            if (is_direct_iterable) {
                // Constant array variable, string literal, or anytype param - iterate directly
                try self.output.writer(self.allocator).print("const __iter_{d}_{d} = ", .{ label_id, gen_idx });
                try genExpr(self, gen.iter.*);
                try self.emit(";\n");
            } else {
                // ArrayList - use .items
                // First emit the list to an intermediate variable, then access .items
                try self.output.writer(self.allocator).print("const __list_{d}_{d} = ", .{ label_id, gen_idx });
                try genExpr(self, gen.iter.*);
                try self.emit(";\n");
                try self.emitIndent();
                try self.output.writer(self.allocator).print("const __iter_{d}_{d} = __list_{d}_{d}.items;\n", .{ label_id, gen_idx, label_id, gen_idx });
            }

            try self.emitIndent();
            // Check if target is a tuple (for tuple unpacking like `for a, b in zip(...)`)
            const is_tuple_target = switch (gen.target.*) {
                .tuple => true,
                .list => true,
                else => false,
            };
            if (is_tuple_target) {
                // Capture as single variable, unpack inside loop
                try self.output.writer(self.allocator).print("for (__iter_{d}_{d}) |__tuple_{d}_{d}__| {{\n", .{ label_id, gen_idx, label_id, gen_idx });
                self.indent();

                // Unpack tuple elements
                const elements = switch (gen.target.*) {
                    .tuple => |t| t.elts,
                    .list => |l| l.elts,
                    else => &[_]ast.Node{},
                };
                for (elements, 0..) |elt, idx| {
                    try self.emitIndent();
                    if (elt == .name) {
                        const var_name = elt.name.id;
                        // Handle underscore discard pattern
                        if (std.mem.eql(u8, var_name, "_")) {
                            try self.output.writer(self.allocator).print("_ = __tuple_{d}_{d}__.@\"{d}\";\n", .{ label_id, gen_idx, idx });
                        } else {
                            // Check if this would shadow an outer variable - use unique name if so
                            if (self.isDeclared(var_name)) {
                                const renamed = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}", .{ var_name, label_id });
                                // Register rename so references within comprehension use the new name
                                try self.var_renames.put(var_name, renamed);
                                try self.output.writer(self.allocator).print("const {s} = __tuple_{d}_{d}__.@\"{d}\";\n", .{ renamed, label_id, gen_idx, idx });
                            } else {
                                try self.output.writer(self.allocator).print("const {s} = __tuple_{d}_{d}__.@\"{d}\";\n", .{ var_name, label_id, gen_idx, idx });
                            }
                        }
                    }
                }
            } else {
                try self.output.writer(self.allocator).print("for (__iter_{d}_{d}) |", .{ label_id, gen_idx });
                try emitForLoopTarget(self, gen.target.*);
                try self.emit("| {\n");
                self.indent();
            }
        }

        // Generate if conditions for this generator
        // Use truthiness conversion for Python semantics (0, "", [], etc. are False)
        for (gen.ifs) |if_cond| {
            try self.emitIndent();
            try self.emit("if (");
            try genComprehensionConditionNoSubs(self, if_cond);
            try self.emit(") {\n");
            self.indent();
        }
    }

    // Generate: try __dict_result.put(<key>, <value>);
    // If using widened PyValue type, wrap value in toPyValue
    try self.emitIndent();
    try self.emit("try __dict_result.put(");
    try genExpr(self, dictcomp.key.*);
    try self.emit(", ");
    if (self.target_dict_value_type != null) {
        // Wrap value in toPyValue for widened dict types
        try self.emit("try runtime.toPyValue(__global_allocator, ");
        try genExpr(self, dictcomp.value.*);
        try self.emit(")");
    } else {
        try genExpr(self, dictcomp.value.*);
    }
    try self.emit(");\n");

    // Close all if conditions and for loops
    for (dictcomp.generators) |gen| {
        // Close if conditions for this generator
        for (gen.ifs) |_| {
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
        }

        // Close for loop
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    // Generate: break :dict_N __dict_result;
    try self.emitIndent();
    try self.emit(try std.fmt.allocPrint(self.allocator, "break :dict_{d} __dict_result;\n", .{label_id}));

    self.dedent();
    try self.emitIndent();
    try self.emit("})");

    // Restore original types for loop variables (temp vars were set up at the start)
    for (saved_types[0..saved_count]) |saved| {
        self.type_inferrer.restoreTempVar(saved.name, saved.old_type);
    }

    // Clean up var_renames so outer scope sees original variable names
    for (renamed_vars.items) |var_name| {
        _ = self.var_renames.swapRemove(var_name);
    }
}

/// Generate generator expression: (x * 2 for x in range(5))
/// For AOT compilation, we treat this as a list comprehension and return the list
/// (Real generators would need lazy evaluation which is complex)
pub fn genGenExp(self: *NativeCodegen, genexp: ast.Node.GenExp) CodegenError!void {
    // Forward declare genExpr - it's in parent module
    const parent = @import("../expressions.zig");
    const genExpr = parent.genExpr;

    // Get unique block label to avoid nested block conflicts
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Generate: (gen_N: { ... })
    // Wrap in parentheses to prevent "label:" from being parsed as named argument
    try self.emit(try std.fmt.allocPrint(self.allocator, "(gen_{d}: {{\n", .{label_id}));
    self.indent();

    // Determine element type from the expression being yielded
    const elem_type = getGenExpElementType(genexp.elt.*);

    // Generate: var __comp_result_N = std.ArrayListUnmanaged(<elem_type>){};
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var __comp_result_{d} = std.ArrayListUnmanaged({s}){{}};\n", .{ label_id, elem_type });

    // Generate nested loops for each generator
    for (genexp.generators, 0..) |gen, gen_idx| {
        // Check if this is a range() call
        const is_range = gen.iter.* == .call and gen.iter.call.func.* == .name and
            std.mem.eql(u8, gen.iter.call.func.name.id, "range");

        if (is_range) {
            // Generate range loop as while loop
            const orig_var_name = gen.target.name.id;
            // Sanitize: "_" -> "_unused" for Zig compatibility
            const var_name = if (std.mem.eql(u8, orig_var_name, "_")) "_unused" else orig_var_name;
            const args = gen.iter.call.args;

            // Check if all range args are constants
            const start_is_const = if (args.len >= 2) args[0] == .constant and args[0].constant.value == .int else true;
            const stop_is_const = if (args.len >= 1) args[if (args.len == 1) 0 else 1] == .constant and args[if (args.len == 1) 0 else 1].constant.value == .int else true;

            if (start_is_const and stop_is_const) {
                // All constants - use static values
                var start_val: i64 = 0;
                var stop_val: i64 = 0;
                const step_val: i64 = 1;

                if (args.len == 1) {
                    stop_val = args[0].constant.value.int;
                } else if (args.len == 2) {
                    start_val = args[0].constant.value.int;
                    stop_val = args[1].constant.value.int;
                }

                try self.emitIndent();
                try self.output.writer(self.allocator).print("var {s}: i64 = {d};\n", .{ var_name, start_val });
                try self.emitIndent();
                try self.output.writer(self.allocator).print("while ({s} < {d}) {{\n", .{ var_name, stop_val });
                self.indent();
                try self.emitIndent();
                try self.output.writer(self.allocator).print("defer {s} += {d};\n", .{ var_name, step_val });
            } else {
                // Dynamic range - generate expressions
                try self.emitIndent();
                try self.output.writer(self.allocator).print("var {s}: i64 = ", .{var_name});
                if (args.len >= 2) {
                    try genExpr(self, args[0]);
                } else {
                    try self.emit("0");
                }
                try self.emit(";\n");

                try self.emitIndent();
                try self.output.writer(self.allocator).print("while ({s} < ", .{var_name});
                try genExpr(self, args[if (args.len == 1) 0 else 1]);
                try self.emit(") {\n");
                self.indent();
                try self.emitIndent();
                try self.output.writer(self.allocator).print("defer {s} += 1;\n", .{var_name});
            }
        } else {
            // Regular iteration - check if source is constant array, ArrayList, or anytype param
            const is_direct_iterable = blk: {
                // String literals are directly iterable (they're Zig arrays)
                if (gen.iter.* == .constant) {
                    const iter_const_type = self.type_inferrer.inferExpr(gen.iter.*) catch .unknown;
                    if (string_traits.isString(iter_const_type)) break :blk true;
                }
                if (gen.iter.* == .name) {
                    const var_name_gen = gen.iter.name.id;
                    // Const array variables can be iterated directly
                    if (self.isArrayVar(var_name_gen)) break :blk true;
                    // anytype parameters should also be iterated directly (no .items)
                    if (self.anytype_params.contains(var_name_gen)) break :blk true;
                    // String variables are directly iterable
                    if (self.getVarType(var_name_gen)) |vt| {
                        if (string_traits.isString(vt)) break :blk true;
                    }
                }
                break :blk false;
            };

            try self.emitIndent();
            if (is_direct_iterable) {
                // Constant array variable, string literal, or anytype param - iterate directly
                try self.output.writer(self.allocator).print("const __iter_{d}_{d} = ", .{ label_id, gen_idx });
                try genExpr(self, gen.iter.*);
                try self.emit(";\n");
            } else {
                // First emit the list to an intermediate variable, then access .items
                try self.output.writer(self.allocator).print("const __list_{d}_{d} = ", .{ label_id, gen_idx });
                try genExpr(self, gen.iter.*);
                try self.emit(";\n");
                try self.emitIndent();
                try self.output.writer(self.allocator).print("const __iter_{d}_{d} = __list_{d}_{d}.items;\n", .{ label_id, gen_idx, label_id, gen_idx });
            }

            try self.emitIndent();
            // Check if target is a tuple (for tuple unpacking like `for a, b in zip(...)`)
            const is_tuple_target = switch (gen.target.*) {
                .tuple => true,
                .list => true,
                else => false,
            };
            if (is_tuple_target) {
                // Capture as single variable, unpack inside loop
                try self.output.writer(self.allocator).print("for (__iter_{d}_{d}) |__tuple_{d}_{d}__| {{\n", .{ label_id, gen_idx, label_id, gen_idx });
                self.indent();

                // Unpack tuple elements
                const elements = switch (gen.target.*) {
                    .tuple => |t| t.elts,
                    .list => |l| l.elts,
                    else => &[_]ast.Node{},
                };
                for (elements, 0..) |elt, idx| {
                    try self.emitIndent();
                    if (elt == .name) {
                        const var_name = elt.name.id;
                        // Handle underscore discard pattern
                        if (std.mem.eql(u8, var_name, "_")) {
                            try self.output.writer(self.allocator).print("_ = __tuple_{d}_{d}__.@\"{d}\";\n", .{ label_id, gen_idx, idx });
                        } else {
                            // Check if this would shadow an outer variable - use unique name if so
                            if (self.isDeclared(var_name)) {
                                const renamed = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}", .{ var_name, label_id });
                                // Register rename so references within comprehension use the new name
                                try self.var_renames.put(var_name, renamed);
                                try self.output.writer(self.allocator).print("const {s} = __tuple_{d}_{d}__.@\"{d}\";\n", .{ renamed, label_id, gen_idx, idx });
                            } else {
                                try self.output.writer(self.allocator).print("const {s} = __tuple_{d}_{d}__.@\"{d}\";\n", .{ var_name, label_id, gen_idx, idx });
                            }
                        }
                    }
                }
            } else {
                try self.output.writer(self.allocator).print("for (__iter_{d}_{d}) |", .{ label_id, gen_idx });
                try emitForLoopTarget(self, gen.target.*);
                try self.emit("| {\n");
                self.indent();
            }
        }

        // Generate if conditions for this generator
        // Use truthiness conversion for Python semantics (0, "", [], etc. are False)
        for (gen.ifs) |if_cond| {
            try self.emitIndent();
            try self.emit("if (");
            try genComprehensionConditionNoSubs(self, if_cond);
            try self.emit(") {\n");
            self.indent();
        }
    }

    // Generate: try __comp_result_N.append(__global_allocator, <elt_expr>);
    try self.emitIndent();
    try self.output.writer(self.allocator).print("try __comp_result_{d}.append(__global_allocator, ", .{label_id});
    try genExpr(self, genexp.elt.*);
    try self.emit(");\n");

    // Close all if conditions and for loops
    for (genexp.generators) |gen| {
        // Close if conditions for this generator
        for (gen.ifs) |_| {
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
        }

        // Close for loop
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    // Generate: break :gen_N __comp_result_N;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :gen_{d} __comp_result_{d};\n", .{ label_id, label_id });

    self.dedent();
    try self.emitIndent();
    try self.emit("})");
}

/// Check if an expression evaluates to an integer type
fn isIntExpr(node: ast.Node) bool {
    return switch (node) {
        .binop => true, // Arithmetic operations yield int
        .constant => |c| c.value == .int,
        .name => true, // Assume loop vars from range() are int (could be smarter)
        .call => |c| {
            if (c.func.* == .name) return IntReturningBuiltins.has(c.func.name.id);
            return false;
        },
        else => false,
    };
}

/// Convert NativeType to Zig type string for dict comprehension value types
fn nativeTypeToZigStr(native_type: @import("../../../analysis/native_types/core.zig").NativeType) []const u8 {
    return switch (native_type) {
        .int => "i64",
        .bigint, .unified_int => "*runtime.bigint.BigInt",
        .usize => "usize",
        .float => "f64",
        .bool => "bool",
        .string => "[]const u8",
        .bytes => "runtime.builtins.PyBytes",
        .complex => "runtime.complex.PyComplex",
        .none => "?void",
        // All other types fall back to PyValue for heterogeneous dicts
        else => "runtime.PyValue",
    };
}

/// Check if an expression evaluates to a boolean type
fn isBoolExpr(node: ast.Node) bool {
    return switch (node) {
        .compare => true, // Comparisons (including 'in') yield bool
        .boolop => true, // and/or yield bool
        .unaryop => |u| u.op == .Not, // not yields bool
        .constant => |c| type_traits.isBoolean(if (c.value == .bool) .bool else .unknown),
        .call => |c| {
            if (c.func.* == .name) return BoolReturningBuiltins.has(c.func.name.id);
            return false;
        },
        else => false,
    };
}

/// Get the Zig element type string for a generator expression element
fn getGenExpElementType(elt: ast.Node) []const u8 {
    // Check for f-string first - common in generator expressions
    if (elt == .fstring) return "[]u8";
    // Check for string constant
    if (elt == .constant and elt.constant.value == .string) return "[]const u8";
    if (isBoolExpr(elt)) return "bool";
    if (isIntExpr(elt)) return "i64";
    // Default to i64 for unknown types
    return "i64";
}

/// String methods that return a string type
const StringReturningMethods = std.StaticStringMap(void).initComptime(.{
    .{ "replace", {} },
    .{ "strip", {} },
    .{ "lstrip", {} },
    .{ "rstrip", {} },
    .{ "lower", {} },
    .{ "upper", {} },
    .{ "capitalize", {} },
    .{ "title", {} },
    .{ "swapcase", {} },
    .{ "casefold", {} },
    .{ "center", {} },
    .{ "ljust", {} },
    .{ "rjust", {} },
    .{ "zfill", {} },
    .{ "join", {} },
    .{ "format", {} },
    .{ "expandtabs", {} },
    .{ "encode", {} },
    .{ "decode", {} },
    .{ "translate", {} },
});

fn isStringReturningMethod(method_name: []const u8) bool {
    return StringReturningMethods.has(method_name);
}
