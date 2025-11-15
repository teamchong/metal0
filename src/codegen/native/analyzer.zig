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

    /// Merge two analyses
    pub fn merge(self: *ModuleAnalysis, other: ModuleAnalysis) void {
        self.needs_json = self.needs_json or other.needs_json;
        self.needs_http = self.needs_http or other.needs_http;
        self.needs_async = self.needs_async or other.needs_async;
        self.needs_allocator = self.needs_allocator or other.needs_allocator;
        self.needs_runtime = self.needs_runtime or other.needs_runtime;
    }
};

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
        else => {},
    }

    return analysis;
}

fn analyzeExpr(node: ast.Node) !ModuleAnalysis {
    var analysis = ModuleAnalysis{};

    switch (node) {
        .call => |call| {
            // Check for module.function() calls
            if (call.func.* == .attribute) {
                const attr = call.func.attribute;
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
                    }
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
        },
        .list => |list| {
            for (list.elts) |elt| {
                const elt_analysis = try analyzeExpr(elt);
                analysis.merge(elt_analysis);
            }
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                const key_analysis = try analyzeExpr(key);
                analysis.merge(key_analysis);
            }
            for (dict.values) |value| {
                const value_analysis = try analyzeExpr(value);
                analysis.merge(value_analysis);
            }
        },
        else => {},
    }

    return analysis;
}
