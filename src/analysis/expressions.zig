const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("types.zig");

/// Detect expression chains for optimization
pub fn analyzeExpressions(info: *types.SemanticInfo, node: ast.Node) !void {
    switch (node) {
        .module => |module| {
            for (module.body) |body_node| {
                try analyzeExpressions(info, body_node);
            }
        },
        .binop => |binop| {
            // Check if this is part of a chain of same operations
            try detectChain(info, node);

            // Recursively analyze children
            try analyzeExpressions(info, binop.left.*);
            try analyzeExpressions(info, binop.right.*);
        },
        .assign => |assign| {
            try analyzeExpressions(info, assign.value.*);
        },
        .aug_assign => |aug| {
            try analyzeExpressions(info, aug.value.*);
        },
        .call => |call| {
            try analyzeExpressions(info, call.func.*);
            for (call.args) |arg| {
                try analyzeExpressions(info, arg);
            }
        },
        .if_stmt => |if_stmt| {
            try analyzeExpressions(info, if_stmt.condition.*);
            for (if_stmt.body) |body_node| {
                try analyzeExpressions(info, body_node);
            }
            for (if_stmt.else_body) |else_node| {
                try analyzeExpressions(info, else_node);
            }
        },
        .for_stmt => |for_stmt| {
            try analyzeExpressions(info, for_stmt.iter.*);
            for (for_stmt.body) |body_node| {
                try analyzeExpressions(info, body_node);
            }
        },
        .while_stmt => |while_stmt| {
            try analyzeExpressions(info, while_stmt.condition.*);
            for (while_stmt.body) |body_node| {
                try analyzeExpressions(info, body_node);
            }
        },
        .function_def => |func| {
            for (func.body) |body_node| {
                try analyzeExpressions(info, body_node);
            }
        },
        .class_def => |class_def| {
            for (class_def.body) |body_node| {
                try analyzeExpressions(info, body_node);
            }
        },
        .compare => |compare| {
            try analyzeExpressions(info, compare.left.*);
            for (compare.comparators) |comp| {
                try analyzeExpressions(info, comp);
            }
        },
        .boolop => |boolop| {
            for (boolop.values) |value| {
                try analyzeExpressions(info, value);
            }
        },
        .unaryop => |unary| {
            try analyzeExpressions(info, unary.operand.*);
        },
        .return_stmt => |ret| {
            if (ret.value) |value| {
                try analyzeExpressions(info, value.*);
            }
        },
        .list => |list| {
            for (list.elts) |elt| {
                try analyzeExpressions(info, elt);
            }
        },
        .listcomp => |listcomp| {
            try analyzeExpressions(info, listcomp.iter.*);
            try analyzeExpressions(info, listcomp.elt.*);
            for (listcomp.ifs) |if_node| {
                try analyzeExpressions(info, if_node);
            }
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                try analyzeExpressions(info, key);
            }
            for (dict.values) |value| {
                try analyzeExpressions(info, value);
            }
        },
        .tuple => |tuple| {
            for (tuple.elts) |elt| {
                try analyzeExpressions(info, elt);
            }
        },
        .subscript => |subscript| {
            try analyzeExpressions(info, subscript.value.*);
            switch (subscript.slice) {
                .index => |idx| {
                    try analyzeExpressions(info, idx.*);
                },
                .slice => |slice| {
                    if (slice.lower) |lower| {
                        try analyzeExpressions(info, lower.*);
                    }
                    if (slice.upper) |upper| {
                        try analyzeExpressions(info, upper.*);
                    }
                    if (slice.step) |step| {
                        try analyzeExpressions(info, step.*);
                    }
                },
            }
        },
        .attribute => |attr| {
            try analyzeExpressions(info, attr.value.*);
        },
        .expr_stmt => |expr| {
            try analyzeExpressions(info, expr.value.*);
        },
        .await_expr => |await_expr| {
            try analyzeExpressions(info, await_expr.value.*);
        },
        .assert_stmt => |assert_stmt| {
            try analyzeExpressions(info, assert_stmt.condition.*);
            if (assert_stmt.msg) |msg| {
                try analyzeExpressions(info, msg.*);
            }
        },
        // Leaf nodes
        .name, .constant, .import_stmt, .import_from => {
            // No expressions to analyze
        },
    }
}

/// Detect if a binop is part of a chain of similar operations
fn detectChain(info: *types.SemanticInfo, node: ast.Node) !void {
    if (node != .binop) return;

    const binop = node.binop;
    var chain_length: usize = 1;
    var is_string_op = false;

    // Check if left side is same operation
    if (binop.left.* == .binop and binop.left.binop.op == binop.op) {
        chain_length += 1;
    }

    // Check if right side is same operation
    if (binop.right.* == .binop and binop.right.binop.op == binop.op) {
        chain_length += 1;
    }

    // Only record chains of length > 1
    if (chain_length > 1) {
        // Detect if this is a string operation
        // TODO: This is a stub - would need type information
        if (binop.op == .Add) {
            is_string_op = false; // Conservative default
        }

        var chain = try types.ExpressionChain.init(info.allocator, binop.op, is_string_op);
        chain.chain_length = chain_length;
        try info.expr_chains.append(info.allocator, chain);
    }
}
