/// AST visitor interface
/// Mirrors cpython/Python/Python-ast.c (visitor pattern)

const Module = @import("module_types.zig").Module;
const Statement = @import("statement_types.zig").Statement;
const Expr = @import("expression_types.zig").Expr;
const Pattern = @import("pattern_types.zig").Pattern;

/// AST visitor interface
pub fn Visitor(comptime Context: type) type {
    return struct {
        context: Context,

        visit_stmt: ?*const fn (Context, *Statement) void = null,
        visit_expr: ?*const fn (Context, *Expr) void = null,
        visit_pattern: ?*const fn (Context, *Pattern) void = null,

        pub fn visitModule(self: @This(), module: *Module) void {
            for (module.body) |*stmt| {
                self.visitStmt(stmt);
            }
        }

        pub fn visitStmt(self: @This(), stmt: *Statement) void {
            if (self.visit_stmt) |visit| {
                visit(self.context, stmt);
            }
        }

        pub fn visitExpr(self: @This(), expr: *Expr) void {
            if (self.visit_expr) |visit| {
                visit(self.context, expr);
            }
        }
    };
}
