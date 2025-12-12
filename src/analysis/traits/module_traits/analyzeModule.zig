//! analyzeModule - Analyze AST to extract ModuleInfo
//! USE: When compiling a local .py module, analyze it to extract function/constant metadata
//! CALL: module_traits.analyzeModule(ast, module_name, path, allocator)
//! RETURNS: ModuleInfo with all functions, constants, and classes

const std = @import("std");
const ast = @import("analysis.ast");
const function_traits = @import("analysis.function_traits");
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

    // Infer return type from: (1) annotation, (2) return statements
    const return_type = inferReturnType(func_def);

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
        .return_type_hint = return_type,
    };
}

/// Infer function return type from annotation or return statements
fn inferReturnType(func_def: ast.Node.FunctionDef) function_traits.TypeHint {
    // 1. Check explicit return type annotation: def add(a, b) -> int:
    if (func_def.return_type) |ret_ann| {
        return annotationToTypeHint(ret_ann);
    }

    // 2. Infer from return statements in body
    return inferReturnTypeFromBody(func_def.body);
}

/// Convert Python type annotation string to TypeHint
fn annotationToTypeHint(annotation: []const u8) function_traits.TypeHint {
    if (std.mem.eql(u8, annotation, "int")) return .int;
    if (std.mem.eql(u8, annotation, "float")) return .float;
    if (std.mem.eql(u8, annotation, "bool")) return .bool;
    if (std.mem.eql(u8, annotation, "str")) return .string;
    if (std.mem.eql(u8, annotation, "list")) return .list;
    if (std.mem.eql(u8, annotation, "dict")) return .dict;
    if (std.mem.eql(u8, annotation, "tuple")) return .tuple;
    if (std.mem.eql(u8, annotation, "None")) return .none;
    if (std.mem.eql(u8, annotation, "void")) return .void;
    if (std.mem.eql(u8, annotation, "Any")) return .any;
    return .object; // Unknown annotation
}

/// Infer return type from return statements in function body
fn inferReturnTypeFromBody(body: []const ast.Node) function_traits.TypeHint {
    for (body) |stmt| {
        if (stmt == .return_stmt) {
            if (stmt.return_stmt.value) |val| {
                return inferExprType(val.*);
            }
            return .none; // return without value -> None
        }
        // Check nested blocks for return statements
        const nested_type = switch (stmt) {
            .if_stmt => |i| blk: {
                const body_type = inferReturnTypeFromBody(i.body);
                if (body_type != .object) break :blk body_type;
                break :blk inferReturnTypeFromBody(i.else_body);
            },
            .for_stmt => |f| inferReturnTypeFromBody(f.body),
            .while_stmt => |w| inferReturnTypeFromBody(w.body),
            .try_stmt => |t| inferReturnTypeFromBody(t.body),
            .with_stmt => |w| inferReturnTypeFromBody(w.body),
            else => function_traits.TypeHint.object,
        };
        if (nested_type != .object) return nested_type;
    }
    return .object; // No return found or unknown
}

/// Infer type of an expression
fn inferExprType(expr: ast.Node) function_traits.TypeHint {
    return switch (expr) {
        .constant => |c| switch (c.value) {
            .int => .int,
            .float => .float,
            .bool => .bool,
            .string => .string,
            .none => .none,
            else => .object,
        },
        .list => .list,
        .dict => .dict,
        .tuple => .tuple,
        .binop => |b| inferBinopType(b),
        .name => .object, // Variable - can't know type statically
        .call => .object, // Function call - need more context
        .fstring => .string, // f-string produces string
        else => .object,
    };
}

/// Infer type of binary operation
fn inferBinopType(binop: ast.Node.BinOp) function_traits.TypeHint {
    const left_type = inferExprType(binop.left.*);
    const right_type = inferExprType(binop.right.*);

    // Arithmetic: int op int -> int, int op float -> float, float op float -> float
    if (left_type == .float or right_type == .float) return .float;
    if (left_type == .int and right_type == .int) {
        // Division always returns float in Python 3
        if (binop.op == .Div) return .float;
        return .int;
    }

    // String: str + str -> str, str * int -> str
    if (left_type == .string and right_type == .string) return .string;
    if (left_type == .string and right_type == .int) return .string;

    // List: list + list -> list
    if (left_type == .list and right_type == .list) return .list;

    return .object;
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
        .assign => |a| blk: {
            if (exprContainsAwait(a.value.*)) break :blk true;
            for (a.targets) |t| if (exprContainsAwait(t)) break :blk true;
            break :blk false;
        },
        .aug_assign => |a| exprContainsAwait(a.target.*) or exprContainsAwait(a.value.*),
        .return_stmt => |r| if (r.value) |v| exprContainsAwait(v.*) else false,
        .if_stmt => |i| blk: {
            if (exprContainsAwait(i.condition.*)) break :blk true;
            for (i.body) |s| if (stmtContainsAwait(s)) break :blk true;
            for (i.else_body) |s| if (stmtContainsAwait(s)) break :blk true;
            break :blk false;
        },
        .for_stmt => |f| blk: {
            if (exprContainsAwait(f.iter.*)) break :blk true;
            for (f.body) |s| if (stmtContainsAwait(s)) break :blk true;
            if (f.orelse_body) |ob| for (ob) |s| if (stmtContainsAwait(s)) break :blk true;
            break :blk false;
        },
        .while_stmt => |w| blk: {
            if (exprContainsAwait(w.condition.*)) break :blk true;
            for (w.body) |s| if (stmtContainsAwait(s)) break :blk true;
            if (w.orelse_body) |ob| for (ob) |s| if (stmtContainsAwait(s)) break :blk true;
            break :blk false;
        },
        .try_stmt => |t| blk: {
            for (t.body) |s| if (stmtContainsAwait(s)) break :blk true;
            for (t.handlers) |h| for (h.body) |s| if (stmtContainsAwait(s)) break :blk true;
            for (t.else_body) |s| if (stmtContainsAwait(s)) break :blk true;
            for (t.finalbody) |s| if (stmtContainsAwait(s)) break :blk true;
            break :blk false;
        },
        .with_stmt => |wth| blk: {
            if (exprContainsAwait(wth.context_expr.*)) break :blk true;
            for (wth.body) |s| if (stmtContainsAwait(s)) break :blk true;
            break :blk false;
        },
        .match_stmt => |m| blk: {
            if (exprContainsAwait(m.subject.*)) break :blk true;
            for (m.cases) |case| {
                if (case.guard) |g| if (exprContainsAwait(g.*)) break :blk true;
                for (case.body) |s| if (stmtContainsAwait(s)) break :blk true;
            }
            break :blk false;
        },
        .assert_stmt => |a| blk: {
            if (exprContainsAwait(a.condition.*)) break :blk true;
            if (a.msg) |msg| if (exprContainsAwait(msg.*)) break :blk true;
            break :blk false;
        },
        .ann_assign => |a| if (a.value) |v| exprContainsAwait(v.*) else false,
        else => false,
    };
}

fn exprContainsAwait(expr: ast.Node) bool {
    return switch (expr) {
        .await_expr => true,
        .call => |c| blk: {
            if (exprContainsAwait(c.func.*)) break :blk true;
            for (c.args) |arg| if (exprContainsAwait(arg)) break :blk true;
            for (c.keyword_args) |kw| if (exprContainsAwait(kw.value)) break :blk true;
            break :blk false;
        },
        .binop => |b| exprContainsAwait(b.left.*) or exprContainsAwait(b.right.*),
        .unaryop => |u| exprContainsAwait(u.operand.*),
        .boolop => |bo| blk: {
            for (bo.values) |v| if (exprContainsAwait(v)) break :blk true;
            break :blk false;
        },
        .compare => |cmp| blk: {
            if (exprContainsAwait(cmp.left.*)) break :blk true;
            for (cmp.comparators) |c| if (exprContainsAwait(c)) break :blk true;
            break :blk false;
        },
        .subscript => |s| blk: {
            if (exprContainsAwait(s.value.*)) break :blk true;
            switch (s.slice) {
                .index => |idx| break :blk exprContainsAwait(idx.*),
                .slice => |range| {
                    if (range.lower) |l| if (exprContainsAwait(l.*)) break :blk true;
                    if (range.upper) |u| if (exprContainsAwait(u.*)) break :blk true;
                    if (range.step) |st| if (exprContainsAwait(st.*)) break :blk true;
                    break :blk false;
                },
            }
        },
        .attribute => |a| exprContainsAwait(a.value.*),
        .if_expr => |ie| exprContainsAwait(ie.condition.*) or exprContainsAwait(ie.body.*) or exprContainsAwait(ie.orelse_value.*),
        .list => |l| blk: {
            for (l.elts) |e| if (exprContainsAwait(e)) break :blk true;
            break :blk false;
        },
        .tuple => |t| blk: {
            for (t.elts) |e| if (exprContainsAwait(e)) break :blk true;
            break :blk false;
        },
        .dict => |d| blk: {
            for (d.keys) |k| if (exprContainsAwait(k)) break :blk true;
            for (d.values) |v| if (exprContainsAwait(v)) break :blk true;
            break :blk false;
        },
        .fstring => |fstr| blk: {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |e| if (exprContainsAwait(e.node.*)) break :blk true,
                    .format_expr => |fe| if (exprContainsAwait(fe.expr.*)) break :blk true,
                    .conv_expr => |ce| if (exprContainsAwait(ce.expr.*)) break :blk true,
                    .literal => {},
                }
            }
            break :blk false;
        },
        .listcomp => |lc| blk: {
            if (exprContainsAwait(lc.elt.*)) break :blk true;
            for (lc.generators) |gen| {
                if (exprContainsAwait(gen.iter.*)) break :blk true;
                for (gen.ifs) |cond| if (exprContainsAwait(cond)) break :blk true;
            }
            break :blk false;
        },
        .dictcomp => |dc| blk: {
            if (exprContainsAwait(dc.key.*) or exprContainsAwait(dc.value.*)) break :blk true;
            for (dc.generators) |gen| {
                if (exprContainsAwait(gen.iter.*)) break :blk true;
                for (gen.ifs) |cond| if (exprContainsAwait(cond)) break :blk true;
            }
            break :blk false;
        },
        .genexp => |ge| blk: {
            if (exprContainsAwait(ge.elt.*)) break :blk true;
            for (ge.generators) |gen| {
                if (exprContainsAwait(gen.iter.*)) break :blk true;
                for (gen.ifs) |cond| if (exprContainsAwait(cond)) break :blk true;
            }
            break :blk false;
        },
        .lambda => |lam| exprContainsAwait(lam.body.*),
        .starred => |st| exprContainsAwait(st.value.*),
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
        .if_stmt => |i| blk: {
            for (i.body) |s| if (stmtContainsYield(s)) break :blk true;
            for (i.else_body) |s| if (stmtContainsYield(s)) break :blk true;
            break :blk false;
        },
        .for_stmt => |f| blk: {
            for (f.body) |s| if (stmtContainsYield(s)) break :blk true;
            if (f.orelse_body) |ob| for (ob) |s| if (stmtContainsYield(s)) break :blk true;
            break :blk false;
        },
        .while_stmt => |w| blk: {
            for (w.body) |s| if (stmtContainsYield(s)) break :blk true;
            if (w.orelse_body) |ob| for (ob) |s| if (stmtContainsYield(s)) break :blk true;
            break :blk false;
        },
        .try_stmt => |t| blk: {
            for (t.body) |s| if (stmtContainsYield(s)) break :blk true;
            for (t.handlers) |h| for (h.body) |s| if (stmtContainsYield(s)) break :blk true;
            for (t.else_body) |s| if (stmtContainsYield(s)) break :blk true;
            for (t.finalbody) |s| if (stmtContainsYield(s)) break :blk true;
            break :blk false;
        },
        .with_stmt => |wth| blk: {
            for (wth.body) |s| if (stmtContainsYield(s)) break :blk true;
            break :blk false;
        },
        .match_stmt => |m| blk: {
            for (m.cases) |case| {
                for (case.body) |s| if (stmtContainsYield(s)) break :blk true;
            }
            break :blk false;
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
            if (f.orelse_body) |ob| for (ob) |s| if (stmtCanError(s)) break :blk true;
            break :blk false;
        },
        .while_stmt => |w| blk: {
            if (exprCanError(w.condition.*)) break :blk true;
            for (w.body) |s| if (stmtCanError(s)) break :blk true;
            if (w.orelse_body) |ob| for (ob) |s| if (stmtCanError(s)) break :blk true;
            break :blk false;
        },
        .with_stmt => |w| blk: {
            if (exprCanError(w.context_expr.*)) break :blk true;
            for (w.body) |s| if (stmtCanError(s)) break :blk true;
            break :blk false;
        },
        .match_stmt => |m| blk: {
            if (exprCanError(m.subject.*)) break :blk true;
            for (m.cases) |case| {
                if (case.guard) |g| if (exprCanError(g.*)) break :blk true;
                for (case.body) |s| if (stmtCanError(s)) break :blk true;
            }
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
            for (c.keyword_args) |kw| if (exprCanError(kw.value)) break :blk true;
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
        .boolop => |bo| blk: {
            for (bo.values) |v| if (exprCanError(v)) break :blk true;
            break :blk false;
        },
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
        .fstring => |fstr| blk: {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |e| if (exprCanError(e.node.*)) break :blk true,
                    .format_expr => |fe| if (exprCanError(fe.expr.*)) break :blk true,
                    .conv_expr => |ce| if (exprCanError(ce.expr.*)) break :blk true,
                    .literal => {},
                }
            }
            break :blk false;
        },
        .listcomp => |lc| blk: {
            if (exprCanError(lc.elt.*)) break :blk true;
            for (lc.generators) |gen| {
                if (exprCanError(gen.iter.*)) break :blk true;
                for (gen.ifs) |cond| if (exprCanError(cond)) break :blk true;
            }
            break :blk false;
        },
        .dictcomp => |dc| blk: {
            if (exprCanError(dc.key.*) or exprCanError(dc.value.*)) break :blk true;
            for (dc.generators) |gen| {
                if (exprCanError(gen.iter.*)) break :blk true;
                for (gen.ifs) |cond| if (exprCanError(cond)) break :blk true;
            }
            break :blk false;
        },
        .genexp => |ge| blk: {
            if (exprCanError(ge.elt.*)) break :blk true;
            for (ge.generators) |gen| {
                if (exprCanError(gen.iter.*)) break :blk true;
                for (gen.ifs) |cond| if (exprCanError(cond)) break :blk true;
            }
            break :blk false;
        },
        .lambda => |lam| exprCanError(lam.body.*),
        .starred => |st| exprCanError(st.value.*),
        else => false,
    };
}
