const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("types.zig");

/// Track variable lifetimes through the AST
pub fn analyzeLifetimes(info: *types.SemanticInfo, node: ast.Node, current_line: usize) !usize {
    var line = current_line;

    switch (node) {
        .module => |module| {
            for (module.body) |body_node| {
                line = try analyzeLifetimes(info, body_node, line);
            }
        },
        .assign => |assign| {
            // Record assignment
            for (assign.targets) |target| {
                if (target == .name) {
                    try info.recordVariableUse(target.name.id, line, true);
                }
            }
            // Analyze value expression for uses
            line = try analyzeLifetimes(info, assign.value.*, line);
            line += 1;
        },
        .ann_assign => |ann_assign| {
            // Record annotated assignment
            if (ann_assign.target.* == .name) {
                try info.recordVariableUse(ann_assign.target.name.id, line, true);
            }
            // Analyze value expression if present
            if (ann_assign.value) |value| {
                line = try analyzeLifetimes(info, value.*, line);
            }
            line += 1;
        },
        .aug_assign => |aug| {
            // Record both use and assignment
            if (aug.target.* == .name) {
                try info.recordVariableUse(aug.target.name.id, line, false);
                try info.recordVariableUse(aug.target.name.id, line, true);
            }
            line = try analyzeLifetimes(info, aug.value.*, line);
            line += 1;
        },
        .name => |name| {
            // Record variable use
            try info.recordVariableUse(name.id, line, false);
        },
        .binop => |binop| {
            line = try analyzeLifetimes(info, binop.left.*, line);
            line = try analyzeLifetimes(info, binop.right.*, line);
        },
        .unaryop => |unary| {
            line = try analyzeLifetimes(info, unary.operand.*, line);
        },
        .call => |call| {
            line = try analyzeLifetimes(info, call.func.*, line);
            for (call.args) |arg| {
                line = try analyzeLifetimes(info, arg, line);
            }
        },
        .compare => |compare| {
            line = try analyzeLifetimes(info, compare.left.*, line);
            for (compare.comparators) |comp| {
                line = try analyzeLifetimes(info, comp, line);
            }
        },
        .boolop => |boolop| {
            for (boolop.values) |value| {
                line = try analyzeLifetimes(info, value, line);
            }
        },
        .if_expr => |if_expr| {
            // Conditional expression: body if condition else orelse_value
            line = try analyzeLifetimes(info, if_expr.body.*, line);
            line = try analyzeLifetimes(info, if_expr.condition.*, line);
            line = try analyzeLifetimes(info, if_expr.orelse_value.*, line);
        },
        .if_stmt => |if_stmt| {
            const scope_start = line;
            line = try analyzeLifetimes(info, if_stmt.condition.*, line);
            line += 1;

            // Analyze body
            for (if_stmt.body) |body_node| {
                line = try analyzeLifetimes(info, body_node, line);
            }

            // Analyze else body
            for (if_stmt.else_body) |else_node| {
                line = try analyzeLifetimes(info, else_node, line);
            }

            // Mark scope end for any variables defined in this scope
            _ = scope_start;
            line += 1;
        },
        .for_stmt => |for_stmt| {
            const scope_start = line;
            line = try analyzeLifetimes(info, for_stmt.iter.*, line);

            // Record loop variable
            if (for_stmt.target.* == .name) {
                try info.recordVariableUse(for_stmt.target.name.id, line, true);
                try info.markLoopLocal(for_stmt.target.name.id);
            }
            line += 1;

            // Analyze body
            for (for_stmt.body) |body_node| {
                line = try analyzeLifetimes(info, body_node, line);
            }

            // Mark scope end
            if (for_stmt.target.* == .name) {
                try info.markScopeEnd(for_stmt.target.name.id, line);
            }
            _ = scope_start;
            line += 1;
        },
        .while_stmt => |while_stmt| {
            const scope_start = line;
            line = try analyzeLifetimes(info, while_stmt.condition.*, line);
            line += 1;

            // Analyze body
            for (while_stmt.body) |body_node| {
                line = try analyzeLifetimes(info, body_node, line);
            }

            _ = scope_start;
            line += 1;
        },
        .function_def => |func| {
            // Skip function body analysis for module-level lifetime tracking.
            // Function-local variables are in a separate scope and should not affect
            // module-level var/const decisions. The codegen handles function-local
            // mutation detection separately.
            _ = func;
            line += 1;
        },
        .lambda => |lambda| {
            const scope_start = line;

            // DON'T record lambda parameters as variable assignments!
            // Lambda parameters are local to the lambda scope and shouldn't
            // be conflated with outer scope variables of the same name
            // for (lambda.args) |arg| {
            //     try info.recordVariableUse(arg.name, line, true);
            // }

            // Analyze body (single expression)
            // Variables referenced in the body will be recorded as uses
            line = try analyzeLifetimes(info, lambda.body.*, line);

            // Mark scope end for parameters
            for (lambda.args) |arg| {
                try info.markScopeEnd(arg.name, line);
            }
            _ = scope_start;
        },
        .class_def => |class_def| {
            const scope_start = line;

            // Analyze class body
            for (class_def.body) |body_node| {
                line = try analyzeLifetimes(info, body_node, line);
            }

            _ = scope_start;
            line += 1;
        },
        .return_stmt => |ret| {
            if (ret.value) |value| {
                line = try analyzeLifetimes(info, value.*, line);
            }
            line += 1;
        },
        .list => |list| {
            for (list.elts) |elt| {
                line = try analyzeLifetimes(info, elt, line);
            }
        },
        .listcomp => |listcomp| {
            for (listcomp.generators) |gen| {
                line = try analyzeLifetimes(info, gen.iter.*, line);
                if (gen.target.* == .name) {
                    try info.recordVariableUse(gen.target.name.id, line, true);
                    try info.markLoopLocal(gen.target.name.id);
                }
                for (gen.ifs) |if_node| {
                    line = try analyzeLifetimes(info, if_node, line);
                }
            }
            line = try analyzeLifetimes(info, listcomp.elt.*, line);
        },
        .dictcomp => |dictcomp| {
            for (dictcomp.generators) |gen| {
                line = try analyzeLifetimes(info, gen.iter.*, line);
                if (gen.target.* == .name) {
                    try info.recordVariableUse(gen.target.name.id, line, true);
                    try info.markLoopLocal(gen.target.name.id);
                }
                for (gen.ifs) |if_node| {
                    line = try analyzeLifetimes(info, if_node, line);
                }
            }
            line = try analyzeLifetimes(info, dictcomp.key.*, line);
            line = try analyzeLifetimes(info, dictcomp.value.*, line);
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                line = try analyzeLifetimes(info, key, line);
            }
            for (dict.values) |value| {
                line = try analyzeLifetimes(info, value, line);
            }
        },
        .set => |set| {
            for (set.elts) |elt| {
                line = try analyzeLifetimes(info, elt, line);
            }
        },
        .tuple => |tuple| {
            for (tuple.elts) |elt| {
                line = try analyzeLifetimes(info, elt, line);
            }
        },
        .subscript => |subscript| {
            line = try analyzeLifetimes(info, subscript.value.*, line);
            switch (subscript.slice) {
                .index => |idx| {
                    line = try analyzeLifetimes(info, idx.*, line);
                },
                .slice => |slice| {
                    if (slice.lower) |lower| {
                        line = try analyzeLifetimes(info, lower.*, line);
                    }
                    if (slice.upper) |upper| {
                        line = try analyzeLifetimes(info, upper.*, line);
                    }
                    if (slice.step) |step| {
                        line = try analyzeLifetimes(info, step.*, line);
                    }
                },
            }
        },
        .attribute => |attr| {
            line = try analyzeLifetimes(info, attr.value.*, line);
        },
        .expr_stmt => |expr| {
            line = try analyzeLifetimes(info, expr.value.*, line);
            line += 1;
        },
        .await_expr => |await_expr| {
            line = try analyzeLifetimes(info, await_expr.value.*, line);
        },
        .assert_stmt => |assert_stmt| {
            line = try analyzeLifetimes(info, assert_stmt.condition.*, line);
            if (assert_stmt.msg) |msg| {
                line = try analyzeLifetimes(info, msg.*, line);
            }
            line += 1;
        },
        .try_stmt => |try_stmt| {
            // Analyze try block
            for (try_stmt.body) |body_node| {
                line = try analyzeLifetimes(info, body_node, line);
            }
            // Analyze except handlers
            for (try_stmt.handlers) |handler| {
                for (handler.body) |body_node| {
                    line = try analyzeLifetimes(info, body_node, line);
                }
            }
            // Analyze else block
            for (try_stmt.else_body) |else_node| {
                line = try analyzeLifetimes(info, else_node, line);
            }
            // Analyze finally block
            for (try_stmt.finalbody) |finally_node| {
                line = try analyzeLifetimes(info, finally_node, line);
            }
            line += 1;
        },
        .with_stmt => |with_stmt| {
            // Analyze context expression
            line = try analyzeLifetimes(info, with_stmt.context_expr.*, line);

            // Record variable if "as var" is present
            if (with_stmt.optional_vars) |var_name| {
                try info.recordVariableUse(var_name, line, true);
            }
            line += 1;

            // Analyze body
            for (with_stmt.body) |body_node| {
                line = try analyzeLifetimes(info, body_node, line);
            }

            line += 1;
        },
        .starred => |starred| {
            // Analyze the value being unpacked
            line = try analyzeLifetimes(info, starred.value.*, line);
        },
        .double_starred => |double_starred| {
            // Analyze the value being unpacked (kwargs)
            line = try analyzeLifetimes(info, double_starred.value.*, line);
        },
        .del_stmt => |del| {
            // Record variable deletion (for completeness, could mark lifetime end)
            for (del.targets) |target| {
                if (target == .name) {
                    try info.markScopeEnd(target.name.id, line);
                }
            }
            line += 1;
        },
        .named_expr => |named| {
            // Named expression (walrus operator): (x := value)
            // Record target as assignment
            if (named.target.* == .name) {
                try info.recordVariableUse(named.target.name.id, line, true);
            }
            // Analyze value expression
            line = try analyzeLifetimes(info, named.value.*, line);
        },
        // Leaf nodes
        .constant, .import_stmt, .import_from, .pass, .break_stmt, .continue_stmt, .fstring, .global_stmt, .ellipsis_literal, .raise_stmt => {
            // No variables to track
        },
    }

    return line;
}
