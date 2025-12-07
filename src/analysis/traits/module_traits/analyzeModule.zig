//! analyzeModule - Analyze AST to extract ModuleInfo
//! USE: When compiling a local .py module, analyze it to extract function/constant metadata
//! CALL: module_traits.analyzeModule(ast, module_name, path, allocator)
//! RETURNS: ModuleInfo with all functions, constants, and classes

const std = @import("std");
const ast = @import("analysis.ast");
const function_traits = @import("../function_traits.zig");
const module_traits = @import("../module_traits.zig");
const hashmap_helper = @import("utils.hashmap_helper");

/// Analyze a module's AST and extract metadata for all exports
pub fn analyzeModule(
    module: ast.Node.Module,
    module_name: []const u8,
    path: []const u8,
    allocator: std.mem.Allocator,
) !module_traits.ModuleInfo {
    var info = module_traits.ModuleInfo.init(allocator, module_name, path, true);

    for (module.body) |stmt| {
        switch (stmt) {
            .function_def => |func_def| {
                // Analyze function and store traits
                const traits = analyzeFunction(func_def, module_name);
                const name_copy = try allocator.dupe(u8, func_def.name);
                try info.functions.put(name_copy, traits);
            },
            .assign => |assign_stmt| {
                // Look for module-level constant assignments
                // e.g., VERSION = "1.0.0"
                if (assign_stmt.targets.len == 1 and assign_stmt.targets[0] == .name) {
                    const const_name = assign_stmt.targets[0].name.id;
                    if (isConstantName(const_name)) {
                        const meta = analyzeConstant(const_name, assign_stmt.value.*);
                        const name_copy = try allocator.dupe(u8, const_name);
                        try info.constants.put(name_copy, meta);
                    }
                }
            },
            .class_def => |class_def| {
                // Analyze class and its methods
                const class_meta = try analyzeClass(class_def, module_name, allocator);
                const name_copy = try allocator.dupe(u8, class_def.name);
                try info.classes.put(name_copy, class_meta);
            },
            else => {},
        }
    }

    return info;
}

/// Analyze a function definition to extract traits
fn analyzeFunction(func_def: ast.Node.FunctionDef, module_name: []const u8) function_traits.FunctionTraits {
    // NOTE: In module mode, ALL functions get an allocator parameter (see generators.zig:38)
    // So for module functions, needs_allocator is always true regardless of body analysis
    const needs_alloc = true; // Module functions always have allocator param

    return .{
        .ref = .{
            .module = module_name,
            .name = func_def.name,
            .class_name = null,
        },
        .needs_allocator = needs_alloc,
        .can_error = analyzeCanError(func_def.body),
        .has_await = containsAwait(func_def.body),
        .is_generator = containsYield(func_def.body),
    };
}

/// Check if a name is a constant (UPPER_CASE convention)
fn isConstantName(name: []const u8) bool {
    if (name.len == 0) return false;
    // Constants are typically ALL_CAPS or start with uppercase
    // Common patterns: VERSION, __version__, MAX_SIZE
    if (name.len >= 2 and name[0] == '_' and name[1] == '_') {
        // Dunder names like __version__
        return true;
    }
    // Check if ALL_CAPS
    for (name) |c| {
        if (c >= 'a' and c <= 'z') return false;
    }
    return true;
}

/// Analyze a constant assignment
fn analyzeConstant(name: []const u8, value: ast.Node) module_traits.ConstantMeta {
    var meta = module_traits.ConstantMeta{
        .name = name,
        .value_type = .unknown,
        .comptime_value = null,
    };

    switch (value) {
        .constant => |c| {
            switch (c.value) {
                .int => |i| {
                    meta.value_type = .int;
                    meta.comptime_value = .{ .int = i };
                },
                .float => |f| {
                    meta.value_type = .float;
                    meta.comptime_value = .{ .float = f };
                },
                .string => |s| {
                    meta.value_type = .string;
                    meta.comptime_value = .{ .string = s };
                },
                .bool => |b| {
                    meta.value_type = .boolean;
                    meta.comptime_value = .{ .boolean = b };
                },
                .none => {
                    meta.value_type = .none;
                    meta.comptime_value = .{ .none = {} };
                },
                else => {},
            }
        },
        else => {},
    }

    return meta;
}

/// Analyze a class definition
fn analyzeClass(class_def: ast.Node.ClassDef, module_name: []const u8, allocator: std.mem.Allocator) !module_traits.ClassMeta {
    var class_meta = module_traits.ClassMeta{
        .name = class_def.name,
        .methods = hashmap_helper.StringHashMap(function_traits.FunctionTraits).init(allocator),
        .class_vars = hashmap_helper.StringHashMap(module_traits.ConstantMeta).init(allocator),
    };

    for (class_def.body) |stmt| {
        switch (stmt) {
            .function_def => |method_def| {
                var traits = analyzeFunction(method_def, module_name);
                traits.ref.class_name = class_def.name;
                const name_copy = try allocator.dupe(u8, method_def.name);
                try class_meta.methods.put(name_copy, traits);
            },
            .assign => |assign_stmt| {
                if (assign_stmt.targets.len == 1 and assign_stmt.targets[0] == .name) {
                    const var_name = assign_stmt.targets[0].name.id;
                    const meta = analyzeConstant(var_name, assign_stmt.value.*);
                    const name_copy = try allocator.dupe(u8, var_name);
                    try class_meta.class_vars.put(name_copy, meta);
                }
            },
            else => {},
        }
    }

    return class_meta;
}

/// Check if function body contains await
fn containsAwait(body: []const ast.Node) bool {
    for (body) |stmt| {
        if (stmtContainsAwait(stmt)) return true;
    }
    return false;
}

fn stmtContainsAwait(stmt: ast.Node) bool {
    return switch (stmt) {
        .await_expr => true,
        .expr_stmt => |e| exprContainsAwait(e.value.*),
        .assign => |a| exprContainsAwait(a.value.*),
        .if_stmt => |i| {
            for (i.body) |s| if (stmtContainsAwait(s)) return true;
            for (i.else_body) |s| if (stmtContainsAwait(s)) return true;
            return false;
        },
        .for_stmt => |f| {
            for (f.body) |s| if (stmtContainsAwait(s)) return true;
            return false;
        },
        .while_stmt => |w| {
            for (w.body) |s| if (stmtContainsAwait(s)) return true;
            return false;
        },
        else => false,
    };
}

fn exprContainsAwait(expr: ast.Node) bool {
    return switch (expr) {
        .await_expr => true,
        .call => |c| {
            for (c.args) |arg| if (exprContainsAwait(arg)) return true;
            return false;
        },
        .binop => |b| exprContainsAwait(b.left.*) or exprContainsAwait(b.right.*),
        else => false,
    };
}

/// Check if function body contains yield
fn containsYield(body: []const ast.Node) bool {
    for (body) |stmt| {
        if (stmtContainsYield(stmt)) return true;
    }
    return false;
}

fn stmtContainsYield(stmt: ast.Node) bool {
    return switch (stmt) {
        .yield_stmt, .yield_from_stmt => true,
        .expr_stmt => |e| e.value.* == .yield_stmt or e.value.* == .yield_from_stmt,
        .if_stmt => |i| {
            for (i.body) |s| if (stmtContainsYield(s)) return true;
            for (i.else_body) |s| if (stmtContainsYield(s)) return true;
            return false;
        },
        .for_stmt => |f| {
            for (f.body) |s| if (stmtContainsYield(s)) return true;
            return false;
        },
        .while_stmt => |w| {
            for (w.body) |s| if (stmtContainsYield(s)) return true;
            return false;
        },
        else => false,
    };
}

/// Check if function body can raise errors (raise stmt, try block, or error-raising builtins)
fn analyzeCanError(body: []const ast.Node) bool {
    for (body) |stmt| {
        if (stmtCanError(stmt)) return true;
    }
    return false;
}

fn stmtCanError(stmt: ast.Node) bool {
    return switch (stmt) {
        .raise_stmt => true,
        .try_stmt => true,
        .assert_stmt => true,
        .expr_stmt => |e| exprCanError(e.value.*),
        .assign => |a| exprCanError(a.value.*),
        .aug_assign => |a| exprCanError(a.value.*),
        .return_stmt => |r| if (r.value) |v| exprCanError(v.*) else false,
        .if_stmt => |i| blk: {
            if (exprCanError(i.condition.*)) break :blk true;
            for (i.body) |s| if (stmtCanError(s)) break :blk true;
            for (i.else_body) |s| if (stmtCanError(s)) break :blk true;
            break :blk false;
        },
        .for_stmt => |f| blk: {
            if (exprCanError(f.iter.*)) break :blk true;
            for (f.body) |s| if (stmtCanError(s)) break :blk true;
            break :blk false;
        },
        .while_stmt => |w| blk: {
            if (exprCanError(w.condition.*)) break :blk true;
            for (w.body) |s| if (stmtCanError(s)) break :blk true;
            break :blk false;
        },
        .with_stmt => |w| blk: {
            if (exprCanError(w.context_expr.*)) break :blk true;
            for (w.body) |s| if (stmtCanError(s)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

/// Error-raising builtin functions
const ErrorFunctions = std.StaticStringMap(void).initComptime(.{
    .{ "int", {} }, // int("abc") raises ValueError
    .{ "float", {} }, // float("abc") raises ValueError
    .{ "open", {} }, // FileNotFoundError, PermissionError
    .{ "eval", {} }, // RuntimeError
    .{ "exec", {} }, // RuntimeError
    .{ "next", {} }, // StopIteration
    .{ "getattr", {} }, // AttributeError
    .{ "input", {} }, // EOFError
});

fn exprCanError(expr: ast.Node) bool {
    return switch (expr) {
        .call => |c| blk: {
            // Check if calling an error-raising function
            if (c.func.* == .name) {
                if (ErrorFunctions.has(c.func.name.id)) break :blk true;
            }
            // Check arguments
            for (c.args) |arg| if (exprCanError(arg)) break :blk true;
            break :blk exprCanError(c.func.*);
        },
        .subscript => |s| blk: {
            // Indexing can raise IndexError/KeyError
            if (s.slice == .index) break :blk true;
            break :blk exprCanError(s.value.*);
        },
        .binop => |b| blk: {
            // Division can raise ZeroDivisionError
            if (b.op == .Div or b.op == .FloorDiv or b.op == .Mod) break :blk true;
            break :blk exprCanError(b.left.*) or exprCanError(b.right.*);
        },
        .attribute => |a| exprCanError(a.value.*),
        .unaryop => |u| exprCanError(u.operand.*),
        .compare => |c| blk: {
            if (exprCanError(c.left.*)) break :blk true;
            for (c.comparators) |cmp| if (exprCanError(cmp)) break :blk true;
            break :blk false;
        },
        .if_expr => |i| exprCanError(i.condition.*) or exprCanError(i.body.*) or exprCanError(i.orelse_value.*),
        .list => |l| blk: {
            for (l.elts) |e| if (exprCanError(e)) break :blk true;
            break :blk false;
        },
        .tuple => |t| blk: {
            for (t.elts) |e| if (exprCanError(e)) break :blk true;
            break :blk false;
        },
        .dict => |d| blk: {
            for (d.keys) |k| if (exprCanError(k)) break :blk true;
            for (d.values) |v| if (exprCanError(v)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}
