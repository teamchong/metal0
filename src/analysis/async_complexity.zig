/// Analyze async function complexity for comptime optimization decisions
const std = @import("std");
const ast = @import("analysis.ast");

pub const Complexity = enum {
    trivial,   // Single expression, no calls - inline always
    simple,    // Few operations, no loops - prefer inline
    moderate,  // Has loops or multiple awaits - generate both
    complex,   // Recursive or many awaits - spawn only
};

/// Analyze function complexity
pub fn analyzeFunction(func: ast.Node.FunctionDef) Complexity {
    var ctx = AnalysisContext{
        .func_name = func.name,
        .op_count = 0,
        .await_count = 0,
        .has_loops = false,
        .is_recursive = false,
    };

    // Walk function body
    for (func.body) |stmt| {
        analyzeStmt(&ctx, stmt);
    }

    // Classify based on metrics
    if (ctx.op_count <= 5 and ctx.await_count == 0 and !ctx.has_loops) {
        return .trivial;
    }
    if (ctx.op_count <= 20 and ctx.await_count <= 1 and !ctx.has_loops and !ctx.is_recursive) {
        return .simple;
    }
    if (!ctx.is_recursive and ctx.await_count <= 5) {
        return .moderate;
    }
    return .complex;
}

const AnalysisContext = struct {
    func_name: []const u8,
    op_count: usize,
    await_count: usize,
    has_loops: bool,
    is_recursive: bool,
};

fn analyzeStmt(ctx: *AnalysisContext, stmt: ast.Node) void {
    switch (stmt) {
        .expr_stmt => |expr_stmt| {
            analyzeExpr(ctx, expr_stmt.value.*);
        },
        .assign => |assign| {
            analyzeExpr(ctx, assign.value.*);
            ctx.op_count += 1;
        },
        .return_stmt => |ret| {
            if (ret.value) |val| {
                analyzeExpr(ctx, val.*);
            }
            ctx.op_count += 1;
        },
        .if_stmt => |if_stmt| {
            analyzeExpr(ctx, if_stmt.condition.*);
            for (if_stmt.body) |s| {
                analyzeStmt(ctx, s);
            }
            for (if_stmt.else_body) |s| {
                analyzeStmt(ctx, s);
            }
            ctx.op_count += 2; // Branch overhead
        },
        .while_stmt => |while_stmt| {
            ctx.has_loops = true;
            analyzeExpr(ctx, while_stmt.condition.*);
            for (while_stmt.body) |s| {
                analyzeStmt(ctx, s);
            }
            ctx.op_count += 5; // Loop overhead
        },
        .for_stmt => |for_stmt| {
            ctx.has_loops = true;
            analyzeExpr(ctx, for_stmt.iterable.*);
            for (for_stmt.body) |s| {
                analyzeStmt(ctx, s);
            }
            ctx.op_count += 5; // Loop overhead
        },
        else => {
            ctx.op_count += 1;
        },
    }
}

fn analyzeExpr(ctx: *AnalysisContext, expr: ast.Node) void {
    switch (expr) {
        .await_expr => |await_expr| {
            ctx.await_count += 1;
            analyzeExpr(ctx, await_expr.value.*);
        },
        .call => |call| {
            // Check for recursion
            if (call.func.* == .name) {
                if (std.mem.eql(u8, call.func.name.id, ctx.func_name)) {
                    ctx.is_recursive = true;
                }
            }
            analyzeExpr(ctx, call.func.*);
            for (call.args) |arg| {
                analyzeExpr(ctx, arg);
            }
            for (call.keyword_args) |kw| {
                analyzeExpr(ctx, kw.value);
            }
            ctx.op_count += 2; // Call overhead
        },
        .binop => |b| {
            analyzeExpr(ctx, b.left.*);
            analyzeExpr(ctx, b.right.*);
            ctx.op_count += 1;
        },
        .unaryop => |u| {
            analyzeExpr(ctx, u.operand.*);
            ctx.op_count += 1;
        },
        .boolop => |b| {
            for (b.values) |v| {
                analyzeExpr(ctx, v);
            }
            ctx.op_count += 1;
        },
        .compare => |compare| {
            analyzeExpr(ctx, compare.left.*);
            for (compare.comparators) |comp| {
                analyzeExpr(ctx, comp);
            }
            ctx.op_count += 1;
        },
        .if_expr => |ie| {
            analyzeExpr(ctx, ie.condition.*);
            analyzeExpr(ctx, ie.body.*);
            analyzeExpr(ctx, ie.orelse_value.*);
            ctx.op_count += 1;
        },
        .subscript => |sub| {
            analyzeExpr(ctx, sub.value.*);
            switch (sub.slice) {
                .index => |idx| analyzeExpr(ctx, idx.*),
                .slice => |sr| {
                    if (sr.lower) |l| analyzeExpr(ctx, l.*);
                    if (sr.upper) |u| analyzeExpr(ctx, u.*);
                    if (sr.step) |s| analyzeExpr(ctx, s.*);
                },
            }
            ctx.op_count += 1;
        },
        .attribute => |attr| {
            analyzeExpr(ctx, attr.value.*);
            ctx.op_count += 1;
        },
        .list => |list| {
            for (list.elts) |elt| {
                analyzeExpr(ctx, elt);
            }
            ctx.op_count += 1;
        },
        .tuple => |tuple| {
            for (tuple.elts) |elt| {
                analyzeExpr(ctx, elt);
            }
            ctx.op_count += 1;
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                analyzeExpr(ctx, key);
            }
            for (dict.values) |val| {
                analyzeExpr(ctx, val);
            }
            ctx.op_count += 1;
        },
        .fstring => |fs| {
            for (fs.parts) |part| {
                switch (part) {
                    .expr => |e| analyzeExpr(ctx, e.node.*),
                    .format_expr => |fe| analyzeExpr(ctx, fe.expr.*),
                    .conv_expr => |ce| analyzeExpr(ctx, ce.expr.*),
                    .literal => {},
                }
            }
            ctx.op_count += 1;
        },
        .listcomp => |lc| {
            analyzeExpr(ctx, lc.elt.*);
            for (lc.generators) |gen| {
                analyzeExpr(ctx, gen.iter.*);
                for (gen.ifs) |cond| analyzeExpr(ctx, cond);
            }
            ctx.op_count += 3; // Comprehensions are expensive
        },
        .dictcomp => |dc| {
            analyzeExpr(ctx, dc.key.*);
            analyzeExpr(ctx, dc.value.*);
            for (dc.generators) |gen| {
                analyzeExpr(ctx, gen.iter.*);
                for (gen.ifs) |cond| analyzeExpr(ctx, cond);
            }
            ctx.op_count += 3;
        },
        .genexp => |ge| {
            analyzeExpr(ctx, ge.elt.*);
            for (ge.generators) |gen| {
                analyzeExpr(ctx, gen.iter.*);
                for (gen.ifs) |cond| analyzeExpr(ctx, cond);
            }
            ctx.op_count += 2;
        },
        .lambda => |lam| {
            analyzeExpr(ctx, lam.body.*);
            ctx.op_count += 1;
        },
        .starred => |st| analyzeExpr(ctx, st.value.*),
        else => {
            // Leaf nodes (constants, names, etc.)
        },
    }
}

/// Check if function only contains a single return expression
pub fn isSingleExpressionReturn(func: ast.Node.FunctionDef) bool {
    if (func.body.len != 1) return false;

    const stmt = func.body[0];
    if (stmt != .return_stmt) return false;

    return stmt.return_stmt.value != null;
}

/// Check if function is pure (no I/O, no side effects)
pub fn isPureFunction(func: ast.Node.FunctionDef) bool {
    var ctx = PurityContext{
        .has_io = false,
        .has_mutation = false,
    };

    for (func.body) |stmt| {
        checkPurity(&ctx, stmt);
    }

    return !ctx.has_io and !ctx.has_mutation;
}

const PurityContext = struct {
    has_io: bool,
    has_mutation: bool,
};

fn checkPurity(ctx: *PurityContext, stmt: ast.Node) void {
    switch (stmt) {
        .expr_stmt => |expr_stmt| {
            checkExprPurity(ctx, expr_stmt.value.*);
        },
        .assign => |assign| {
            // Check if mutating external state
            if (assign.targets.len > 0) {
                const target = assign.targets[0];
                if (target == .attribute or target == .subscript) {
                    ctx.has_mutation = true;
                }
            }
            checkExprPurity(ctx, assign.value.*);
        },
        .return_stmt => |ret| {
            if (ret.value) |val| {
                checkExprPurity(ctx, val.*);
            }
        },
        .if_stmt => |if_stmt| {
            checkExprPurity(ctx, if_stmt.condition.*);
            for (if_stmt.body) |s| {
                checkPurity(ctx, s);
            }
            for (if_stmt.else_body) |s| {
                checkPurity(ctx, s);
            }
        },
        .while_stmt => |while_stmt| {
            checkExprPurity(ctx, while_stmt.condition.*);
            for (while_stmt.body) |s| {
                checkPurity(ctx, s);
            }
        },
        .for_stmt => |for_stmt| {
            checkExprPurity(ctx, for_stmt.iterable.*);
            for (for_stmt.body) |s| {
                checkPurity(ctx, s);
            }
        },
        else => {},
    }
}

fn checkExprPurity(ctx: *PurityContext, expr: ast.Node) void {
    switch (expr) {
        .call => |call| {
            // Check for I/O functions
            if (call.func == .name) {
                const func_name = call.func.name.id;
                if (std.mem.eql(u8, func_name, "print") or
                    std.mem.eql(u8, func_name, "input") or
                    std.mem.eql(u8, func_name, "open"))
                {
                    ctx.has_io = true;
                }
            } else if (call.func == .attribute) {
                // Check for method calls that might do I/O
                const attr = call.func.attribute;
                if (std.mem.eql(u8, attr.attr, "write") or
                    std.mem.eql(u8, attr.attr, "read") or
                    std.mem.eql(u8, attr.attr, "close"))
                {
                    ctx.has_io = true;
                }
            }

            checkExprPurity(ctx, call.func.*);
            for (call.args) |arg| {
                checkExprPurity(ctx, arg);
            }
        },
        .await_expr => |await_expr| {
            checkExprPurity(ctx, await_expr.value.*);
        },
        .bin_op => |bin_op| {
            checkExprPurity(ctx, bin_op.left.*);
            checkExprPurity(ctx, bin_op.right.*);
        },
        .unary_op => |unary_op| {
            checkExprPurity(ctx, unary_op.operand.*);
        },
        .compare => |compare| {
            checkExprPurity(ctx, compare.left.*);
            for (compare.comparators) |comp| {
                checkExprPurity(ctx, comp);
            }
        },
        .subscript => |subscript| {
            checkExprPurity(ctx, subscript.value.*);
            checkExprPurity(ctx, subscript.slice.*);
        },
        .attribute => |attr| {
            checkExprPurity(ctx, attr.value.*);
        },
        .list => |list| {
            for (list.elts) |elt| {
                checkExprPurity(ctx, elt);
            }
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                checkExprPurity(ctx, key);
            }
            for (dict.values) |val| {
                checkExprPurity(ctx, val);
            }
        },
        else => {},
    }
}
