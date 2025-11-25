/// Comptime analysis - Analyze AST before code generation
/// Determines what imports, resources, and setup code is needed
const std = @import("std");
const ast = @import("../../ast.zig");

/// Analysis result - what the module needs
pub const ModuleAnalysis = struct {
    needs_json: bool = false,
    needs_http: bool = false,
    needs_async: bool = false,
    needs_allocator: bool = false,
    needs_runtime: bool = false,
    needs_string_utils: bool = false,
    needs_hashmap_helper: bool = false,
    needs_std: bool = false, // For print() and other std features

    /// Merge two analyses
    pub fn merge(self: *ModuleAnalysis, other: ModuleAnalysis) void {
        self.needs_json = self.needs_json or other.needs_json;
        self.needs_http = self.needs_http or other.needs_http;
        self.needs_async = self.needs_async or other.needs_async;
        self.needs_allocator = self.needs_allocator or other.needs_allocator;
        self.needs_runtime = self.needs_runtime or other.needs_runtime;
        self.needs_string_utils = self.needs_string_utils or other.needs_string_utils;
        self.needs_hashmap_helper = self.needs_hashmap_helper or other.needs_hashmap_helper;
        self.needs_std = self.needs_std or other.needs_std;
    }
};

/// Check if a list contains only literal constants
fn isConstantList(list: ast.Node.List) bool {
    if (list.elts.len == 0) return false; // Empty lists stay dynamic

    for (list.elts) |elem| {
        const is_literal = switch (elem) {
            .constant => true,
            else => false,
        };
        if (!is_literal) return false;
    }

    return true;
}

/// Check if all elements in a list have the same type (homogeneous)
fn allSameType(elements: []ast.Node) bool {
    if (elements.len == 0) return true;

    // Get type tag of first element
    const first_const = switch (elements[0]) {
        .constant => |c| c,
        else => return false,
    };

    const first_type_tag = @as(std.meta.Tag(@TypeOf(first_const.value)), first_const.value);

    // Check all other elements match
    for (elements[1..]) |elem| {
        const elem_const = switch (elem) {
            .constant => |c| c,
            else => return false,
        };

        const elem_type_tag = @as(std.meta.Tag(@TypeOf(elem_const.value)), elem_const.value);
        if (elem_type_tag != first_type_tag) return false;
    }

    return true;
}

/// Analyze entire module to determine requirements
pub fn analyzeModule(module: ast.Node.Module, allocator: std.mem.Allocator) !ModuleAnalysis {
    _ = allocator; // Will need for recursive analysis
    var analysis = ModuleAnalysis{};

    for (module.body) |stmt| {
        const stmt_analysis = try analyzeStmt(stmt);
        analysis.merge(stmt_analysis);
    }

    return analysis;
}

fn analyzeStmt(node: ast.Node) !ModuleAnalysis {
    var analysis = ModuleAnalysis{};

    switch (node) {
        .assign => |assign| {
            const expr_analysis = try analyzeExpr(assign.value.*);
            analysis.merge(expr_analysis);
        },
        .expr_stmt => |expr| {
            const expr_analysis = try analyzeExpr(expr.value.*);
            analysis.merge(expr_analysis);
        },
        .if_stmt => |if_stmt| {
            const cond_analysis = try analyzeExpr(if_stmt.condition.*);
            analysis.merge(cond_analysis);

            for (if_stmt.body) |stmt| {
                const stmt_analysis = try analyzeStmt(stmt);
                analysis.merge(stmt_analysis);
            }

            for (if_stmt.else_body) |stmt| {
                const stmt_analysis = try analyzeStmt(stmt);
                analysis.merge(stmt_analysis);
            }
        },
        .for_stmt => |for_stmt| {
            const iter_analysis = try analyzeExpr(for_stmt.iter.*);
            analysis.merge(iter_analysis);

            for (for_stmt.body) |stmt| {
                const stmt_analysis = try analyzeStmt(stmt);
                analysis.merge(stmt_analysis);
            }
        },
        .while_stmt => |while_stmt| {
            const cond_analysis = try analyzeExpr(while_stmt.condition.*);
            analysis.merge(cond_analysis);

            for (while_stmt.body) |stmt| {
                const stmt_analysis = try analyzeStmt(stmt);
                analysis.merge(stmt_analysis);
            }
        },
        .function_def => |func| {
            // Analyze function body for imports/requirements
            for (func.body) |stmt| {
                const stmt_analysis = try analyzeStmt(stmt);
                analysis.merge(stmt_analysis);
            }
        },
        else => {},
    }

    return analysis;
}

fn analyzeExpr(node: ast.Node) !ModuleAnalysis {
    var analysis = ModuleAnalysis{};

    switch (node) {
        .fstring => |f| {
            // F-strings use std.fmt.allocPrint which needs allocator
            analysis.needs_allocator = true;

            // Analyze expressions inside f-string parts
            for (f.parts) |part| {
                switch (part) {
                    .expr => |expr| {
                        const part_analysis = try analyzeExpr(expr.*);
                        analysis.merge(part_analysis);
                    },
                    .format_expr => |fe| {
                        const part_analysis = try analyzeExpr(fe.expr.*);
                        analysis.merge(part_analysis);
                    },
                    .literal => {},
                }
            }
        },
        .call => |call| {
            // Check for module.function() calls
            if (call.func.* == .attribute) {
                const attr = call.func.attribute;

                // Check for string methods that need string_utils
                if (std.mem.eql(u8, attr.attr, "upper") or std.mem.eql(u8, attr.attr, "lower")) {
                    analysis.needs_string_utils = true;
                    analysis.needs_allocator = true;
                }

                // Check for string methods that need allocator
                if (std.mem.eql(u8, attr.attr, "replace") or std.mem.eql(u8, attr.attr, "split")) {
                    analysis.needs_allocator = true;
                }

                // Check for list methods that need allocator (append, extend, insert, etc.)
                const list_methods = [_][]const u8{ "append", "extend", "insert", "remove", "clone" };
                for (list_methods) |method| {
                    if (std.mem.eql(u8, attr.attr, method)) {
                        analysis.needs_allocator = true;
                        break;
                    }
                }

                if (attr.value.* == .name) {
                    const module_name = attr.value.name.id;

                    if (std.mem.eql(u8, module_name, "json")) {
                        analysis.needs_json = true;
                        analysis.needs_allocator = true;
                    } else if (std.mem.eql(u8, module_name, "http")) {
                        analysis.needs_http = true;
                        analysis.needs_runtime = true;
                        analysis.needs_allocator = true;
                    } else if (std.mem.eql(u8, module_name, "asyncio")) {
                        analysis.needs_async = true;
                        analysis.needs_runtime = true;
                        analysis.needs_allocator = true;
                    } else if (std.mem.eql(u8, module_name, "numpy") or std.mem.eql(u8, module_name, "np")) {
                        // NumPy functions that need allocator: array, zeros, ones, transpose, matmul
                        const func_name = attr.attr;
                        if (std.mem.eql(u8, func_name, "array") or
                            std.mem.eql(u8, func_name, "zeros") or
                            std.mem.eql(u8, func_name, "ones") or
                            std.mem.eql(u8, func_name, "transpose") or
                            std.mem.eql(u8, func_name, "matmul"))
                        {
                            analysis.needs_allocator = true;
                        }
                    }
                }
            }

            // Check for built-in functions that need allocator
            if (call.func.* == .name) {
                const func_name = call.func.name.id;
                // str() needs allocator for ArrayList buffer
                // reversed/sorted need allocator for copying slices
                const allocator_builtins = [_][]const u8{ "reversed", "sorted", "str" };
                for (allocator_builtins) |builtin| {
                    if (std.mem.eql(u8, func_name, builtin)) {
                        analysis.needs_allocator = true;
                        break;
                    }
                }

                // Check for class instantiation (uppercase first letter)
                if (func_name.len > 0 and std.ascii.isUpper(func_name[0])) {
                    analysis.needs_allocator = true;
                }

                // print() needs std.debug.print
                if (std.mem.eql(u8, func_name, "print")) {
                    analysis.needs_std = true;
                }
            }

            // Analyze function arguments
            for (call.args) |arg| {
                const arg_analysis = try analyzeExpr(arg);
                analysis.merge(arg_analysis);
            }
        },
        .binop => |binop| {
            const left_analysis = try analyzeExpr(binop.left.*);
            const right_analysis = try analyzeExpr(binop.right.*);
            analysis.merge(left_analysis);
            analysis.merge(right_analysis);

            // String concatenation (with +) needs allocator
            if (binop.op == .Add) {
                // Check if either side is a string literal
                if ((binop.left.* == .constant and binop.left.constant.value == .string) or
                    (binop.right.* == .constant and binop.right.constant.value == .string))
                {
                    analysis.needs_allocator = true;
                }
            }
        },
        .list => |list| {
            // Check if list can be optimized to fixed-size array (no allocator needed)
            // Fixed arrays: constant literals + homogeneous type (e.g., [1, 2, 3])
            // Dynamic lists: non-constant or mixed types (need allocator)
            const is_constant = isConstantList(list);
            const is_homogeneous = allSameType(list.elts);
            const can_optimize_to_array = is_constant and is_homogeneous;

            // Only mark as needing allocator if we can't optimize to fixed array
            if (list.elts.len > 0 and !can_optimize_to_array) {
                analysis.needs_allocator = true;
            }

            for (list.elts) |elt| {
                const elt_analysis = try analyzeExpr(elt);
                analysis.merge(elt_analysis);
            }
        },
        .dict => |dict| {
            // Dicts need allocator for HashMap.init()
            analysis.needs_allocator = true;
            analysis.needs_hashmap_helper = true;

            for (dict.keys) |key| {
                const key_analysis = try analyzeExpr(key);
                analysis.merge(key_analysis);
            }
            for (dict.values) |value| {
                const value_analysis = try analyzeExpr(value);
                analysis.merge(value_analysis);
            }
        },
        .listcomp => |listcomp| {
            // List comprehensions need allocator for ArrayList operations
            analysis.needs_allocator = true;

            const elt_analysis = try analyzeExpr(listcomp.elt.*);
            analysis.merge(elt_analysis);

            for (listcomp.generators) |gen| {
                const iter_analysis = try analyzeExpr(gen.iter.*);
                analysis.merge(iter_analysis);

                for (gen.ifs) |if_cond| {
                    const cond_analysis = try analyzeExpr(if_cond);
                    analysis.merge(cond_analysis);
                }
            }
        },
        .dictcomp => |dictcomp| {
            // Dict comprehensions need allocator for HashMap operations
            analysis.needs_allocator = true;
            analysis.needs_hashmap_helper = true;

            const key_analysis = try analyzeExpr(dictcomp.key.*);
            analysis.merge(key_analysis);

            const value_analysis = try analyzeExpr(dictcomp.value.*);
            analysis.merge(value_analysis);

            for (dictcomp.generators) |gen| {
                const iter_analysis = try analyzeExpr(gen.iter.*);
                analysis.merge(iter_analysis);

                for (gen.ifs) |if_cond| {
                    const cond_analysis = try analyzeExpr(if_cond);
                    analysis.merge(cond_analysis);
                }
            }
        },
        else => {},
    }

    return analysis;
}
