/// Test skip detection for unittest classes
const std = @import("std");
const ast = @import("analysis.ast");
const hashmap_helper = @import("utils.hashmap_helper");
const shared = @import("../../../shared_maps.zig");
const TypeParamDefaults = shared.PythonBuiltinTypes;
const PyNameToZig = shared.PyTypeToZig;

/// Check if test has @support.cpython_only decorator
pub fn hasCPythonOnlyDecorator(decorators: []const ast.Node) bool {
    for (decorators) |decorator| {
        if (decorator == .attribute) {
            const attr = decorator.attribute;
            if (std.mem.eql(u8, attr.attr, "cpython_only") and
                attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "support"))
                return true;
        }
    }
    return false;
}

/// Check if test has @unittest.skipUnless with CPython-only module
pub fn hasSkipUnlessCPythonModule(decorators: []const ast.Node) bool {
    for (decorators) |decorator| {
        if (decorator == .call) {
            const call = decorator.call;
            if (call.func.* == .attribute) {
                const func_attr = call.func.attribute;
                if (std.mem.eql(u8, func_attr.attr, "skipUnless") and
                    func_attr.value.* == .name and std.mem.eql(u8, func_attr.value.name.id, "unittest"))
                {
                    if (call.args.len > 0 and call.args[0] == .name) {
                        const arg_name = call.args[0].name.id;
                        if (std.mem.eql(u8, arg_name, "_pylong") or std.mem.eql(u8, arg_name, "_decimal"))
                            return true;
                    }
                }
            }
        }
    }
    return false;
}

/// Check if test has @unittest.skipIf(module is None, ...)
pub fn hasSkipIfModuleIsNone(decorators: []const ast.Node, skipped_modules: *const hashmap_helper.StringHashMap(void)) bool {
    for (decorators) |decorator| {
        if (decorator == .call) {
            const call = decorator.call;
            if (call.func.* == .attribute) {
                const func_attr = call.func.attribute;
                if (std.mem.eql(u8, func_attr.attr, "skipIf") and
                    func_attr.value.* == .name and std.mem.eql(u8, func_attr.value.name.id, "unittest"))
                {
                    if (call.args.len > 0 and call.args[0] == .compare) {
                        const cmp = call.args[0].compare;
                        if (cmp.ops.len > 0 and cmp.ops[0] == .Is and cmp.left.* == .name and cmp.comparators.len > 0) {
                            const module_name = cmp.left.name.id;
                            const is_none = if (cmp.comparators[0] == .constant) cmp.comparators[0].constant.value == .none else false;
                            if (is_none and skipped_modules.contains(module_name)) return true;
                        }
                    }
                }
            }
        }
    }
    return false;
}

/// Check if parameter has type as default value
pub fn hasTypeParameterDefault(args: []const ast.Arg) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg.name, "self")) continue;
        if (arg.default) |d| if (d.* == .name and TypeParamDefaults.has(d.name.id)) return true;
    }
    return false;
}

/// Check if test calls self.method() with class argument
pub fn callsSelfMethodWithClassArg(stmts: []const ast.Node, class_names: []const []const u8) bool {
    for (stmts) |stmt| if (stmtCallsSelfMethodWithClassArg(stmt, class_names)) return true;
    return false;
}

fn stmtCallsSelfMethodWithClassArg(stmt: ast.Node, class_names: []const []const u8) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprCallsSelfMethodWithClassArg(e.value.*, class_names),
        .assign => |a| exprCallsSelfMethodWithClassArg(a.value.*, class_names),
        .return_stmt => |r| if (r.value) |v| exprCallsSelfMethodWithClassArg(v.*, class_names) else false,
        .if_stmt => |i| blk: {
            for (i.body) |s| if (stmtCallsSelfMethodWithClassArg(s, class_names)) break :blk true;
            for (i.else_body) |s| if (stmtCallsSelfMethodWithClassArg(s, class_names)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

fn exprCallsSelfMethodWithClassArg(expr: ast.Node, class_names: []const []const u8) bool {
    if (expr != .call) return false;
    const c = expr.call;
    if (c.func.* != .attribute) return false;
    const attr = c.func.attribute;
    if (attr.value.* != .name or !std.mem.eql(u8, attr.value.name.id, "self")) return false;
    for (c.args) |arg| if (arg == .name) for (class_names) |cn| if (std.mem.eql(u8, arg.name.id, cn)) return true;
    return false;
}

/// Check for "skip:" in docstring
pub fn hasSkipDocstring(func_body: []const ast.Node) bool {
    if (func_body.len == 0) return false;
    if (func_body[0] != .expr_stmt) return false;
    const expr = func_body[0].expr_stmt.value.*;
    if (expr != .constant or expr.constant.value != .string) return false;
    const ds = expr.constant.value.string;
    return std.mem.startsWith(u8, ds, "skip:") or std.mem.indexOf(u8, ds, "skip:") != null;
}

/// Count @mock.patch decorators
pub fn countMockPatchDecorators(decorators: []const ast.Node) usize {
    var count: usize = 0;
    for (decorators) |d| if (isMockPatchDecorator(d)) { count += 1; };
    return count;
}

fn isMockPatchDecorator(decorator: ast.Node) bool {
    if (decorator == .call) return isMockPatchFunc(decorator.call.func.*);
    return isMockPatchFunc(decorator);
}

fn isMockPatchFunc(node: ast.Node) bool {
    if (node != .attribute) return false;
    const attr = node.attribute;
    if (std.mem.eql(u8, attr.attr, "object") and attr.value.* == .attribute) {
        const parent = attr.value.attribute;
        if (std.mem.eql(u8, parent.attr, "patch")) {
            if (parent.value.* == .name) return std.mem.eql(u8, parent.value.name.id, "mock");
            if (parent.value.* == .attribute) return std.mem.eql(u8, parent.value.attribute.attr, "mock");
        }
    } else if (std.mem.eql(u8, attr.attr, "patch")) {
        if (attr.value.* == .name) return std.mem.eql(u8, attr.value.name.id, "mock");
        if (attr.value.* == .attribute) return std.mem.eql(u8, attr.value.attribute.attr, "mock");
    }
    return false;
}

/// Check if test name indicates pickle iterator test
/// These tests require pickle to reconstruct actual iterator types (via __reduce__)
/// which metal0 doesn't support yet
pub fn isPickleIteratorTest(test_name: []const u8) bool {
    return std.mem.indexOf(u8, test_name, "iterator_pickle") != null or
        std.mem.indexOf(u8, test_name, "reversed_pickle") != null;
}

/// Check if test requires advanced exception context manager support
/// (assertRaisesRegex with actual code execution)
pub fn requiresExceptionContextManager(test_name: []const u8) bool {
    // test_getitem_error uses assertRaisesRegex context manager
    // test_no_comdat_folding tests list + tuple subclass TypeError
    return std.mem.eql(u8, test_name, "test_getitem_error") or
        std.mem.eql(u8, test_name, "test_no_comdat_folding");
}

/// Check if test has nested classes inheriting from builtin types used in lambdas
/// Pattern: class CustomStr(str): pass; lambda b: CustomStr(b.decode())
pub fn hasNestedBuiltinSubclassInLambda(stmts: []const ast.Node) bool {
    // First, collect nested class names that inherit from builtins
    var nested_builtin_subclasses: [8][]const u8 = undefined;
    var count: usize = 0;
    for (stmts) |stmt| {
        if (stmt == .class_def) {
            const class = stmt.class_def;
            // bases is []const []const u8 (array of strings)
            for (class.bases) |base_name| {
                // Check if inheriting from builtin types that can't be properly subclassed yet
                if (std.mem.eql(u8, base_name, "str") or
                    std.mem.eql(u8, base_name, "bytes") or
                    std.mem.eql(u8, base_name, "bytearray"))
                {
                    if (count < nested_builtin_subclasses.len) {
                        nested_builtin_subclasses[count] = class.name;
                        count += 1;
                    }
                }
            }
        }
    }
    if (count == 0) return false;

    // Then check if any lambda uses these nested classes
    for (stmts) |stmt| {
        if (hasLambdaUsingClasses(stmt, nested_builtin_subclasses[0..count])) return true;
    }
    return false;
}

fn hasLambdaUsingClasses(node: ast.Node, class_names: []const []const u8) bool {
    return switch (node) {
        .lambda => |l| exprUsesClasses(l.body.*, class_names),
        .assign => |a| hasLambdaUsingClasses(a.value.*, class_names),
        .list => |lst| blk: {
            for (lst.elts) |e| if (hasLambdaUsingClasses(e, class_names)) break :blk true;
            break :blk false;
        },
        .tuple => |t| blk: {
            for (t.elts) |e| if (hasLambdaUsingClasses(e, class_names)) break :blk true;
            break :blk false;
        },
        .call => |c| blk: {
            for (c.args) |arg| if (hasLambdaUsingClasses(arg, class_names)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

fn exprUsesClasses(expr: ast.Node, class_names: []const []const u8) bool {
    return switch (expr) {
        .name => |n| blk: {
            for (class_names) |cn| if (std.mem.eql(u8, n.id, cn)) break :blk true;
            break :blk false;
        },
        .call => |c| exprUsesClasses(c.func.*, class_names) or blk: {
            for (c.args) |arg| if (exprUsesClasses(arg, class_names)) break :blk true;
            break :blk false;
        },
        .attribute => |a| exprUsesClasses(a.value.*, class_names),
        .binop => |b| exprUsesClasses(b.left.*, class_names) or exprUsesClasses(b.right.*, class_names),
        else => false,
    };
}

/// Convert Python default value to Zig code
pub fn convertDefaultToZig(default_expr: ast.Node) ?[]const u8 {
    return switch (default_expr) {
        .name => |n| PyNameToZig.get(n.id) orelse
            if (n.id.len > 0 and std.ascii.isUpper(n.id[0])) n.id else null,
        .constant => |c| switch (c.value) {
            .none => "null",
            .bool => |b| if (b) "true" else "false",
            else => null,
        },
        else => null,
    };
}

/// Check if test uses assertRaises with operator.eq/ne expecting TypeError
/// Pattern: self.assertRaises(TypeError, eq, x, y) where eq is from operator module
/// These tests rely on __eq__/ne = None raising TypeError at runtime, which
/// requires runtime operator dispatch that we don't support yet.
pub fn usesAssertRaisesWithOperatorEqNe(stmts: []const ast.Node) bool {
    for (stmts) |stmt| {
        if (stmtUsesAssertRaisesWithOperatorEqNe(stmt)) return true;
    }
    return false;
}

fn stmtUsesAssertRaisesWithOperatorEqNe(stmt: ast.Node) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprUsesAssertRaisesWithOperatorEqNe(e.value.*),
        .if_stmt => |i| blk: {
            for (i.body) |s| if (stmtUsesAssertRaisesWithOperatorEqNe(s)) break :blk true;
            for (i.else_body) |s| if (stmtUsesAssertRaisesWithOperatorEqNe(s)) break :blk true;
            break :blk false;
        },
        .for_stmt => |f| blk: {
            for (f.body) |s| if (stmtUsesAssertRaisesWithOperatorEqNe(s)) break :blk true;
            break :blk false;
        },
        .while_stmt => |w| blk: {
            for (w.body) |s| if (stmtUsesAssertRaisesWithOperatorEqNe(s)) break :blk true;
            break :blk false;
        },
        .try_stmt => |t| blk: {
            for (t.body) |s| if (stmtUsesAssertRaisesWithOperatorEqNe(s)) break :blk true;
            for (t.handlers) |h| {
                for (h.body) |s| if (stmtUsesAssertRaisesWithOperatorEqNe(s)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

fn exprUsesAssertRaisesWithOperatorEqNe(expr: ast.Node) bool {
    if (expr != .call) return false;
    const c = expr.call;
    // Check if it's self.assertRaises(TypeError, eq/ne, ...)
    if (c.func.* != .attribute) return false;
    const attr = c.func.attribute;
    if (!std.mem.eql(u8, attr.attr, "assertRaises")) return false;
    if (attr.value.* != .name or !std.mem.eql(u8, attr.value.name.id, "self")) return false;
    // Check args: (TypeError, eq/ne, ...)
    if (c.args.len < 2) return false;
    // First arg should be TypeError
    if (c.args[0] != .name or !std.mem.eql(u8, c.args[0].name.id, "TypeError")) return false;
    // Second arg should be eq or ne (from operator import eq, ne)
    if (c.args[1] != .name) return false;
    const op_name = c.args[1].name.id;
    return std.mem.eql(u8, op_name, "eq") or std.mem.eql(u8, op_name, "ne");
}

/// Check if test body uses CPython internal modules (_pylong, _decimal)
/// These modules are CPython-specific and not available in metal0
pub fn usesCPythonInternalModules(stmts: []const ast.Node) bool {
    for (stmts) |stmt| {
        if (stmtUsesCPythonInternalModules(stmt)) return true;
    }
    return false;
}

fn stmtUsesCPythonInternalModules(stmt: ast.Node) bool {
    switch (stmt) {
        .expr_stmt => |e| return exprUsesCPythonInternalModules(e.value.*),
        .assign => |a| {
            if (exprUsesCPythonInternalModules(a.value.*)) return true;
            for (a.targets) |target| {
                if (exprUsesCPythonInternalModules(target)) return true;
            }
            return false;
        },
        .aug_assign => |a| return exprUsesCPythonInternalModules(a.target.*) or exprUsesCPythonInternalModules(a.value.*),
        .ann_assign => |a| {
            if (a.value) |v| if (exprUsesCPythonInternalModules(v.*)) return true;
            return exprUsesCPythonInternalModules(a.target.*);
        },
        .if_stmt => |i| {
            if (exprUsesCPythonInternalModules(i.condition.*)) return true;
            for (i.body) |s| if (stmtUsesCPythonInternalModules(s)) return true;
            for (i.else_body) |s| if (stmtUsesCPythonInternalModules(s)) return true;
            return false;
        },
        .for_stmt => |f| {
            if (exprUsesCPythonInternalModules(f.iter.*)) return true;
            for (f.body) |s| if (stmtUsesCPythonInternalModules(s)) return true;
            if (f.orelse_body) |orelse_stmts| {
                for (orelse_stmts) |s| if (stmtUsesCPythonInternalModules(s)) return true;
            }
            return false;
        },
        .while_stmt => |w| {
            if (exprUsesCPythonInternalModules(w.condition.*)) return true;
            for (w.body) |s| if (stmtUsesCPythonInternalModules(s)) return true;
            if (w.orelse_body) |orelse_stmts| {
                for (orelse_stmts) |s| if (stmtUsesCPythonInternalModules(s)) return true;
            }
            return false;
        },
        .with_stmt => |wth| {
            if (exprUsesCPythonInternalModules(wth.context_expr.*)) return true;
            for (wth.body) |s| if (stmtUsesCPythonInternalModules(s)) return true;
            return false;
        },
        .try_stmt => |t| {
            for (t.body) |s| if (stmtUsesCPythonInternalModules(s)) return true;
            for (t.else_body) |s| if (stmtUsesCPythonInternalModules(s)) return true;
            for (t.finalbody) |s| if (stmtUsesCPythonInternalModules(s)) return true;
            for (t.handlers) |h| {
                for (h.body) |s| if (stmtUsesCPythonInternalModules(s)) return true;
            }
            return false;
        },
        .return_stmt => |r| {
            if (r.value) |v| return exprUsesCPythonInternalModules(v.*);
            return false;
        },
        else => return false,
    }
}

fn exprUsesCPythonInternalModules(expr: ast.Node) bool {
    switch (expr) {
        .name => |n| {
            // Check for direct usage of _pylong or _decimal
            return std.mem.eql(u8, n.id, "_pylong") or std.mem.eql(u8, n.id, "_decimal");
        },
        .attribute => |a| {
            // Check value for _pylong.xxx or _decimal.xxx
            if (a.value.* == .name) {
                const name = a.value.name.id;
                if (std.mem.eql(u8, name, "_pylong") or std.mem.eql(u8, name, "_decimal")) return true;
            }
            return exprUsesCPythonInternalModules(a.value.*);
        },
        .call => |c| {
            if (exprUsesCPythonInternalModules(c.func.*)) return true;
            for (c.args) |arg| {
                if (exprUsesCPythonInternalModules(arg)) return true;
            }
            for (c.keyword_args) |kw| {
                if (exprUsesCPythonInternalModules(kw.value)) return true;
            }
            return false;
        },
        .binop => |b| return exprUsesCPythonInternalModules(b.left.*) or exprUsesCPythonInternalModules(b.right.*),
        .unaryop => |u| return exprUsesCPythonInternalModules(u.operand.*),
        .compare => |c| {
            if (exprUsesCPythonInternalModules(c.left.*)) return true;
            for (c.comparators) |comp| {
                if (exprUsesCPythonInternalModules(comp)) return true;
            }
            return false;
        },
        .subscript => |s| {
            if (exprUsesCPythonInternalModules(s.value.*)) return true;
            switch (s.slice) {
                .index => |i| return exprUsesCPythonInternalModules(i.*),
                .slice => |sl| {
                    if (sl.lower) |l| if (exprUsesCPythonInternalModules(l.*)) return true;
                    if (sl.upper) |up| if (exprUsesCPythonInternalModules(up.*)) return true;
                    if (sl.step) |st| if (exprUsesCPythonInternalModules(st.*)) return true;
                    return false;
                },
            }
        },
        .if_expr => |i| return exprUsesCPythonInternalModules(i.condition.*) or exprUsesCPythonInternalModules(i.body.*) or exprUsesCPythonInternalModules(i.orelse_value.*),
        .list => |lst| {
            for (lst.elts) |e| {
                if (exprUsesCPythonInternalModules(e)) return true;
            }
            return false;
        },
        .tuple => |t| {
            for (t.elts) |e| {
                if (exprUsesCPythonInternalModules(e)) return true;
            }
            return false;
        },
        .set => |st| {
            for (st.elts) |e| {
                if (exprUsesCPythonInternalModules(e)) return true;
            }
            return false;
        },
        .dict => |d| {
            for (d.keys) |k| if (exprUsesCPythonInternalModules(k)) return true;
            for (d.values) |v| if (exprUsesCPythonInternalModules(v)) return true;
            return false;
        },
        else => return false,
    }
}
