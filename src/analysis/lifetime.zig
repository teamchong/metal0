const std = @import("std");
const ast = @import("ast");
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
            // Record annotated assignment - only count as assignment if value present
            // Annotation-only (x: int) is just a declaration, not an assignment
            if (ann_assign.target.* == .name) {
                const is_assignment = ann_assign.value != null;
                try info.recordVariableUse(ann_assign.target.name.id, line, is_assignment);
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
            // Special handling for eval/exec: extract variable references from string argument
            if (call.func.* == .name) {
                const func_name = call.func.name.id;
                if ((std.mem.eql(u8, func_name, "eval") or std.mem.eql(u8, func_name, "exec")) and call.args.len >= 1) {
                    if (call.args[0] == .constant and call.args[0].constant.value == .string) {
                        const source = call.args[0].constant.value.string;
                        // Extract variable names from eval string and mark them as used
                        try extractVarsFromEvalString(info, source, line);
                    }
                }
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
        .fstring => |fstr| {
            // F-strings can contain expressions that reference variables
            for (fstr.parts) |part| {
                switch (part) {
                    .literal => {}, // No variables
                    .expr => |expr| {
                        line = try analyzeLifetimes(info, expr.*, line);
                    },
                    .format_expr => |fmt| {
                        line = try analyzeLifetimes(info, fmt.expr.*, line);
                    },
                    .conv_expr => |conv| {
                        line = try analyzeLifetimes(info, conv.expr.*, line);
                    },
                }
            }
        },
        // Leaf nodes
        .constant, .import_stmt, .import_from, .pass, .break_stmt, .continue_stmt, .global_stmt, .ellipsis_literal, .raise_stmt, .yield_stmt => {
            // No variables to track
        },
    }

    return line;
}

/// Extract variable names from an eval/exec string and mark them as used.
/// Uses simple identifier extraction - finds [a-zA-Z_][a-zA-Z0-9_]* patterns.
fn extractVarsFromEvalString(info: *types.SemanticInfo, source: []const u8, line: usize) !void {
    // Strip quotes if present (AST stores string with quotes)
    const stripped = if (source.len >= 2 and
        ((source[0] == '"' and source[source.len - 1] == '"') or
        (source[0] == '\'' and source[source.len - 1] == '\'')))
        source[1 .. source.len - 1]
    else
        source;

    var i: usize = 0;
    while (i < stripped.len) {
        const c = stripped[i];
        // Check for start of identifier (letter or underscore)
        if (isIdentStart(c)) {
            const start = i;
            i += 1;
            // Continue while identifier character
            while (i < stripped.len and isIdentCont(stripped[i])) {
                i += 1;
            }
            const ident = stripped[start..i];
            // Skip Python keywords - only record potential variable names
            if (!isKeyword(ident)) {
                // Record as a use (not assignment) to mark variable as "read"
                try info.recordVariableUse(ident, line, false);
                // Also mark as eval-string var for special handling in codegen
                try info.markEvalStringVar(ident);
            }
        } else {
            i += 1;
        }
    }
}

fn isIdentStart(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
}

fn isIdentCont(c: u8) bool {
    return isIdentStart(c) or (c >= '0' and c <= '9');
}

fn isKeyword(s: []const u8) bool {
    const keywords = [_][]const u8{
        "and",     "as",       "assert", "async",  "await",    "break",
        "class",   "continue", "def",    "del",    "elif",     "else",
        "except",  "False",    "finally", "for",    "from",     "global",
        "if",      "import",   "in",     "is",     "lambda",   "None",
        "nonlocal", "not",      "or",     "pass",   "raise",    "return",
        "True",    "try",      "while",  "with",   "yield",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, s, kw)) return true;
    }
    return false;
}
