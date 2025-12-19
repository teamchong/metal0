/// Unified Variable Hoisting for Python->Zig Scope Conversion
/// MIGRATED TO ZIGBUILDER
///
/// Python has function-level scoping - variables assigned anywhere in a function
/// are visible throughout. Zig has block-level scoping - variables in if/for/while/try
/// blocks are not visible outside.
///
/// This module provides a SINGLE SOURCE OF TRUTH for:
/// 1. Detecting if init expressions are safe (no forward references)
/// 2. Inferring fallback types when @TypeOf can't be used
/// 3. Emitting hoisted variable declarations consistently
///
/// Used by both genFunctionBody (top-level functions) and genMethodBody (class methods).
const std = @import("std");
const ast = @import("analysis.ast");
const hashmap_helper = @import("utils.hashmap_helper");
const zig_keywords = @import("utils.zig_keywords");
const scope_analyzer = @import("scope_analyzer.zig");
const container_traits = @import("../../../../analysis/traits/container_traits.zig");

const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const VarTypeContext = @import("var_type_context.zig").VarTypeContext;

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}


/// Check if an expression contains a reference to a specific variable name.
/// Used to detect self-references in init expressions (e.g., `line = line.strip()`
/// where `line` is both the target and referenced in the value).
pub fn exprContainsName(expr: *const ast.Node, var_name: []const u8) bool {
    return switch (expr.*) {
        .name => |n| std.mem.eql(u8, n.id, var_name),
        .attribute => |a| exprContainsName(a.value, var_name),
        .call => |c| {
            if (exprContainsName(c.func, var_name)) return true;
            for (c.args) |arg| {
                if (exprContainsNameNode(arg, var_name)) return true;
            }
            for (c.keyword_args) |kwarg| {
                if (exprContainsNameNode(kwarg.value, var_name)) return true;
            }
            return false;
        },
        .binop => |b| exprContainsName(b.left, var_name) or exprContainsName(b.right, var_name),
        .unaryop => |u| exprContainsName(u.operand, var_name),
        .subscript => |s| {
            if (exprContainsName(s.value, var_name)) return true;
            return switch (s.slice) {
                .index => |idx| exprContainsName(idx, var_name),
                .slice => |sl| {
                    if (sl.lower) |l| if (exprContainsName(l, var_name)) return true;
                    if (sl.upper) |u| if (exprContainsName(u, var_name)) return true;
                    if (sl.step) |st| if (exprContainsName(st, var_name)) return true;
                    return false;
                },
            };
        },
        .compare => |cmp| {
            if (exprContainsName(cmp.left, var_name)) return true;
            for (cmp.comparators) |c| {
                if (exprContainsNameNode(c, var_name)) return true;
            }
            return false;
        },
        .tuple => |t| {
            for (t.elts) |elt| {
                if (exprContainsNameNode(elt, var_name)) return true;
            }
            return false;
        },
        .list => |l| {
            for (l.elts) |elt| {
                if (exprContainsNameNode(elt, var_name)) return true;
            }
            return false;
        },
        .if_expr => |ie| {
            return exprContainsName(ie.condition, var_name) or
                exprContainsName(ie.body, var_name) or
                exprContainsName(ie.orelse_value, var_name);
        },
        .boolop => |bo| {
            for (bo.values) |v| {
                if (exprContainsNameNode(v, var_name)) return true;
            }
            return false;
        },
        .dict => |d| {
            for (d.keys) |k| {
                if (exprContainsNameNode(k, var_name)) return true;
            }
            for (d.values) |v| {
                if (exprContainsNameNode(v, var_name)) return true;
            }
            return false;
        },
        .fstring => |fstr| {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |e| if (exprContainsName(e.node, var_name)) return true,
                    .format_expr => |fe| if (exprContainsName(fe.expr, var_name)) return true,
                    .conv_expr => |ce| if (exprContainsName(ce.expr, var_name)) return true,
                    .literal => {},
                }
            }
            return false;
        },
        .listcomp => |lc| {
            if (exprContainsName(lc.elt, var_name)) return true;
            for (lc.generators) |gen| {
                if (exprContainsName(gen.iter, var_name)) return true;
                for (gen.ifs) |cond| {
                    if (exprContainsNameNode(cond, var_name)) return true;
                }
            }
            return false;
        },
        .dictcomp => |dc| {
            if (exprContainsName(dc.key, var_name) or exprContainsName(dc.value, var_name)) return true;
            for (dc.generators) |gen| {
                if (exprContainsName(gen.iter, var_name)) return true;
                for (gen.ifs) |cond| {
                    if (exprContainsNameNode(cond, var_name)) return true;
                }
            }
            return false;
        },
        .genexp => |ge| {
            if (exprContainsName(ge.elt, var_name)) return true;
            for (ge.generators) |gen| {
                if (exprContainsName(gen.iter, var_name)) return true;
                for (gen.ifs) |cond| {
                    if (exprContainsNameNode(cond, var_name)) return true;
                }
            }
            return false;
        },
        .lambda => |lam| exprContainsName(lam.body, var_name),
        .starred => |st| exprContainsName(st.value, var_name),
        else => false,
    };
}

/// Helper for non-pointer ast.Node
fn exprContainsNameNode(node: ast.Node, var_name: []const u8) bool {
    return switch (node) {
        .name => |n| std.mem.eql(u8, n.id, var_name),
        .attribute => |a| exprContainsName(a.value, var_name),
        .call => |c| {
            if (exprContainsName(c.func, var_name)) return true;
            for (c.args) |arg| {
                if (exprContainsNameNode(arg, var_name)) return true;
            }
            for (c.keyword_args) |kw| {
                if (exprContainsNameNode(kw.value, var_name)) return true;
            }
            return false;
        },
        .binop => |b| exprContainsName(b.left, var_name) or exprContainsName(b.right, var_name),
        .unaryop => |u| exprContainsName(u.operand, var_name),
        .boolop => |bo| {
            for (bo.values) |v| {
                if (exprContainsNameNode(v, var_name)) return true;
            }
            return false;
        },
        .compare => |cmp| {
            if (exprContainsName(cmp.left, var_name)) return true;
            for (cmp.comparators) |c| {
                if (exprContainsNameNode(c, var_name)) return true;
            }
            return false;
        },
        .subscript => |s| {
            if (exprContainsName(s.value, var_name)) return true;
            switch (s.slice) {
                .index => |idx| return exprContainsName(idx, var_name),
                .slice => |range| {
                    if (range.lower) |l| if (exprContainsName(l, var_name)) return true;
                    if (range.upper) |u| if (exprContainsName(u, var_name)) return true;
                    if (range.step) |st| if (exprContainsName(st, var_name)) return true;
                    return false;
                },
            }
        },
        .if_expr => |ie| exprContainsName(ie.condition, var_name) or exprContainsName(ie.body, var_name) or exprContainsName(ie.orelse_value, var_name),
        .list => |l| {
            for (l.elts) |e| {
                if (exprContainsNameNode(e, var_name)) return true;
            }
            return false;
        },
        .tuple => |t| {
            for (t.elts) |e| {
                if (exprContainsNameNode(e, var_name)) return true;
            }
            return false;
        },
        .dict => |d| {
            for (d.keys) |k| {
                if (exprContainsNameNode(k, var_name)) return true;
            }
            for (d.values) |v| {
                if (exprContainsNameNode(v, var_name)) return true;
            }
            return false;
        },
        .fstring => |fstr| {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |e| if (exprContainsName(e.node, var_name)) return true,
                    .format_expr => |fe| if (exprContainsName(fe.expr, var_name)) return true,
                    .conv_expr => |ce| if (exprContainsName(ce.expr, var_name)) return true,
                    .literal => {},
                }
            }
            return false;
        },
        .listcomp => |lc| {
            if (exprContainsName(lc.elt, var_name)) return true;
            for (lc.generators) |gen| {
                if (exprContainsName(gen.iter, var_name)) return true;
                for (gen.ifs) |cond| {
                    if (exprContainsNameNode(cond, var_name)) return true;
                }
            }
            return false;
        },
        .dictcomp => |dc| {
            if (exprContainsName(dc.key, var_name) or exprContainsName(dc.value, var_name)) return true;
            for (dc.generators) |gen| {
                if (exprContainsName(gen.iter, var_name)) return true;
                for (gen.ifs) |cond| {
                    if (exprContainsNameNode(cond, var_name)) return true;
                }
            }
            return false;
        },
        .genexp => |ge| {
            if (exprContainsName(ge.elt, var_name)) return true;
            for (ge.generators) |gen| {
                if (exprContainsName(gen.iter, var_name)) return true;
                for (gen.ifs) |cond| {
                    if (exprContainsNameNode(cond, var_name)) return true;
                }
            }
            return false;
        },
        .lambda => |lam| exprContainsName(lam.body, var_name),
        .starred => |st| exprContainsName(st.value, var_name),
        .constant => false,
        else => false,
    };
}

/// Check if a name looks like a module-level constant (ALL_CAPS).
/// Python convention: CONSTANT_NAME, not localVariable
fn isAllCapsConstant(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |c| {
        // Allow uppercase letters, digits, and underscores
        if (!(c >= 'A' and c <= 'Z') and !(c >= '0' and c <= '9') and c != '_') {
            return false;
        }
    }
    // Must start with a letter (not digit)
    return name[0] >= 'A' and name[0] <= 'Z';
}

/// Check if a name is a Python builtin exception/type (not a user class).
/// These are things like TypeError, ValueError, etc. that shouldn't be treated
/// as local class constructors for type inference purposes.
fn isBuiltinException(name: []const u8) bool {
    const builtins = [_][]const u8{
        "TypeError",      "ValueError",     "KeyError",       "IndexError",
        "RuntimeError",   "ZeroDivisionError", "AttributeError", "ImportError",
        "FileNotFoundError", "OSError",     "IOError",        "NameError",
        "SyntaxError",    "AssertionError", "StopIteration",  "GeneratorExit",
        "Exception",      "BaseException",  "Warning",        "DeprecationWarning",
        "UserWarning",    "FutureWarning",  "PendingDeprecationWarning",
        "SyntaxWarning",  "RuntimeWarning", "ResourceWarning", "UnicodeError",
        "UnicodeDecodeError", "UnicodeEncodeError", "NotImplementedError",
        "OverflowError",  "RecursionError", "SystemExit",     "KeyboardInterrupt",
        // Also builtin types that start with uppercase
        "True",           "False",          "None",
    };
    for (builtins) |b| {
        if (std.mem.eql(u8, name, b)) return true;
    }
    return false;
}

/// Check if an init expression only references safe variables (no forward refs).
/// Safe means: literals, function parameters, or previously-declared variables.
/// This determines whether we can use @TypeOf(init_expr) safely.
pub fn initExprIsSafe(init: *const ast.Node, safe_vars: *const hashmap_helper.StringHashMap(void)) bool {
    return switch (init.*) {
        // Literals are always safe
        .constant => true,

        // Names are safe if they're in safe_vars (params or already-hoisted)
        // OR if they look like ALL_CAPS constants (module-level constants)
        .name => |n| safe_vars.contains(n.id) or isAllCapsConstant(n.id),

        // Function calls - check func and all args (including keyword args)
        .call => |c| {
            // Check the function being called
            if (!initExprIsSafe(c.func, safe_vars)) return false;
            // Check all positional arguments
            for (c.args) |arg| {
                if (!initExprIsSafeNode(arg, safe_vars)) return false;
            }
            // Check all keyword arguments
            for (c.keyword_args) |kwarg| {
                if (!initExprIsSafeNode(kwarg.value, safe_vars)) return false;
            }
            return true;
        },

        // Binary operations - check both sides
        .binop => |b| initExprIsSafe(b.left, safe_vars) and initExprIsSafe(b.right, safe_vars),

        // Unary operations - check operand
        .unaryop => |u| initExprIsSafe(u.operand, safe_vars),

        // Attribute access - check the value
        .attribute => |a| initExprIsSafe(a.value, safe_vars),

        // Subscript - check value and index
        .subscript => |s| {
            if (!initExprIsSafe(s.value, safe_vars)) return false;
            return switch (s.slice) {
                .index => |idx| initExprIsSafe(idx, safe_vars),
                .slice => |sl| {
                    if (sl.lower) |l| if (!initExprIsSafe(l, safe_vars)) return false;
                    if (sl.upper) |u| if (!initExprIsSafe(u, safe_vars)) return false;
                    if (sl.step) |st| if (!initExprIsSafe(st, safe_vars)) return false;
                    return true;
                },
            };
        },

        // Comparisons - check all parts
        .compare => |cmp| {
            if (!initExprIsSafe(cmp.left, safe_vars)) return false;
            for (cmp.comparators) |c| {
                if (!initExprIsSafeNode(c, safe_vars)) return false;
            }
            return true;
        },

        // Tuples and lists - check all elements
        .tuple => |t| {
            for (t.elts) |elt| {
                if (!initExprIsSafeNode(elt, safe_vars)) return false;
            }
            return true;
        },
        .list => |l| {
            for (l.elts) |elt| {
                if (!initExprIsSafeNode(elt, safe_vars)) return false;
            }
            return true;
        },

        // If expression - check all three parts
        .if_expr => |ie| {
            return initExprIsSafe(ie.condition, safe_vars) and
                initExprIsSafe(ie.body, safe_vars) and
                initExprIsSafe(ie.orelse_value, safe_vars);
        },

        // Bool operations - check all values
        .boolop => |bo| {
            for (bo.values) |v| {
                if (!initExprIsSafeNode(v, safe_vars)) return false;
            }
            return true;
        },

        // Dict - check all keys and values
        .dict => |d| {
            for (d.keys) |k| {
                if (!initExprIsSafeNode(k, safe_vars)) return false;
            }
            for (d.values) |v| {
                if (!initExprIsSafeNode(v, safe_vars)) return false;
            }
            return true;
        },

        // F-strings - check embedded expressions
        .fstring => |fstr| {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |e| if (!initExprIsSafe(e.node, safe_vars)) return false,
                    .format_expr => |fe| if (!initExprIsSafe(fe.expr, safe_vars)) return false,
                    .conv_expr => |ce| if (!initExprIsSafe(ce.expr, safe_vars)) return false,
                    .literal => {},
                }
            }
            return true;
        },

        // Comprehensions - check element and generators
        .listcomp => |lc| {
            if (!initExprIsSafe(lc.elt, safe_vars)) return false;
            for (lc.generators) |gen| {
                if (!initExprIsSafe(gen.iter, safe_vars)) return false;
                for (gen.ifs) |cond| {
                    if (!initExprIsSafeNode(cond, safe_vars)) return false;
                }
            }
            return true;
        },
        .dictcomp => |dc| {
            if (!initExprIsSafe(dc.key, safe_vars) or !initExprIsSafe(dc.value, safe_vars)) return false;
            for (dc.generators) |gen| {
                if (!initExprIsSafe(gen.iter, safe_vars)) return false;
                for (gen.ifs) |cond| {
                    if (!initExprIsSafeNode(cond, safe_vars)) return false;
                }
            }
            return true;
        },
        .genexp => |ge| {
            if (!initExprIsSafe(ge.elt, safe_vars)) return false;
            for (ge.generators) |gen| {
                if (!initExprIsSafe(gen.iter, safe_vars)) return false;
                for (gen.ifs) |cond| {
                    if (!initExprIsSafeNode(cond, safe_vars)) return false;
                }
            }
            return true;
        },

        // Lambda - check body
        .lambda => |lam| initExprIsSafe(lam.body, safe_vars),

        // Starred - check value
        .starred => |st| initExprIsSafe(st.value, safe_vars),

        // Conservative default: assume unsafe for unknown node types
        else => false,
    };
}

/// Helper for non-pointer ast.Node
fn initExprIsSafeNode(node: ast.Node, safe_vars: *const hashmap_helper.StringHashMap(void)) bool {
    return switch (node) {
        .constant => true,
        .name => |n| safe_vars.contains(n.id),
        .call => |c| {
            if (!initExprIsSafe(c.func, safe_vars)) return false;
            for (c.args) |arg| {
                if (!initExprIsSafeNode(arg, safe_vars)) return false;
            }
            for (c.keyword_args) |kwarg| {
                if (!initExprIsSafeNode(kwarg.value, safe_vars)) return false;
            }
            return true;
        },
        .binop => |b| initExprIsSafe(b.left, safe_vars) and initExprIsSafe(b.right, safe_vars),
        .unaryop => |u| initExprIsSafe(u.operand, safe_vars),
        .attribute => |a| initExprIsSafe(a.value, safe_vars),
        .tuple => |t| {
            for (t.elts) |elt| {
                if (!initExprIsSafeNode(elt, safe_vars)) return false;
            }
            return true;
        },
        .list => |l| {
            for (l.elts) |elt| {
                if (!initExprIsSafeNode(elt, safe_vars)) return false;
            }
            return true;
        },
        .boolop => |bo| {
            for (bo.values) |v| {
                if (!initExprIsSafeNode(v, safe_vars)) return false;
            }
            return true;
        },
        .compare => |cmp| {
            if (!initExprIsSafe(cmp.left, safe_vars)) return false;
            for (cmp.comparators) |c| {
                if (!initExprIsSafeNode(c, safe_vars)) return false;
            }
            return true;
        },
        .subscript => |s| {
            if (!initExprIsSafe(s.value, safe_vars)) return false;
            return switch (s.slice) {
                .index => |idx| initExprIsSafe(idx, safe_vars),
                .slice => |sl| {
                    if (sl.lower) |l| if (!initExprIsSafe(l, safe_vars)) return false;
                    if (sl.upper) |u| if (!initExprIsSafe(u, safe_vars)) return false;
                    if (sl.step) |st| if (!initExprIsSafe(st, safe_vars)) return false;
                    return true;
                },
            };
        },
        .if_expr => |ie| initExprIsSafe(ie.condition, safe_vars) and initExprIsSafe(ie.body, safe_vars) and initExprIsSafe(ie.orelse_value, safe_vars),
        .dict => |d| {
            for (d.keys) |k| {
                if (!initExprIsSafeNode(k, safe_vars)) return false;
            }
            for (d.values) |v| {
                if (!initExprIsSafeNode(v, safe_vars)) return false;
            }
            return true;
        },
        .fstring => |fstr| {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |e| if (!initExprIsSafe(e.node, safe_vars)) return false,
                    .format_expr => |fe| if (!initExprIsSafe(fe.expr, safe_vars)) return false,
                    .conv_expr => |ce| if (!initExprIsSafe(ce.expr, safe_vars)) return false,
                    .literal => {},
                }
            }
            return true;
        },
        .listcomp => |lc| {
            if (!initExprIsSafe(lc.elt, safe_vars)) return false;
            for (lc.generators) |gen| {
                if (!initExprIsSafe(gen.iter, safe_vars)) return false;
                for (gen.ifs) |cond| {
                    if (!initExprIsSafeNode(cond, safe_vars)) return false;
                }
            }
            return true;
        },
        .dictcomp => |dc| {
            if (!initExprIsSafe(dc.key, safe_vars) or !initExprIsSafe(dc.value, safe_vars)) return false;
            for (dc.generators) |gen| {
                if (!initExprIsSafe(gen.iter, safe_vars)) return false;
                for (gen.ifs) |cond| {
                    if (!initExprIsSafeNode(cond, safe_vars)) return false;
                }
            }
            return true;
        },
        .genexp => |ge| {
            if (!initExprIsSafe(ge.elt, safe_vars)) return false;
            for (ge.generators) |gen| {
                if (!initExprIsSafe(gen.iter, safe_vars)) return false;
                for (gen.ifs) |cond| {
                    if (!initExprIsSafeNode(cond, safe_vars)) return false;
                }
            }
            return true;
        },
        .lambda => |lam| initExprIsSafe(lam.body, safe_vars),
        .starred => |st| initExprIsSafe(st.value, safe_vars),
        else => false,
    };
}

/// Get the Zig type string for a constant value in a collection.
/// Used to determine element type for for-loop iteration.
fn getConstantType(node: ast.Node) []const u8 {
    return switch (node) {
        .constant => |c| switch (c.value) {
            .int => "i64",
            .float => "f64",
            .string => "[]const u8",
            .bool => "bool",
            else => "runtime.PyValue",
        },
        .unaryop => |u| {
            // Handle -INF, -0.0, -1.0, etc.
            if (u.operand.* == .constant) {
                return switch (u.operand.constant.value) {
                    .float => "f64",
                    .int => "i64",
                    else => "runtime.PyValue",
                };
            }
            // Handle -INF, -NAN (unary minus on name)
            if (u.operand.* == .name) {
                const name = u.operand.name.id;
                if (std.mem.eql(u8, name, "INF") or std.mem.eql(u8, name, "NAN")) {
                    return "f64";
                }
            }
            return "runtime.PyValue";
        },
        .name => |n| {
            // Handle special float constants: INF, NAN
            if (std.mem.eql(u8, n.id, "INF") or std.mem.eql(u8, n.id, "NAN")) {
                return "f64";
            }
            return "runtime.PyValue";
        },
        .call => |c| {
            // Handle known builtin function return types
            if (c.func.* == .name) {
                const fn_name = c.func.name.id;
                // round() returns int when ndigits is None or not provided
                // round(x) -> int, round(x, None) -> int, round(x, ndigits=None) -> int
                // round(x, n) where n is not None -> float
                if (std.mem.eql(u8, fn_name, "round")) {
                    if (c.args.len == 1) {
                        // round(x) - no ndigits positional arg
                        // But check for ndigits=None keyword arg
                        var has_ndigits_value = false;
                        for (c.keyword_args) |kw| {
                            if (std.mem.eql(u8, kw.name, "ndigits")) {
                                // Check if ndigits=None
                                if (kw.value == .constant and kw.value.constant.value == .none) {
                                    // ndigits=None means returns int
                                } else {
                                    has_ndigits_value = true;
                                }
                                break;
                            }
                        }
                        if (!has_ndigits_value) {
                            return "i64"; // round(x) or round(x, ndigits=None)
                        }
                    } else if (c.args.len == 2) {
                        // round(x, None) or round(x, n)
                        // Check if second arg is None
                        if (c.args[1] == .constant and c.args[1].constant.value == .none) {
                            return "i64"; // round(x, None) returns int
                        }
                        // Otherwise has ndigits value, returns float
                    }
                }
                // int() returns int
                if (std.mem.eql(u8, fn_name, "int")) {
                    return "i64";
                }
                // float() returns float
                if (std.mem.eql(u8, fn_name, "float")) {
                    return "f64";
                }
            }
            return "runtime.PyValue";
        },
        else => "runtime.PyValue",
    };
}

/// Analyze collection literal elements and return consistent type.
/// Returns "runtime.PyValue" for empty or mixed-type collections.
fn analyzeCollectionElements(elements: []const ast.Node) []const u8 {
    if (elements.len == 0) return "runtime.PyValue";

    // Check first element type
    const first_type = getConstantType(elements[0]);
    if (std.mem.eql(u8, first_type, "runtime.PyValue")) return first_type;

    // Verify all elements have same type
    for (elements[1..]) |elem| {
        if (!std.mem.eql(u8, getConstantType(elem), first_type)) {
            return "runtime.PyValue"; // Mixed types
        }
    }
    return first_type;
}

/// Analyze a for-loop iterator expression to determine element type.
/// Returns the Zig type string for the loop variable.
fn analyzeIterElementType(iter_expr: *const ast.Node) []const u8 {
    return switch (iter_expr.*) {
        // range() call returns i64
        .call => |c| {
            if (c.func.* == .name and std.mem.eql(u8, c.func.name.id, "range")) {
                return "i64";
            }
            return "runtime.PyValue";
        },
        // Tuple/list literals - check element types
        .tuple => |t| analyzeCollectionElements(t.elts),
        .list => |l| analyzeCollectionElements(l.elts),
        // Named variable - unknown at compile time
        .name => "runtime.PyValue",
        else => "runtime.PyValue",
    };
}

/// Infer a fallback type when @TypeOf can't be used due to forward references.
/// This provides a reasonable default based on the expression shape and source context.
pub fn inferFallbackType(init: ?*const ast.Node, source: scope_analyzer.EscapedSource) []const u8 {
    if (init) |expr| {
        return switch (expr.*) {
            // Function calls - usually return PyValue or objects
            .call => |c| {
                // Check for known return types
                if (c.func.* == .name) {
                    const fn_name = c.func.name.id;
                    // eval() returns *PyObject
                    if (std.mem.eql(u8, fn_name, "eval")) {
                        return "*runtime.PyObject";
                    }
                    // float() returns f64
                    if (std.mem.eql(u8, fn_name, "float")) {
                        return "f64";
                    }
                    // int() could return large values from string parsing - use UnifiedInt
                    if (std.mem.eql(u8, fn_name, "int")) {
                        return "runtime.UnifiedInt";
                    }
                    // bool() returns bool
                    if (std.mem.eql(u8, fn_name, "bool")) {
                        return "bool";
                    }
                    // bytes/bytearray calls return []const u8
                    if (std.mem.eql(u8, fn_name, "bytes") or
                        std.mem.eql(u8, fn_name, "bytearray"))
                    {
                        return "[]const u8";
                    }
                    // String functions
                    if (std.mem.eql(u8, fn_name, "str")) {
                        return "[]const u8";
                    }
                    // Range returns iterator
                    if (std.mem.eql(u8, fn_name, "range")) {
                        return "[]i64";
                    }
                }
                // Generic function call - use PyValue
                return "runtime.PyValue";
            },

            // Literals have known types
            .constant => |c| switch (c.value) {
                .int => "i64",
                .float => "f64",
                .string => "[]const u8",
                .bytes => "runtime.builtins.PyBytes",
                .bool => "bool",
                .none => "?*anyopaque",
                else => "runtime.PyValue",
            },

            // Collection types
            .list => "std.ArrayList(runtime.PyValue)",
            .tuple => "runtime.PyValue",
            .dict => "runtime.PyValue",

            // Binary ops usually produce same type as operands
            .binop => |b| {
                // If either side is a string op, result is string
                if (b.left.* == .constant and b.left.constant.value == .string) {
                    return "[]const u8";
                }
                // Python's / operator ALWAYS returns float (true division)
                if (b.op == .Div) {
                    return "f64";
                }
                // If either operand is float, result is float
                if (b.left.* == .constant and b.left.constant.value == .float) {
                    return "f64";
                }
                if (b.right.* == .constant and b.right.constant.value == .float) {
                    return "f64";
                }
                // Use UnifiedInt for binops that may overflow or involve uncertain types
                // This handles cases like `1 << n` where n could produce BigInt
                return "runtime.UnifiedInt";
            },

            // Subscript/slice operations - check what we're slicing
            .subscript => |s| {
                // String slices return strings
                if (s.value.* == .name or s.value.* == .constant) {
                    // Check if base is a string literal or known string var
                    if (s.value.* == .constant and s.value.constant.value == .string) {
                        return "[]const u8";
                    }
                    // For slices (a[1:] or a[1:2]), assume string for now
                    if (s.slice == .slice) {
                        return "[]const u8";
                    }
                }
                return "runtime.PyValue";
            },

            // Attribute access - usually returns PyValue
            .attribute => "runtime.PyValue",

            // If expression - complex, use PyValue
            .if_expr => "runtime.PyValue",

            // Default
            else => "runtime.PyValue",
        };
    }

    // No init expr - base on source context
    // Use appropriate fallback types based on common patterns
    return switch (source) {
        .try_except => "runtime.PyValue",
        // For for_loop, assume range() loops which always produce i64
        // This is the most common pattern and @intCast doesn't work on PyValue
        .for_loop => "i64",
        .if_stmt => "runtime.PyValue",
        .with_stmt => "runtime.PyValue",
    };
}

/// Emit hoisted variable declarations at function/method start.
/// This is the SINGLE SOURCE OF TRUTH for hoisting - called from both
/// genFunctionBody and genMethodBody.
///
/// Strategy:
/// 1. Pre-scan function body to collect variable type information (Solution 3)
/// 2. Build safe_vars set from function parameters
/// 3. For each escaped var:
///    - If init_expr is safe (no forward refs), use @TypeOf(init_expr)
///    - For for-loop vars, use pre-scanned type context to resolve forward refs
///    - Otherwise, use inferred fallback type
/// 4. Add each declared var to safe_vars for subsequent vars
pub fn emitHoistedDeclarations(
    self: *NativeCodegen,
    escaped_vars: []const scope_analyzer.EscapedVar,
    func_params: []const ast.Arg,
    func_body: []const ast.Node,
) CodegenError!void {
    return emitHoistedDeclarationsWithSpecialParams(self, escaped_vars, func_params, func_body, null, null);
}

/// Extended version that also skips *args and **kwargs parameters
pub fn emitHoistedDeclarationsWithSpecialParams(
    self: *NativeCodegen,
    escaped_vars: []const scope_analyzer.EscapedVar,
    func_params: []const ast.Arg,
    func_body: []const ast.Node,
    vararg_name: ?[]const u8,
    kwarg_name: ?[]const u8,
) CodegenError!void {
    if (escaped_vars.len == 0) return;

    // Pre-scan function body to collect variable type information
    // This solves the forward-reference problem: when we need to hoist `f` for
    // `for f in floats:` but `floats` isn't declared yet, we can look up the
    // pre-scanned type info for `floats` instead of using @TypeOf
    var type_ctx = VarTypeContext.init(self.allocator);
    defer type_ctx.deinit();
    type_ctx.scanFunctionBody(func_body);

    // Build safe vars set from function parameters
    var safe_vars = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer safe_vars.deinit();

    for (func_params) |param| {
        try safe_vars.put(param.name, {});
    }

    // Also add module-level names as safe (they're always available)
    var mod_iter = self.module_level_funcs.iterator();
    while (mod_iter.next()) |entry| {
        try safe_vars.put(entry.key_ptr.*, {});
    }

    // Add module-level variable names (tracked explicitly during module generation)
    var mod_var_iter = self.module_level_vars.iterator();
    while (mod_var_iter.next()) |entry| {
        try safe_vars.put(entry.key_ptr.*, {});
    }

    // Emit each hoisted variable declaration
    for (escaped_vars) |escaped| {
        // Skip variables that match function parameters - they're already declared
        var is_param = false;
        for (func_params) |param| {
            if (std.mem.eql(u8, escaped.name, param.name)) {
                is_param = true;
                break;
            }
        }
        if (is_param) continue;

        // Skip *args parameter (vararg) - it's already declared in function signature
        if (vararg_name) |vname| {
            if (std.mem.eql(u8, escaped.name, vname)) continue;
        }

        // Skip **kwargs parameter (kwarg) - it's already declared in function signature
        if (kwarg_name) |kname| {
            if (std.mem.eql(u8, escaped.name, kname)) continue;
        }

        // Skip module-level functions - they're already declared as functions
        // Python allows `genslices = rslices` to reassign function names,
        // but in Zig the function is already defined so we skip hoisting
        if (self.module_level_funcs.contains(escaped.name)) continue;

        // Also skip variables that are assigned a module-level function
        // e.g., `permutations = rpermutation` - can't hoist a function reference
        if (escaped.init_expr) |init| {
            if (init.* == .name) {
                if (self.module_level_funcs.contains(init.name.id)) continue;
            }
        }

        // For loop target variables ARE hoisted - they need to persist after the loop.
        // The for loop codegen checks hoisted_vars and uses assignment instead of const.
        // Don't skip them here.

        // Check if this hoisted var would shadow a module-level pre-declared global
        // If so, rename the local to avoid Zig's shadowing error
        // Use NameGen for consistent unique naming across the codebase
        var actual_name = escaped.name;
        if (self.module_level_vars.contains(escaped.name)) {
            const shadow_name = try self.name_gen.hoisted(escaped.name);
            try self.var_renames.put(try self.arena.allocator().dupe(u8, escaped.name), shadow_name);
            actual_name = shadow_name;
        }

        try self.emitIndent();
        try emitConst(self,"var ");
        // Use writeLocalVarName to be consistent with expression usage
        // This handles both keyword escaping AND method shadowing (e.g., "format" -> "format_")
        try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);

        if (escaped.init_expr) |init| {
            // Check for self-reference: `line = line.strip()` where init references the variable being declared
            // This would cause circular reference in @TypeOf - use fallback type instead
            const has_self_reference = exprContainsName(init, escaped.name);

            // Check if init is a literal constant - @TypeOf(literal) gives comptime types (comptime_int, etc.)
            // which can't be used for runtime vars. Use concrete types instead.
            // Also check for attribute access (method references) - @TypeOf(obj.method) gives function types
            // which can't be used for var.
            const is_literal = switch (init.*) {
                .constant => true,
                .attribute => true, // Method references like self.assertEqual
                else => false,
            };

            // Check if this is a class constructor call - if so, use class type directly
            // Class constructor calls like Rat(1, 0) would evaluate at comptime in @TypeOf
            // and throw errors. Instead, use the class name directly.
            const class_type: ?[]const u8 = if (init.* == .call and init.call.func.* == .name)
                blk: {
                    const func_name = init.call.func.name.id;
                    // Check if this is a class (starts with uppercase and is not a builtin)
                    if (func_name.len > 0 and func_name[0] >= 'A' and func_name[0] <= 'Z') {
                        // Check if it's a known class in this module (not a builtin like TypeError)
                        if (!isBuiltinException(func_name)) {
                            break :blk func_name;
                        }
                    }
                    break :blk null;
                }
            else
                null;

            if (class_type) |cls_name| {
                // Use class type directly instead of @TypeOf(Class.init(...))
                try emitConst(self,": ");
                try emitConst(self,cls_name);
            } else if (!has_self_reference and !is_literal and initExprIsSafe(init, &safe_vars)) {
                // Safe to use @TypeOf - no forward references, no self-references, and not a literal
                try emitConst(self,": @TypeOf(");
                try self.genExpr(init.*);
                try emitConst(self,")");
            } else {
                // Has forward refs, self-reference, or is a literal - use fallback type
                const fallback = inferFallbackType(init, escaped.source);
                try emitConst(self,": ");
                try emitConst(self,fallback);
            }
        } else if (escaped.source == .for_loop and escaped.for_iter_expr != null and escaped.tuple_index != null) {
            // For-loop tuple unpacking: derive type from iteration expression
            // But only if the iter expression uses safe names (params, globals)
            // Otherwise fall back to runtime.PyValue to avoid forward reference errors
            const iter_safe = initExprIsSafe(escaped.for_iter_expr.?, &safe_vars);
            if (iter_safe) {
                // Generate: var s: @TypeOf(L.items[0].@"0") = undefined;
                try emitConst(self,": @TypeOf((");
                try self.genExpr(escaped.for_iter_expr.?.*);
                // Add .items if it's an ArrayList (list type)
                const iter_type = self.type_inferrer.inferExpr(escaped.for_iter_expr.?.*) catch .unknown;
                if (container_traits.isList(iter_type)) {
                    try emitConst(self,").items[0].@\"");
                } else {
                    // For other types (tuples, etc.) access directly
                    try emitConst(self,")[0].@\"");
                }
                try self.output.writer(self.allocator).print("{d}\")", .{escaped.tuple_index.?});
            } else {
                // Iter expression uses local vars - use fallback type
                const fallback = inferFallbackType(null, escaped.source);
                try emitConst(self,": ");
                try emitConst(self,fallback);
            }
        } else if (escaped.source == .for_loop and escaped.for_iter_expr != null) {
            // For-loop variable (without tuple unpacking) - analyze iterator to get element type
            // First try static analysis for literal tuples/lists/calls
            const elem_type = analyzeIterElementType(escaped.for_iter_expr.?);
            if (!std.mem.eql(u8, elem_type, "runtime.PyValue")) {
                // Known element type from literal analysis (tuple/list/range)
                try emitConst(self,": ");
                try emitConst(self,elem_type);
            } else {
                // Unknown collection - try type inference on iterator expression
                const iter_type = self.type_inferrer.inferExpr(escaped.for_iter_expr.?.*) catch .unknown;
                const elem_native_type = container_traits.getIteratorElementType(iter_type);
                const elem_native_tag = @as(std.meta.Tag(@TypeOf(elem_native_type)), elem_native_type);

                if (elem_native_tag != .unknown and elem_native_tag != .pyvalue) {
                    // Type inferrer knows the element type - use it
                    const zig_type = elem_native_type.toSimpleZigType();
                    try emitConst(self,": ");
                    try emitConst(self,zig_type);
                } else {
                    // Type inferrer doesn't know - try pre-scanned type context first
                    // This handles: floats = (INF, -INF, 0.0, ...) -> for f in floats:
                    // where floats is a local var not yet declared at hoist time
                    const iter_expr = escaped.for_iter_expr.?;
                    if (iter_expr.* == .name) {
                        // Iterator is a variable name - look up in pre-scanned type context
                        if (type_ctx.getIteratorElementType(iter_expr.name.id)) |elem_zig_type| {
                            try emitConst(self,": ");
                            try emitConst(self,elem_zig_type);
                        } else {
                            // Not in type context - try @TypeOf if safe, else fallback
                            const iter_safe = initExprIsSafe(iter_expr, &safe_vars);
                            if (iter_safe) {
                                // Use std.meta.Elem to safely get element type (handles empty arrays)
                                if (container_traits.isList(iter_type)) {
                                    try emitConst(self,": std.meta.Elem(@TypeOf((");
                                    try self.genExpr(iter_expr.*);
                                    try emitConst(self,").items))");
                                } else {
                                    try emitConst(self,": std.meta.Elem(@TypeOf(");
                                    try self.genExpr(iter_expr.*);
                                    try emitConst(self,"))");
                                }
                            } else {
                                try emitConst(self,": runtime.PyValue");
                            }
                        }
                    } else {
                        // Non-name iterator - try @TypeOf if safe
                        const iter_safe = initExprIsSafe(iter_expr, &safe_vars);
                        if (iter_safe) {
                            // Use std.meta.Elem to safely get element type (handles empty arrays)
                            if (container_traits.isList(iter_type)) {
                                try emitConst(self,": std.meta.Elem(@TypeOf((");
                                try self.genExpr(iter_expr.*);
                                try emitConst(self,").items))");
                            } else {
                                try emitConst(self,": std.meta.Elem(@TypeOf(");
                                try self.genExpr(iter_expr.*);
                                try emitConst(self,"))");
                            }
                        } else {
                            try emitConst(self,": runtime.PyValue");
                        }
                    }
                }
            }
        } else {
            // No init expr - use fallback based on source
            const fallback = inferFallbackType(null, escaped.source);
            try emitConst(self,": ");
            try emitConst(self,fallback);
        }

        try emitConst(self," = undefined;\n");
        // Add discard to prevent "unused variable" errors when body is skipped
        try self.emitIndent();
        try emitConst(self,"_ = &");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), escaped.name);
        try emitConst(self,";\n");

        // Add this var to safe_vars for subsequent hoisted vars
        try safe_vars.put(escaped.name, {});
    }
}
