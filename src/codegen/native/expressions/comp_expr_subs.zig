//! Expression generation with variable substitutions for comprehensions
//! Split from comprehensions.zig for maintainability

const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const hashmap_helper = @import("utils.hashmap_helper");
const zig_keywords = @import("utils.zig_keywords");
const shared = @import("../shared_maps.zig");
const BinOpStrings = shared.BinOpStrings;

// MIGRATED TO ZIGBUILDER

// Trait imports for type checking
const type_traits = @import("../../../analysis/traits/type_traits.zig");

/// Generate expression with variable substitutions for comprehensions
pub fn genExprWithSubs(
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
                // Uses auto-close pattern for outer parens
                const ShiftCtx = struct {
                    s: *NativeCodegen,
                    sb: *const hashmap_helper.StringHashMap([]const u8),
                    left: ast.Node,
                    right: ast.Node,
                    op_str: []const u8,
                };
                try self.withParensCtx(ShiftCtx{
                    .s = self,
                    .sb = subs,
                    .left = b.left.*,
                    .right = b.right.*,
                    .op_str = if (b.op == .LShift) " << " else " >> ",
                }, struct {
                    pub fn f(_: *NativeCodegen, ctx: ShiftCtx) CodegenError!void {
                        try genExprWithSubs(ctx.s, ctx.left, ctx.sb);
                        try ctx.s.emit(ctx.op_str);
                        try ctx.s.emit("@as(u6, @intCast(@mod(");
                        try genExprWithSubs(ctx.s, ctx.right, ctx.sb);
                        try ctx.s.emit(", 64)))");
                    }
                }.f);
            } else {
                // Standard binary ops with auto-close pattern
                const BinOpCtx = struct {
                    s: *NativeCodegen,
                    sb: *const hashmap_helper.StringHashMap([]const u8),
                    left: ast.Node,
                    right: ast.Node,
                    op_str: []const u8,
                };
                try self.withParensCtx(BinOpCtx{
                    .s = self,
                    .sb = subs,
                    .left = b.left.*,
                    .right = b.right.*,
                    .op_str = BinOpStrings.get(@tagName(b.op)) orelse " ? ",
                }, struct {
                    pub fn f(_: *NativeCodegen, ctx: BinOpCtx) CodegenError!void {
                        try genExprWithSubs(ctx.s, ctx.left, ctx.sb);
                        try ctx.s.emit(ctx.op_str);
                        try genExprWithSubs(ctx.s, ctx.right, ctx.sb);
                    }
                }.f);
            }
        },
        .constant => |c| {
            // Use proper constant generation to handle string escaping correctly
            const constants = @import("constants.zig");
            try constants.genConstant(self, c);
        },
        .call => |c| {
            try genCallWithSubs(self, c, subs);
        },
        .list => |l| {
            // Handle list literals with substitution
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
            try genSubscriptWithSubs(self, sub, subs);
        },
        .unaryop => |u| {
            // Handle unary operations with substitution using auto-close pattern
            const prefix = switch (u.op) {
                .USub => "-",
                .UAdd => "+",
                .Not => "!",
                .Invert => "~",
            };
            const UnaryCtx = struct {
                s: *NativeCodegen,
                sb: *const hashmap_helper.StringHashMap([]const u8),
                operand: ast.Node,
                pfx: []const u8,
            };
            try self.withParensCtx(UnaryCtx{
                .s = self,
                .sb = subs,
                .operand = u.operand.*,
                .pfx = prefix,
            }, struct {
                pub fn f(_: *NativeCodegen, ctx: UnaryCtx) CodegenError!void {
                    try ctx.s.emit(ctx.pfx);
                    try genExprWithSubs(ctx.s, ctx.operand, ctx.sb);
                }
            }.f);
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
            try genIfExprWithSubs(self, ie, subs);
        },
        .compare => |cmp| {
            try genCompareWithSubs(self, cmp, expr, subs);
        },
        else => {
            // For other expressions, fallback to regular genExpr
            const parent = @import("../expressions.zig");
            try parent.genExpr(self, expr);
        },
    }
}

/// Generate call expression with substitutions
fn genCallWithSubs(
    self: *NativeCodegen,
    c: ast.Node.Call,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
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
        try genSimpleCallWithSubs(self, c, subs);
    } else if (c.func.* == .attribute) {
        // Attribute call (e.g., random.sample, struct.unpack_from)
        try genExprWithSubs(self, c.func.*, subs);
        try self.emit("(");
        var first_arg = true;
        for (c.args) |arg| {
            if (!first_arg) try self.emit(", ");
            first_arg = false;
            try genExprWithSubs(self, arg, subs);
        }
        try self.emit(")");
    } else if (c.func.* == .name) {
        try genBuiltinCallWithSubs(self, c, subs);
    } else {
        // Non-name func (lambda, etc.) - fall back to genExpr
        const parent = @import("../expressions.zig");
        try parent.genExpr(self, .{ .call = c });
    }
}

/// Generate simple local function call with substitutions
fn genSimpleCallWithSubs(
    self: *NativeCodegen,
    c: ast.Node.Call,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
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
}

/// Generate builtin call with substitutions
fn genBuiltinCallWithSubs(
    self: *NativeCodegen,
    c: ast.Node.Call,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
    const func_name = c.func.name.id;

    if (std.mem.eql(u8, func_name, "bool") and c.args.len == 1) {
        // bool(x) in comprehension - use runtime.toBool with substitution
        try self.emit("runtime.toBool(");
        try genExprWithSubs(self, c.args[0], subs);
        try self.emit(")");
    } else if (std.mem.eql(u8, func_name, "int") and c.args.len >= 1) {
        // int(x) or int(x, base) in comprehension - cast with substitution
        try self.emit("@as(i64, @intCast(");
        try genExprWithSubs(self, c.args[0], subs);
        try self.emit("))");
    } else if (std.mem.eql(u8, func_name, "str") and c.args.len == 1) {
        // str(x) in comprehension - use runtime.format with substitution
        try self.emit("runtime.format(\"{}\", .{");
        try genExprWithSubs(self, c.args[0], subs);
        try self.emit("})");
    } else if (std.mem.eql(u8, func_name, "len") and c.args.len == 1) {
        // len(x) in comprehension - use .len with substitution
        try self.emit("@as(i64, @intCast((");
        try genExprWithSubs(self, c.args[0], subs);
        try self.emit(").len))");
    } else if (std.mem.eql(u8, func_name, "abs") and c.args.len == 1) {
        // abs(x) in comprehension - use @abs with substitution
        try self.emit("@abs(");
        try genExprWithSubs(self, c.args[0], subs);
        try self.emit(")");
    } else if (std.mem.eql(u8, func_name, "float") and c.args.len == 1) {
        // float(x) in comprehension - use runtime.floatBuiltinCall with substitution
        try self.emit("(runtime.floatBuiltinCall(");
        try genExprWithSubs(self, c.args[0], subs);
        try self.emit(", .{}) catch 0.0)");
    } else if (std.mem.eql(u8, func_name, "complex") and c.args.len >= 1) {
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
    } else if (std.mem.eql(u8, func_name, "bytes") and c.args.len > 0) {
        try genBytesCallWithSubs(self, c, subs);
    } else if ((std.mem.eql(u8, func_name, "set") or std.mem.eql(u8, func_name, "frozenset")) and c.args.len == 1) {
        try genSetCallWithSubs(self, c, subs);
    } else if (std.mem.eql(u8, func_name, "bytearray") and c.args.len > 0) {
        // bytearray(n) in comprehension - allocates n zero-filled bytes
        try self.emit("blk_ba: { const _n: usize = @intCast(");
        try genExprWithSubs(self, c.args[0], subs);
        try self.emit("); const _buf = try __global_allocator.alloc(u8, _n); @memset(_buf, 0); break :blk_ba _buf; }");
    } else {
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
    }
}

/// Generate bytes() call with substitutions
fn genBytesCallWithSubs(
    self: *NativeCodegen,
    c: ast.Node.Call,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
    // Special case: bytes([x]) in comprehension needs substitution for list elements
    if (c.args[0] == .list and c.args[0].list.elts.len == 1) {
        // bytes([x]) -> &[_]u8{@intCast(x)} for single element
        try self.emit("&[_]u8{@intCast(");
        try genExprWithSubs(self, c.args[0].list.elts[0], subs);
        try self.emit(")}");
    } else {
        // General case: generate list with substitution
        const label = try self.emitInlineBlockStart("blk");
        try self.emit("var _bytes_list = std.ArrayListUnmanaged(u8){}; ");
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
        try self.emitFmt("break :{s} _bytes_list.items; ", .{label});
        try self.emitInlineBlockEnd();
    }
}

/// Generate set()/frozenset() call with substitutions
fn genSetCallWithSubs(
    self: *NativeCodegen,
    c: ast.Node.Call,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
    // Generate: set_blk: { var _set = ...; for (<arg>) |_item| { try _set.put(_item, {}); } break :set_blk _set; }
    const label = try self.emitInlineBlockStart("set");
    try self.emit("\n");
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
    try self.emitFmt("break :{s} _set;\n", .{label});
    self.dedent();
    try self.emitIndent();
    try self.emitInlineBlockEnd();
}

/// Generate subscript with substitutions
fn genSubscriptWithSubs(
    self: *NativeCodegen,
    sub: ast.Node.Subscript,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
    switch (sub.slice) {
        .slice => |sr| {
            // It's a slice - generate slice with substitutions
            const label = try self.emitInlineBlockStart("slice");
            try self.emit("const __s = ");
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
            try self.emitFmt(", __s.len); break :{s} if (__start < __end) __s[__start..__end] else \"\"; ", .{label});
            try self.emitInlineBlockEnd();
        },
        .index => |idx| {
            // Simple index with substitution
            try genExprWithSubs(self, sub.value.*, subs);
            try self.emit("[");
            try genExprWithSubs(self, idx.*, subs);
            try self.emit("]");
        },
    }
}

/// Generate if expression with substitutions
fn genIfExprWithSubs(
    self: *NativeCodegen,
    ie: anytype,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
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
}

/// Generate comparison with substitutions
fn genCompareWithSubs(
    self: *NativeCodegen,
    cmp: ast.Node.Compare,
    expr: ast.Node,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
    // For complex comparisons (in, not in, is, is not) OR chained comparisons (a < b < c),
    // delegate to main genExpr which handles these properly.
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
        // Simple single-operator comparisons with auto-close pattern
        const CmpCtx = struct {
            s: *NativeCodegen,
            sb: *const hashmap_helper.StringHashMap([]const u8),
            left: ast.Node,
            ops: []const ast.CompareOp,
            comparators: []ast.Node,
        };
        try self.withParensCtx(CmpCtx{
            .s = self,
            .sb = subs,
            .left = cmp.left.*,
            .ops = cmp.ops,
            .comparators = cmp.comparators,
        }, struct {
            pub fn f(_: *NativeCodegen, ctx: CmpCtx) CodegenError!void {
                try genExprWithSubs(ctx.s, ctx.left, ctx.sb);
                for (ctx.ops, 0..) |op, idx| {
                    const op_str = switch (op) {
                        .Eq => " == ",
                        .NotEq => " != ",
                        .Lt => " < ",
                        .LtEq => " <= ",
                        .Gt => " > ",
                        .GtEq => " >= ",
                        else => " == ", // Fallback (shouldn't reach here)
                    };
                    try ctx.s.emit(op_str);
                    try genExprWithSubs(ctx.s, ctx.comparators[idx], ctx.sb);
                }
            }
        }.f);
    }
}
