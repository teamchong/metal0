/// Test skip detection for unittest classes
const std = @import("std");
const ast = @import("ast");
const hashmap_helper = @import("hashmap_helper");

const TypeParamDefaults = std.StaticStringMap(void).initComptime(.{
    .{ "float", {} }, .{ "int", {} }, .{ "str", {} }, .{ "bool", {} }, .{ "complex", {} },
    .{ "list", {} }, .{ "dict", {} }, .{ "set", {} }, .{ "tuple", {} }, .{ "bytes", {} }, .{ "type", {} },
});

const PyNameToZig = std.StaticStringMap([]const u8).initComptime(.{
    .{ "float", "f64" }, .{ "int", "i64" }, .{ "str", "[]const u8" }, .{ "bool", "bool" },
    .{ "None", "null" }, .{ "True", "true" }, .{ "False", "false" },
    .{ "complex", "runtime.Complex" }, .{ "repr", "runtime.repr" },
});

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
