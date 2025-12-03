/// Variable usage analysis for function/method bodies
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../../main.zig").CodegenError;

/// Analyze function body for used variables (variables that are read, not just assigned)
/// This prevents false "unused variable" detection for variables used within function bodies
pub fn analyzeFunctionLocalUses(self: *NativeCodegen, func: ast.Node.FunctionDef) !void {
    self.func_local_uses.clearRetainingCapacity();
    for (func.body) |stmt| {
        try collectUsesInNode(self, stmt);
    }
}

/// Recursively collect variable uses in an AST node
pub fn collectUsesInNode(self: *NativeCodegen, node: ast.Node) !void {
    switch (node) {
        .name => |name| {
            // A name reference is a use (unless it's on the left side of assignment, handled separately)
            try self.func_local_uses.put(name.id, {});
        },
        .call => |call| {
            // Function being called is a use
            try collectUsesInNode(self, call.func.*);
            for (call.args) |arg| {
                try collectUsesInNode(self, arg);
            }
            for (call.keyword_args) |kwarg| {
                try collectUsesInNode(self, kwarg.value);
            }
        },
        .binop => |binop| {
            try collectUsesInNode(self, binop.left.*);
            try collectUsesInNode(self, binop.right.*);
        },
        .unaryop => |unary| {
            try collectUsesInNode(self, unary.operand.*);
        },
        .compare => |compare| {
            try collectUsesInNode(self, compare.left.*);
            for (compare.comparators) |comp| {
                try collectUsesInNode(self, comp);
            }
        },
        .boolop => |boolop| {
            for (boolop.values) |value| {
                try collectUsesInNode(self, value);
            }
        },
        .subscript => |subscript| {
            try collectUsesInNode(self, subscript.value.*);
            switch (subscript.slice) {
                .index => |idx| try collectUsesInNode(self, idx.*),
                .slice => |slice| {
                    if (slice.lower) |lower| try collectUsesInNode(self, lower.*);
                    if (slice.upper) |upper| try collectUsesInNode(self, upper.*);
                    if (slice.step) |step| try collectUsesInNode(self, step.*);
                },
            }
        },
        .attribute => |attr| {
            try collectUsesInNode(self, attr.value.*);
        },
        .list => |list| {
            for (list.elts) |elt| {
                try collectUsesInNode(self, elt);
            }
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                try collectUsesInNode(self, key);
            }
            for (dict.values) |value| {
                try collectUsesInNode(self, value);
            }
        },
        .tuple => |tuple| {
            for (tuple.elts) |elt| {
                try collectUsesInNode(self, elt);
            }
        },
        .set => |set| {
            for (set.elts) |elt| {
                try collectUsesInNode(self, elt);
            }
        },
        .if_expr => |if_expr| {
            try collectUsesInNode(self, if_expr.condition.*);
            try collectUsesInNode(self, if_expr.body.*);
            try collectUsesInNode(self, if_expr.orelse_value.*);
        },
        .lambda => |lambda| {
            try collectUsesInNode(self, lambda.body.*);
        },
        .listcomp => |listcomp| {
            try collectUsesInNode(self, listcomp.elt.*);
            for (listcomp.generators) |gen| {
                try collectUsesInNode(self, gen.iter.*);
                for (gen.ifs) |if_node| {
                    try collectUsesInNode(self, if_node);
                }
            }
        },
        .dictcomp => |dictcomp| {
            try collectUsesInNode(self, dictcomp.key.*);
            try collectUsesInNode(self, dictcomp.value.*);
            for (dictcomp.generators) |gen| {
                try collectUsesInNode(self, gen.iter.*);
                for (gen.ifs) |if_node| {
                    try collectUsesInNode(self, if_node);
                }
            }
        },
        .genexp => |genexp| {
            try collectUsesInNode(self, genexp.elt.*);
            for (genexp.generators) |gen| {
                try collectUsesInNode(self, gen.iter.*);
                for (gen.ifs) |if_node| {
                    try collectUsesInNode(self, if_node);
                }
            }
        },
        // Statements
        .assign => |assign| {
            // Value is a use
            try collectUsesInNode(self, assign.value.*);
            // Targets may contain subscripts with index expressions that are uses
            // e.g., dest[to] = value - 'to' is used here
            for (assign.targets) |target| {
                if (target == .subscript) {
                    // The subscript container and index are uses
                    try collectUsesInNode(self, target.subscript.value.*);
                    switch (target.subscript.slice) {
                        .index => |idx| try collectUsesInNode(self, idx.*),
                        .slice => |slice| {
                            if (slice.lower) |lower| try collectUsesInNode(self, lower.*);
                            if (slice.upper) |upper| try collectUsesInNode(self, upper.*);
                            if (slice.step) |step| try collectUsesInNode(self, step.*);
                        },
                    }
                } else if (target == .attribute) {
                    // For attribute targets like obj.field = value, obj is a use
                    try collectUsesInNode(self, target.attribute.value.*);
                }
                // Simple name targets (x = value) are assignments, not uses
            }
        },
        .ann_assign => |ann_assign| {
            if (ann_assign.value) |value| {
                try collectUsesInNode(self, value.*);
            }
        },
        .aug_assign => |aug| {
            // Both target and value are uses (target is read then written)
            try collectUsesInNode(self, aug.target.*);
            try collectUsesInNode(self, aug.value.*);
        },
        .expr_stmt => |expr| {
            try collectUsesInNode(self, expr.value.*);
        },
        .return_stmt => |ret| {
            if (ret.value) |value| {
                try collectUsesInNode(self, value.*);
            }
        },
        .if_stmt => |if_stmt| {
            try collectUsesInNode(self, if_stmt.condition.*);
            for (if_stmt.body) |body_stmt| {
                try collectUsesInNode(self, body_stmt);
            }
            for (if_stmt.else_body) |else_stmt| {
                try collectUsesInNode(self, else_stmt);
            }
        },
        .while_stmt => |while_stmt| {
            try collectUsesInNode(self, while_stmt.condition.*);
            for (while_stmt.body) |body_stmt| {
                try collectUsesInNode(self, body_stmt);
            }
        },
        .for_stmt => |for_stmt| {
            try collectUsesInNode(self, for_stmt.iter.*);
            for (for_stmt.body) |body_stmt| {
                try collectUsesInNode(self, body_stmt);
            }
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |body_stmt| {
                try collectUsesInNode(self, body_stmt);
            }
            for (try_stmt.handlers) |handler| {
                for (handler.body) |body_stmt| {
                    try collectUsesInNode(self, body_stmt);
                }
            }
            for (try_stmt.else_body) |body_stmt| {
                try collectUsesInNode(self, body_stmt);
            }
            for (try_stmt.finalbody) |body_stmt| {
                try collectUsesInNode(self, body_stmt);
            }
        },
        .with_stmt => |with_stmt| {
            try collectUsesInNode(self, with_stmt.context_expr.*);
            for (with_stmt.body) |body_stmt| {
                try collectUsesInNode(self, body_stmt);
            }
        },
        .assert_stmt => |assert_stmt| {
            try collectUsesInNode(self, assert_stmt.condition.*);
            if (assert_stmt.msg) |msg| {
                try collectUsesInNode(self, msg.*);
            }
        },
        .raise_stmt => |raise| {
            if (raise.exc) |exc| {
                try collectUsesInNode(self, exc.*);
            }
            if (raise.cause) |cause| {
                try collectUsesInNode(self, cause.*);
            }
        },
        .fstring => |fstr| {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |expr| try collectUsesInNode(self, expr.*),
                    .format_expr => |fmt| try collectUsesInNode(self, fmt.expr.*),
                    .conv_expr => |conv| try collectUsesInNode(self, conv.expr.*),
                    .literal => {},
                }
            }
        },
        .named_expr => |named| {
            try collectUsesInNode(self, named.value.*);
        },
        .await_expr => |await_expr| {
            try collectUsesInNode(self, await_expr.value.*);
        },
        .starred => |starred| {
            try collectUsesInNode(self, starred.value.*);
        },
        .double_starred => |double_starred| {
            try collectUsesInNode(self, double_starred.value.*);
        },
        .yield_stmt => |yield| {
            if (yield.value) |value| {
                try collectUsesInNode(self, value.*);
            }
        },
        .yield_from_stmt => |yield_from| {
            try collectUsesInNode(self, yield_from.value.*);
        },
        // Nested class definitions - need to analyze their bodies for uses of outer-scope classes
        .class_def => |class_def| {
            // Check base classes - they reference outer scope (bases are string names)
            for (class_def.bases) |base_name| {
                try self.func_local_uses.put(base_name, {});
            }
            // Analyze class body for uses
            for (class_def.body) |body_stmt| {
                switch (body_stmt) {
                    .function_def => |method| {
                        // Check return type annotation if present - it may reference outer classes
                        // return_type is a string name, so just mark it as used
                        if (method.return_type) |ret_type_name| {
                            try self.func_local_uses.put(ret_type_name, {});
                        }
                        // Analyze method body for references to outer-scope classes
                        for (method.body) |method_stmt| {
                            try collectUsesInNode(self, method_stmt);
                        }
                    },
                    else => try collectUsesInNode(self, body_stmt),
                }
            }
        },
        // Skip these - they don't contain variable uses
        .constant, .pass, .break_stmt, .continue_stmt, .ellipsis_literal,
        .import_stmt, .import_from, .global_stmt, .nonlocal_stmt,
        .function_def, .del_stmt => {},
        // Catch-all for other node types
        else => {},
    }
}
