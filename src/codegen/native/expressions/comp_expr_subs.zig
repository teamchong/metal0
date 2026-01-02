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
const string_traits_mod = @import("../../../analysis/traits/string_traits.zig");

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
            // Check for string concatenation (requires std.mem.concat instead of +)
            if (b.op == .Add) {
                const left_type = self.type_inferrer.inferExpr(b.left.*) catch .unknown;
                const right_type = self.type_inferrer.inferExpr(b.right.*) catch .unknown;
                const string_traits = @import("../../../analysis/traits/string_traits.zig");
                if (string_traits.isString(left_type) or string_traits.isString(right_type)) {
                    try emitStringConcatWithSubs(self, b.left.*, b.right.*, subs);
                    return;
                }
            }
            // Use @mod for modulo to handle signed integers properly
            if (b.op == .Mod) {
                try emitModWithSubs(self, b.left.*, b.right.*, subs);
            } else if (b.op == .Pow) {
                // Zig doesn't have ** operator, use std.math.pow
                try emitPowWithSubs(self, b.left.*, b.right.*, subs);
            } else if (b.op == .FloorDiv) {
                // Floor division uses @divFloor for Python semantics
                try emitFloorDivWithSubs(self, b.left.*, b.right.*, subs);
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
            // Use const for empty lists (never modified), var for non-empty (appended to)
            if (l.elts.len == 0) {
                try self.emit("const _list = std.ArrayListUnmanaged(i64){};\n");
            } else {
                try self.emit("var _list = std.ArrayListUnmanaged(i64){};\n");
                for (l.elts) |elt| {
                    try self.emitIndent();
                    try self.emit("try _list.append(__global_allocator, ");
                    try genExprWithSubs(self, elt, subs);
                    try self.emit(");\n");
                }
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
        const AttrCallCtx = struct { a: []ast.Node, s: *const hashmap_helper.StringHashMap([]const u8) };
        try self.withParensCtx(AttrCallCtx{ .a = c.args, .s = subs }, struct {
            fn emit(s: *NativeCodegen, ctx: AttrCallCtx) CodegenError!void {
                var first_arg = true;
                for (ctx.a) |arg| {
                    if (!first_arg) try s.emit(", ");
                    first_arg = false;
                    try genExprWithSubs(s, arg, ctx.s);
                }
            }
        }.emit);
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
        try emitToBoolWithSubs(self, c.args[0], subs);
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
        try emitAbsWithSubs(self, c.args[0], subs);
    } else if (std.mem.eql(u8, func_name, "float") and c.args.len == 1) {
        // float(x) in comprehension - use runtime.floatBuiltinCall with substitution
        try self.emit("(runtime.floatBuiltinCall(");
        try genExprWithSubs(self, c.args[0], subs);
        try self.emit(", .{}) catch 0.0)");
    } else if (std.mem.eql(u8, func_name, "complex") and c.args.len >= 1) {
        // complex(x) or complex(x, y) in comprehension - use runtime.PyComplex.create
        const imag = if (c.args.len >= 2) c.args[1] else null;
        try emitComplexWithSubs(self, c.args[0], imag, subs);
    } else if (std.mem.eql(u8, func_name, "bytes") and c.args.len > 0) {
        try genBytesCallWithSubs(self, c, subs);
    } else if ((std.mem.eql(u8, func_name, "set") or std.mem.eql(u8, func_name, "frozenset")) and c.args.len == 1) {
        try genSetCallWithSubs(self, c, subs);
    } else if (std.mem.eql(u8, func_name, "bytearray") and c.args.len > 0) {
        // bytearray(n) in comprehension - allocates n zero-filled bytes
        try self.emit("blk_ba: { const _n: usize = @intCast(");
        try genExprWithSubs(self, c.args[0], subs);
        try self.emit("); const _buf = try __global_allocator.alloc(u8, _n); @memset(_buf, 0); break :blk_ba _buf; }");
    } else if (std.mem.eql(u8, func_name, "id") and c.args.len == 1) {
        // id(x) in comprehension - returns memory address as integer with substitution
        try self.emit("@as(i64, @intCast(@intFromPtr(&(");
        try genExprWithSubs(self, c.args[0], subs);
        try self.emit("))))");
    } else if (std.mem.eql(u8, func_name, "isinstance") and c.args.len == 2) {
        // isinstance(obj, Type) in comprehension - check type at compile time
        // Get the type name being checked
        if (c.args[1] == .name) {
            const type_name = c.args[1].name.id;
            // Generate: (@TypeOf(obj) == Type or @TypeOf(obj) == *Type or @TypeOf(obj) == *const Type)
            try self.emit("(@TypeOf(");
            try genExprWithSubs(self, c.args[0], subs);
            try self.emit(") == ");
            try self.emit(type_name);
            try self.emit(" or @TypeOf(");
            try genExprWithSubs(self, c.args[0], subs);
            try self.emit(") == *");
            try self.emit(type_name);
            try self.emit(" or @TypeOf(");
            try genExprWithSubs(self, c.args[0], subs);
            try self.emit(") == *const ");
            try self.emit(type_name);
            try self.emit(")");
        } else {
            // Fallback for tuple of types - just emit false for now
            try self.emit("false");
        }
    } else if (std.mem.eql(u8, func_name, "ord") and c.args.len == 1) {
        // ord(x) in comprehension - get first byte of string as integer
        try self.emit("@as(i64, (");
        try genExprWithSubs(self, c.args[0], subs);
        try self.emit(")[0])");
    } else if (std.mem.eql(u8, func_name, "chr") and c.args.len == 1) {
        // chr(x) in comprehension - convert integer to single-char string
        try self.emit("(try runtime.builtins.chr(__global_allocator, @intCast(");
        try genExprWithSubs(self, c.args[0], subs);
        try self.emit(")))");
    } else if (std.mem.eql(u8, func_name, "getattr") and c.args.len >= 2) {
        // getattr(obj, name) in comprehension - use dynamic_attrs dispatch
        const dynamic_attrs = @import("../builtins/dynamic_attrs.zig");
        try dynamic_attrs.genGetattr(self, c.args);
    } else if (std.mem.eql(u8, func_name, "hasattr") and c.args.len >= 2) {
        // hasattr(obj, name) in comprehension - use dynamic_attrs dispatch
        const dynamic_attrs = @import("../builtins/dynamic_attrs.zig");
        try dynamic_attrs.genHasattr(self, c.args);
    } else if (std.mem.eql(u8, func_name, "setattr") and c.args.len >= 3) {
        // setattr(obj, name, value) in comprehension - use dynamic_attrs dispatch
        const dynamic_attrs = @import("../builtins/dynamic_attrs.zig");
        try dynamic_attrs.genSetattr(self, c.args);
    } else if (std.mem.eql(u8, func_name, "next") and c.args.len >= 1) {
        // next(iterator) in comprehension - call iterator's .next() method
        try self.emit("((");
        try genExprWithSubs(self, c.args[0], subs);
        try self.emit(").next() orelse ");
        if (c.args.len >= 2) {
            // next(iter, default) - use default value if iterator exhausted
            try genExprWithSubs(self, c.args[1], subs);
        } else {
            // next(iter) with no default - return 0 as fallback (or could error)
            try self.emit("0");
        }
        try self.emit(")");
    } else if (std.mem.eql(u8, func_name, "slice") and c.args.len >= 1) {
        // slice(start, end) or slice(stop) - create slice object
        // In comprehensions, this is typically used as slice(start, end) for indexing
        if (c.args.len == 1) {
            // slice(stop) - slice from 0 to stop
            try self.emit(".{ .start = 0, .stop = @as(usize, @intCast(");
            try genExprWithSubs(self, c.args[0], subs);
            try self.emit(")) }");
        } else {
            // slice(start, end)
            try self.emit(".{ .start = @as(usize, @intCast(");
            try genExprWithSubs(self, c.args[0], subs);
            try self.emit(")), .stop = @as(usize, @intCast(");
            try genExprWithSubs(self, c.args[1], subs);
            try self.emit(")) }");
        }
    } else {
        // Fallback: generate call with substituted args
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), func_name);
        const FallbackCtx = struct { a: []ast.Node, s: *const hashmap_helper.StringHashMap([]const u8) };
        try self.withParensCtx(FallbackCtx{ .a = c.args, .s = subs }, struct {
            fn emit(s: *NativeCodegen, ctx: FallbackCtx) CodegenError!void {
                var first_arg = true;
                for (ctx.a) |arg| {
                    if (!first_arg) try s.emit(", ");
                    first_arg = false;
                    try genExprWithSubs(s, arg, ctx.s);
                }
            }
        }.emit);
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
        const Ctx = struct {
            arg: ast.Node,
            subs: *const hashmap_helper.StringHashMap([]const u8),
        };
        try self.withInlineBlock("blk", Ctx{ .arg = c.args[0], .subs = subs }, struct {
            fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
                try s.emit("var _bytes_list = std.ArrayListUnmanaged(u8){}; ");
                if (ctx.arg == .list) {
                    for (ctx.arg.list.elts) |elt| {
                        try s.emit("try _bytes_list.append(__global_allocator, @intCast(");
                        try genExprWithSubs(s, elt, ctx.subs);
                        try s.emit(")); ");
                    }
                } else {
                    try s.emit("for ((");
                    try genExprWithSubs(s, ctx.arg, ctx.subs);
                    try s.emit(").items) |_item| try _bytes_list.append(__global_allocator, @intCast(_item)); ");
                }
                try s.emit("break :");
                try s.emit(label);
                try s.emit(" _bytes_list.items; ");
            }
        }.emit);
    }
}

/// Generate set()/frozenset() call with substitutions
fn genSetCallWithSubs(
    self: *NativeCodegen,
    c: ast.Node.Call,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
    // Generate: set_blk: { var _set = ...; for (<arg>) |_item| { try _set.put(_item, {}); } break :set_blk _set; }
    const Ctx = struct {
        arg: ast.Node,
        subs: *const hashmap_helper.StringHashMap([]const u8),
    };
    try self.withInlineBlock("set", Ctx{ .arg = c.args[0], .subs = subs }, struct {
        fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
            try s.emit("\n");
            s.indent();
            try s.emitIndent();
            try s.emit("var _set = std.AutoHashMap(i64, void).init(__global_allocator);\n");

            // Check if arg is a list literal - iterate over elements
            if (ctx.arg == .list) {
                const list_elts = ctx.arg.list.elts;
                for (list_elts) |elt| {
                    try s.emitIndent();
                    try s.emit("try _set.put(");
                    try genExprWithSubs(s, elt, ctx.subs);
                    try s.emit(", {});\n");
                }
            } else {
                // General case - iterate over the expression
                try s.emitIndent();
                try s.emit("for (");
                try genExprWithSubs(s, ctx.arg, ctx.subs);
                try s.emit(") |_item| {\n");
                s.indent();
                try s.emitIndent();
                try s.emit("try _set.put(_item, {});\n");
                s.dedent();
                try s.emitIndent();
                try s.emit("}\n");
            }
            try s.emitIndent();
            try s.emit("break :");
            try s.emit(label);
            try s.emit(" _set;\n");
            s.dedent();
            try s.emitIndent();
        }
    }.emit);
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
            const Ctx = struct {
                value: ast.Node,
                sr: ast.Node.SliceRange,
                subs: *const hashmap_helper.StringHashMap([]const u8),
            };
            try self.withInlineBlock("slice", Ctx{ .value = sub.value.*, .sr = sr, .subs = subs }, struct {
                fn emit(s: *NativeCodegen, label: []const u8, ctx: Ctx) CodegenError!void {
                    try s.emit("const __s = ");
                    try genExprWithSubs(s, ctx.value, ctx.subs);
                    try s.emit("; const __start = @min(");
                    if (ctx.sr.lower) |lower| {
                        try genExprWithSubs(s, lower.*, ctx.subs);
                    } else {
                        try s.emit("0");
                    }
                    try s.emit(", __s.len); const __end = @min(");
                    if (ctx.sr.upper) |upper| {
                        try genExprWithSubs(s, upper.*, ctx.subs);
                    } else {
                        try s.emit("__s.len");
                    }
                    try s.emit(", __s.len); break :");
                    try s.emit(label);
                    try s.emit(" if (__start < __end) __s[__start..__end] else \"\"; ");
                }
            }.emit);
        },
        .index => |idx| {
            // Simple index with substitution
            try genExprWithSubs(self, sub.value.*, subs);
            const IndexCtx = struct { i: *ast.Node, s: *const hashmap_helper.StringHashMap([]const u8) };
            try self.withBracketsCtx(IndexCtx{ .i = idx, .s = subs }, struct {
                fn emit(s: *NativeCodegen, ctx: IndexCtx) CodegenError!void {
                    try genExprWithSubs(s, ctx.i.*, ctx.s);
                }
            }.emit);
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
        try emitPyTruthyWithSubs(self, ie.condition.*, subs);
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

// === Structured helpers for binary operations with substitutions ===

/// Helper: emit @mod(left, right) with substitutions and guaranteed bracket matching
fn emitModWithSubs(
    self: *NativeCodegen,
    left: ast.Node,
    right: ast.Node,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
    const Ctx = struct { l: ast.Node, r: ast.Node, sb: *const hashmap_helper.StringHashMap([]const u8) };
    try self.emitCallCtx("@mod", Ctx{ .l = left, .r = right, .sb = subs }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try genExprWithSubs(s, ctx.l, ctx.sb);
            try s.emit(", ");
            try genExprWithSubs(s, ctx.r, ctx.sb);
        }
    }.f);
}

/// Helper: emit std.math.pow(i64, left, right) with substitutions and guaranteed bracket matching
fn emitPowWithSubs(
    self: *NativeCodegen,
    left: ast.Node,
    right: ast.Node,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
    const Ctx = struct { l: ast.Node, r: ast.Node, sb: *const hashmap_helper.StringHashMap([]const u8) };
    try self.emitCallCtx("std.math.pow", Ctx{ .l = left, .r = right, .sb = subs }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emit("i64, ");
            try genExprWithSubs(s, ctx.l, ctx.sb);
            try s.emit(", ");
            try genExprWithSubs(s, ctx.r, ctx.sb);
        }
    }.f);
}

/// Helper: emit @divFloor(left, right) with substitutions and guaranteed bracket matching
fn emitFloorDivWithSubs(
    self: *NativeCodegen,
    left: ast.Node,
    right: ast.Node,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
    const Ctx = struct { l: ast.Node, r: ast.Node, sb: *const hashmap_helper.StringHashMap([]const u8) };
    try self.emitCallCtx("@divFloor", Ctx{ .l = left, .r = right, .sb = subs }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try genExprWithSubs(s, ctx.l, ctx.sb);
            try s.emit(", ");
            try genExprWithSubs(s, ctx.r, ctx.sb);
        }
    }.f);
}

/// Helper: emit std.mem.concat(allocator, u8, &.{left, right}) for string concatenation
fn emitStringConcatWithSubs(
    self: *NativeCodegen,
    left: ast.Node,
    right: ast.Node,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
    try self.emit("try std.mem.concat(__global_allocator, u8, &[_][]const u8{ ");
    try genExprWithSubs(self, left, subs);
    try self.emit(", ");
    try genExprWithSubs(self, right, subs);
    try self.emit(" })");
}

/// Helper context for single-arg builtin calls with substitutions
const SingleArgSubsCtx = struct {
    arg: ast.Node,
    subs: *const hashmap_helper.StringHashMap([]const u8),
};

/// Helper: emit runtime.toBool(expr) with substitutions
fn emitToBoolWithSubs(self: *NativeCodegen, arg: ast.Node, subs: *const hashmap_helper.StringHashMap([]const u8)) CodegenError!void {
    try self.emitCallCtx("runtime.toBool", SingleArgSubsCtx{ .arg = arg, .subs = subs }, struct {
        pub fn f(s: *NativeCodegen, ctx: SingleArgSubsCtx) CodegenError!void {
            try genExprWithSubs(s, ctx.arg, ctx.subs);
        }
    }.f);
}

/// Helper: emit @abs(expr) with substitutions
fn emitAbsWithSubs(self: *NativeCodegen, arg: ast.Node, subs: *const hashmap_helper.StringHashMap([]const u8)) CodegenError!void {
    try self.emitCallCtx("@abs", SingleArgSubsCtx{ .arg = arg, .subs = subs }, struct {
        pub fn f(s: *NativeCodegen, ctx: SingleArgSubsCtx) CodegenError!void {
            try genExprWithSubs(s, ctx.arg, ctx.subs);
        }
    }.f);
}

/// Helper context for two-arg calls with substitutions
const TwoArgSubsCtx = struct {
    arg1: ast.Node,
    arg2: ?ast.Node,
    subs: *const hashmap_helper.StringHashMap([]const u8),
};

/// Helper: emit runtime.PyComplex.create(real, imag) with substitutions
fn emitComplexWithSubs(self: *NativeCodegen, real: ast.Node, imag: ?ast.Node, subs: *const hashmap_helper.StringHashMap([]const u8)) CodegenError!void {
    try self.emitCallCtx("runtime.PyComplex.create", TwoArgSubsCtx{ .arg1 = real, .arg2 = imag, .subs = subs }, struct {
        pub fn f(s: *NativeCodegen, ctx: TwoArgSubsCtx) CodegenError!void {
            try genExprWithSubs(s, ctx.arg1, ctx.subs);
            try s.emit(", ");
            if (ctx.arg2) |a2| {
                try genExprWithSubs(s, a2, ctx.subs);
            } else {
                try s.emit("0.0");
            }
        }
    }.f);
}

/// Helper: emit runtime.pyTruthy(expr) with substitutions
fn emitPyTruthyWithSubs(self: *NativeCodegen, arg: ast.Node, subs: *const hashmap_helper.StringHashMap([]const u8)) CodegenError!void {
    try self.emitCallCtx("runtime.pyTruthy", SingleArgSubsCtx{ .arg = arg, .subs = subs }, struct {
        pub fn f(s: *NativeCodegen, ctx: SingleArgSubsCtx) CodegenError!void {
            try genExprWithSubs(s, ctx.arg, ctx.subs);
        }
    }.f);
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
        // Check for string comparisons that need std.mem.eql
        // This handles cases like: meth[0] != "_" or name == "test"
        const left_type = self.type_inferrer.inferExpr(cmp.left.*) catch .unknown;
        const right_type = self.type_inferrer.inferExpr(cmp.comparators[0]) catch .unknown;

        // Check if left is a subscript with integer index (e.g., meth[0]) and right is a single-char string literal
        // This handles the common pattern of character-to-string comparison in Python
        const is_char_to_string_compare = blk: {
            // Check if left is an integer subscript (e.g., x[0])
            if (cmp.left.* == .subscript) {
                const slice = cmp.left.subscript.slice;
                // Check if it's an integer index (not a slice)
                if (slice == .index) {
                    const idx_node = slice.index.*;
                    if (idx_node == .constant and idx_node.constant.value == .int) {
                        // Check if right is a single-character string literal
                        if (cmp.comparators[0] == .constant) {
                            const val = cmp.comparators[0].constant.value;
                            if (val == .string and val.string.len == 1) {
                                break :blk true;
                            }
                        }
                    }
                }
            }
            break :blk false;
        };

        // Check if both sides are strings (full string comparison)
        const is_string_compare = string_traits_mod.isStringLike(left_type) and string_traits_mod.isStringLike(right_type);

        if (is_char_to_string_compare) {
            // Character to single-char string: convert string to character
            // e.g., meth[0] != "_" becomes meth[0] != '_'
            const op = cmp.ops[0];
            if (op == .NotEq) {
                try self.emit("(");
            }
            try genExprWithSubs(self, cmp.left.*, subs);
            try self.emit(switch (op) {
                .Eq => " == '",
                .NotEq => " != '",
                else => " == '", // Fallback
            });
            // Emit the single character
            const char_str = cmp.comparators[0].constant.value.string;
            try self.emit(char_str);
            try self.emit("'");
            if (op == .NotEq) {
                try self.emit(")");
            }
        } else if (is_string_compare) {
            // Full string comparison: use std.mem.eql
            const op = cmp.ops[0];
            if (op == .NotEq) {
                try self.emit("!");
            }
            try self.emit("std.mem.eql(u8, ");
            try genExprWithSubs(self, cmp.left.*, subs);
            try self.emit(", ");
            try genExprWithSubs(self, cmp.comparators[0], subs);
            try self.emit(")");
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
}
