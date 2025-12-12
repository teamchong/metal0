/// Static AST analysis for allocator requirements
/// Determines if functions need allocator parameter
const std = @import("std");
const ast = @import("analysis.ast");

/// Methods that use allocator param
const AllocatorMethods = std.StaticStringMap(void).initComptime(.{
    .{ "upper", {} }, .{ "lower", {} }, .{ "strip", {} }, .{ "split", {} },
    .{ "replace", {} }, .{ "join", {} }, .{ "write", {} }, .{ "getvalue", {} },
});

/// Methods using __global_allocator (need error union but not allocator param)
const GlobalAllocMethods = std.StaticStringMap(void).initComptime(.{
    .{ "hexdigest", {} }, .{ "digest", {} }, .{ "append", {} },
    .{ "extend", {} }, .{ "insert", {} }, .{ "appendleft", {} }, .{ "extendleft", {} },
});

/// Builtins needing allocator
const AllocBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "str", {} }, .{ "list", {} }, .{ "dict", {} }, .{ "input", {} },
    .{ "StringIO", {} }, .{ "BytesIO", {} }, .{ "int", {} }, .{ "float", {} },
    .{ "Counter", {} }, .{ "deque", {} }, .{ "defaultdict", {} }, .{ "OrderedDict", {} },
});

/// Builtins using __global_allocator
const GlobalAllocBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "str", {} }, .{ "list", {} }, .{ "dict", {} }, .{ "print", {} },
    .{ "eval", {} }, .{ "exec", {} }, .{ "compile", {} },
});

/// Module functions using allocator param
const ModuleAllocFuncs = std.StaticStringMap(void).initComptime(.{
    .{ "dumps", {} }, .{ "loads", {} }, .{ "match", {} }, .{ "search", {} },
    .{ "findall", {} }, .{ "sub", {} }, .{ "split", {} }, .{ "compile", {} },
    .{ "compress", {} }, .{ "decompress", {} },
});

/// Constructors using allocator
const AllocConstructors = std.StaticStringMap(void).initComptime(.{
    .{ "Counter", {} }, .{ "deque", {} }, .{ "defaultdict", {} },
    .{ "OrderedDict", {} }, .{ "StringIO", {} }, .{ "BytesIO", {} },
});

/// Dunder methods that return primitive values and should NEVER need allocator
const NoAllocatorDunderMethods = std.StaticStringMap(void).initComptime(.{
    .{ "__float__", {} }, .{ "__int__", {} }, .{ "__bool__", {} }, .{ "__hash__", {} },
    .{ "__index__", {} }, .{ "__sizeof__", {} }, .{ "__len__", {} },
    .{ "__eq__", {} }, .{ "__ne__", {} }, .{ "__lt__", {} }, .{ "__le__", {} },
    .{ "__gt__", {} }, .{ "__ge__", {} }, .{ "__contains__", {} },
});

/// Analyze function AST to determine if it needs allocator (for error union)
pub fn analyzeNeedsAllocator(func: ast.Node.FunctionDef, class_name: ?[]const u8) bool {
    if (NoAllocatorDunderMethods.has(func.name)) return false;

    var nested: [32][]const u8 = undefined;
    var count: usize = 0;
    collectNestedClasses(func.body, &nested, &count);
    if (class_name) |cn| if (count < 32) {
        nested[count] = cn;
        count += 1;
    };
    if (count > 0 and hasNestedClassCalls(func.body, nested[0..count])) return true;

    for (func.body) |stmt| if (stmtNeedsAlloc(stmt)) return true;
    return false;
}

/// Analyze if function actually uses allocator param (not __global_allocator)
pub fn analyzeUsesAllocatorParam(func: ast.Node.FunctionDef, class_name: ?[]const u8) bool {
    _ = class_name;
    var nested: [32][]const u8 = undefined;
    var count: usize = 0;
    collectNestedClasses(func.body, &nested, &count);

    for (func.body) |stmt| if (stmtUsesAllocParam(stmt, func.name, nested[0..count])) return true;
    return false;
}

fn collectNestedClasses(stmts: []ast.Node, names: *[32][]const u8, count: *usize) void {
    for (stmts) |stmt| switch (stmt) {
        .class_def => |c| if (count.* < 32) {
            names[count.*] = c.name;
            count.* += 1;
        },
        .if_stmt => |i| {
            collectNestedClasses(i.body, names, count);
            collectNestedClasses(i.else_body, names, count);
        },
        .for_stmt => |f| collectNestedClasses(f.body, names, count),
        .while_stmt => |w| collectNestedClasses(w.body, names, count),
        .try_stmt => |t| {
            collectNestedClasses(t.body, names, count);
            for (t.handlers) |h| collectNestedClasses(h.body, names, count);
        },
        .with_stmt => |w| collectNestedClasses(w.body, names, count),
        else => {},
    };
}

fn hasNestedClassCalls(stmts: []ast.Node, nested: []const []const u8) bool {
    for (stmts) |stmt| if (stmtHasNestedCall(stmt, nested)) return true;
    return false;
}

fn stmtHasNestedCall(stmt: ast.Node, nested: []const []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprHasNestedCall(e.value.*, nested),
        .assign => |a| exprHasNestedCall(a.value.*, nested),
        .aug_assign => |a| exprHasNestedCall(a.target.*, nested) or exprHasNestedCall(a.value.*, nested),
        .return_stmt => |r| if (r.value) |v| exprHasNestedCall(v.*, nested) else false,
        .if_stmt => |i| exprHasNestedCall(i.condition.*, nested) or hasNestedClassCalls(i.body, nested) or hasNestedClassCalls(i.else_body, nested),
        .while_stmt => |w| blk: {
            if (exprHasNestedCall(w.condition.*, nested) or hasNestedClassCalls(w.body, nested)) break :blk true;
            if (w.orelse_body) |ob| if (hasNestedClassCalls(ob, nested)) break :blk true;
            break :blk false;
        },
        .for_stmt => |f| blk: {
            if (exprHasNestedCall(f.iter.*, nested) or hasNestedClassCalls(f.body, nested)) break :blk true;
            if (f.orelse_body) |ob| if (hasNestedClassCalls(ob, nested)) break :blk true;
            break :blk false;
        },
        .try_stmt => |t| blk: {
            if (hasNestedClassCalls(t.body, nested)) break :blk true;
            for (t.handlers) |h| if (hasNestedClassCalls(h.body, nested)) break :blk true;
            if (hasNestedClassCalls(t.else_body, nested)) break :blk true;
            if (hasNestedClassCalls(t.finalbody, nested)) break :blk true;
            break :blk false;
        },
        .with_stmt => |w| exprHasNestedCall(w.context_expr.*, nested) or hasNestedClassCalls(w.body, nested),
        else => false,
    };
}

fn exprHasNestedCall(expr: ast.Node, nested: []const []const u8) bool {
    return switch (expr) {
        .call => |c| blk: {
            if (c.func.* == .name) for (nested) |n| if (std.mem.eql(u8, c.func.name.id, n)) break :blk true;
            for (c.args) |a| if (exprHasNestedCall(a, nested)) break :blk true;
            for (c.keyword_args) |kw| if (exprHasNestedCall(kw.value, nested)) break :blk true;
            break :blk exprHasNestedCall(c.func.*, nested);
        },
        .binop => |b| exprHasNestedCall(b.left.*, nested) or exprHasNestedCall(b.right.*, nested),
        .unaryop => |u| exprHasNestedCall(u.operand.*, nested),
        .boolop => |bo| blk: {
            for (bo.values) |v| if (exprHasNestedCall(v, nested)) break :blk true;
            break :blk false;
        },
        .attribute => |a| exprHasNestedCall(a.value.*, nested),
        .subscript => |s| blk: {
            if (exprHasNestedCall(s.value.*, nested)) break :blk true;
            switch (s.slice) {
                .index => |i| break :blk exprHasNestedCall(i.*, nested),
                .slice => |r| {
                    if (r.lower) |l| if (exprHasNestedCall(l.*, nested)) break :blk true;
                    if (r.upper) |up| if (exprHasNestedCall(up.*, nested)) break :blk true;
                    if (r.step) |st| if (exprHasNestedCall(st.*, nested)) break :blk true;
                    break :blk false;
                },
            }
        },
        .if_expr => |ie| exprHasNestedCall(ie.condition.*, nested) or exprHasNestedCall(ie.body.*, nested) or exprHasNestedCall(ie.orelse_value.*, nested),
        .tuple => |t| blk: {
            for (t.elts) |e| if (exprHasNestedCall(e, nested)) break :blk true;
            break :blk false;
        },
        .list => |l| blk: {
            for (l.elts) |e| if (exprHasNestedCall(e, nested)) break :blk true;
            break :blk false;
        },
        .dict => |d| blk: {
            for (d.keys) |k| if (exprHasNestedCall(k, nested)) break :blk true;
            for (d.values) |v| if (exprHasNestedCall(v, nested)) break :blk true;
            break :blk false;
        },
        .compare => |co| blk: {
            if (exprHasNestedCall(co.left.*, nested)) break :blk true;
            for (co.comparators) |c| if (exprHasNestedCall(c, nested)) break :blk true;
            break :blk false;
        },
        .fstring => |fstr| blk: {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |e| if (exprHasNestedCall(e.node.*, nested)) break :blk true,
                    .format_expr => |fe| if (exprHasNestedCall(fe.expr.*, nested)) break :blk true,
                    .conv_expr => |ce| if (exprHasNestedCall(ce.expr.*, nested)) break :blk true,
                    .literal => {},
                }
            }
            break :blk false;
        },
        .listcomp => |lc| blk: {
            if (exprHasNestedCall(lc.elt.*, nested)) break :blk true;
            for (lc.generators) |gen| {
                if (exprHasNestedCall(gen.iter.*, nested)) break :blk true;
                for (gen.ifs) |cond| if (exprHasNestedCall(cond, nested)) break :blk true;
            }
            break :blk false;
        },
        .dictcomp => |dc| blk: {
            if (exprHasNestedCall(dc.key.*, nested) or exprHasNestedCall(dc.value.*, nested)) break :blk true;
            for (dc.generators) |gen| {
                if (exprHasNestedCall(gen.iter.*, nested)) break :blk true;
                for (gen.ifs) |cond| if (exprHasNestedCall(cond, nested)) break :blk true;
            }
            break :blk false;
        },
        .genexp => |ge| blk: {
            if (exprHasNestedCall(ge.elt.*, nested)) break :blk true;
            for (ge.generators) |gen| {
                if (exprHasNestedCall(gen.iter.*, nested)) break :blk true;
                for (gen.ifs) |cond| if (exprHasNestedCall(cond, nested)) break :blk true;
            }
            break :blk false;
        },
        .lambda => |lam| exprHasNestedCall(lam.body.*, nested),
        .starred => |st| exprHasNestedCall(st.value.*, nested),
        else => false,
    };
}

fn stmtNeedsAlloc(stmt: ast.Node) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprNeedsAlloc(e.value.*),
        .assign => |a| blk: {
            for (a.targets) |t| if (t == .attribute and t.attribute.value.* == .name and std.mem.eql(u8, t.attribute.value.name.id, "self")) break :blk true;
            break :blk exprNeedsAlloc(a.value.*);
        },
        .aug_assign => |a| exprNeedsAlloc(a.value.*),
        .return_stmt => |r| if (r.value) |v| exprNeedsAlloc(v.*) else false,
        .if_stmt => |i| exprNeedsAlloc(i.condition.*) or blk: {
            for (i.body) |s| if (stmtNeedsAlloc(s)) break :blk true;
            for (i.else_body) |s| if (stmtNeedsAlloc(s)) break :blk true;
            break :blk false;
        },
        .while_stmt => |w| exprNeedsAlloc(w.condition.*) or blk: {
            for (w.body) |s| if (stmtNeedsAlloc(s)) break :blk true;
            break :blk false;
        },
        .for_stmt => |f| exprNeedsAlloc(f.iter.*) or blk: {
            for (f.body) |s| if (stmtNeedsAlloc(s)) break :blk true;
            break :blk false;
        },
        .try_stmt => |t| blk: {
            for (t.body) |s| if (stmtNeedsAlloc(s)) break :blk true;
            for (t.handlers) |h| for (h.body) |s| if (stmtNeedsAlloc(s)) break :blk true;
            break :blk false;
        },
        .class_def => |c| blk: {
            for (c.body) |s| if (stmtNeedsAlloc(s)) break :blk true;
            break :blk false;
        },
        .function_def => true,
        .with_stmt => |w| exprNeedsAlloc(w.context_expr.*) or blk: {
            for (w.body) |s| if (stmtNeedsAlloc(s)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

fn exprNeedsAlloc(expr: ast.Node) bool {
    return switch (expr) {
        .binop => |b| (b.op == .Add and (mightBeStr(b.left.*) or mightBeStr(b.right.*))) or
            b.op == .Div or b.op == .FloorDiv or b.op == .Mod or exprNeedsAlloc(b.left.*) or exprNeedsAlloc(b.right.*),
        .call => |c| callNeedsAlloc(c),
        .fstring, .listcomp, .dictcomp, .dict => true,
        .list => |l| l.elts.len > 0 or blk: {
            for (l.elts) |e| if (exprNeedsAlloc(e)) break :blk true;
            break :blk false;
        },
        .tuple => |t| blk: {
            for (t.elts) |e| if (exprNeedsAlloc(e)) break :blk true;
            break :blk false;
        },
        .subscript => |s| exprNeedsAlloc(s.value.*) or switch (s.slice) {
            .index => |i| exprNeedsAlloc(i.*),
            .slice => |r| (if (r.lower) |l| exprNeedsAlloc(l.*) else false) or (if (r.upper) |u| exprNeedsAlloc(u.*) else false),
        },
        .attribute => |a| exprNeedsAlloc(a.value.*),
        .compare => |c| exprNeedsAlloc(c.left.*) or blk: {
            for (c.comparators) |x| if (exprNeedsAlloc(x)) break :blk true;
            break :blk false;
        },
        .boolop => |b| blk: {
            for (b.values) |v| if (exprNeedsAlloc(v)) break :blk true;
            break :blk false;
        },
        .unaryop => |u| exprNeedsAlloc(u.operand.*),
        else => false,
    };
}

fn callNeedsAlloc(call: ast.Node.Call) bool {
    for (call.args) |a| if (exprNeedsAlloc(a)) return true;
    if (call.func.* == .attribute) {
        const m = call.func.attribute.attr;
        if (AllocatorMethods.has(m) or GlobalAllocMethods.has(m)) return true;
        if (call.func.attribute.value.* == .call and exprNeedsAlloc(call.func.attribute.value.*)) return true;
        if (call.func.attribute.value.* == .name) {
            const obj = call.func.attribute.value.name.id;
            if (std.mem.eql(u8, obj, "self")) return true;
            if (ModuleAllocFuncs.has(m)) return true;
        }
    }
    if (call.func.* == .name and AllocBuiltins.has(call.func.name.id)) return true;
    return false;
}

fn mightBeStr(expr: ast.Node) bool {
    return switch (expr) {
        .constant => |c| c.value == .string,
        .fstring => true,
        .call => |c| (c.func.* == .name and (std.mem.eql(u8, c.func.name.id, "str") or std.mem.eql(u8, c.func.name.id, "input"))) or
            (c.func.* == .attribute and (std.mem.eql(u8, c.func.attribute.attr, "upper") or std.mem.eql(u8, c.func.attribute.attr, "lower"))),
        .binop => |b| b.op == .Add and (mightBeStr(b.left.*) or mightBeStr(b.right.*)),
        else => false,
    };
}

fn stmtUsesAllocParam(stmt: ast.Node, func_name: []const u8, nested: []const []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprUsesAllocParam(e.value.*, func_name, nested),
        .assign => |a| exprUsesAllocParam(a.value.*, func_name, nested),
        .aug_assign => |a| exprUsesAllocParam(a.value.*, func_name, nested),
        .return_stmt => |r| if (r.value) |v| exprUsesAllocParam(v.*, func_name, nested) else false,
        .if_stmt => |i| exprUsesAllocParam(i.condition.*, func_name, nested) or blk: {
            for (i.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true;
            for (i.else_body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true;
            break :blk false;
        },
        .while_stmt => |w| exprUsesAllocParam(w.condition.*, func_name, nested) or blk: {
            for (w.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true;
            break :blk false;
        },
        .for_stmt => |f| exprUsesAllocParam(f.iter.*, func_name, nested) or blk: {
            for (f.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true;
            break :blk false;
        },
        .try_stmt => |t| blk: {
            for (t.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true;
            for (t.handlers) |h| for (h.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true;
            break :blk false;
        },
        .class_def => |c| blk: {
            for (c.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true;
            break :blk false;
        },
        .with_stmt => |w| exprUsesAllocParam(w.context_expr.*, func_name, nested) or blk: {
            for (w.body) |s| if (stmtUsesAllocParam(s, func_name, nested)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

fn exprUsesAllocParam(expr: ast.Node, func_name: []const u8, nested: []const []const u8) bool {
    return switch (expr) {
        .binop => |b| exprUsesAllocParam(b.left.*, func_name, nested) or exprUsesAllocParam(b.right.*, func_name, nested),
        .call => |c| callUsesAllocParam(c, func_name, nested),
        .listcomp, .dictcomp => true,
        .list => |l| blk: {
            for (l.elts) |e| if (exprUsesAllocParam(e, func_name, nested)) break :blk true;
            break :blk false;
        },
        .tuple => |t| blk: {
            for (t.elts) |e| if (exprUsesAllocParam(e, func_name, nested)) break :blk true;
            break :blk false;
        },
        .subscript => |s| exprUsesAllocParam(s.value.*, func_name, nested) or switch (s.slice) {
            .index => |i| exprUsesAllocParam(i.*, func_name, nested),
            .slice => |r| (if (r.lower) |l| exprUsesAllocParam(l.*, func_name, nested) else false) or (if (r.upper) |u| exprUsesAllocParam(u.*, func_name, nested) else false),
        },
        .attribute => |a| exprUsesAllocParam(a.value.*, func_name, nested),
        .compare => |co| exprUsesAllocParam(co.left.*, func_name, nested) or blk: {
            for (co.comparators) |x| if (exprUsesAllocParam(x, func_name, nested)) break :blk true;
            break :blk false;
        },
        .boolop => |b| blk: {
            for (b.values) |v| if (exprUsesAllocParam(v, func_name, nested)) break :blk true;
            break :blk false;
        },
        .unaryop => |u| exprUsesAllocParam(u.operand.*, func_name, nested),
        .name => |n| std.mem.eql(u8, n.id, "allocator"),
        .if_expr => |ie| exprUsesAllocParam(ie.body.*, func_name, nested) or exprUsesAllocParam(ie.orelse_value.*, func_name, nested),
        else => false,
    };
}

fn callUsesAllocParam(call: ast.Node.Call, func_name: []const u8, nested: []const []const u8) bool {
    for (call.args) |a| if (exprUsesAllocParam(a, func_name, nested)) return true;
    if (call.func.* == .attribute) {
        if (AllocatorMethods.has(call.func.attribute.attr)) return true;
        if (call.func.attribute.value.* == .name) {
            const obj = call.func.attribute.value.name.id;
            if (ModuleAllocFuncs.has(call.func.attribute.attr) and !std.mem.eql(u8, obj, "self")) return true;
        }
    }
    if (call.func.* == .name) {
        const n = call.func.name.id;
        if (GlobalAllocBuiltins.has(n)) return false;
        if (std.mem.eql(u8, n, func_name)) return true;
        if (AllocBuiltins.has(n)) return true;
        if (AllocConstructors.has(n)) return true;
        for (nested) |c| if (std.mem.eql(u8, n, c)) return true;
    }
    return false;
}
