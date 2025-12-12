/// Helper functions for assignment code generation
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const string_traits = @import("../../../analysis/traits/string_traits.zig");

/// Check if a node is a compile-time constant (can use comptime)
pub fn isComptimeConstant(node: ast.Node) bool {
    return switch (node) {
        .constant => true,
        .unaryop => |u| isComptimeConstant(u.operand.*),
        .binop => |b| isComptimeConstant(b.left.*) and isComptimeConstant(b.right.*),
        else => false,
    };
}

/// Check if an expression contains a reference to a variable name
/// Used to detect self-referencing assignments like: x = x + 1
pub fn valueContainsName(node: ast.Node, name: []const u8) bool {
    switch (node) {
        .name => |n| return std.mem.eql(u8, n.id, name),
        .binop => |binop| {
            return valueContainsName(binop.left.*, name) or valueContainsName(binop.right.*, name);
        },
        .unaryop => |unary| {
            return valueContainsName(unary.operand.*, name);
        },
        .boolop => |boolop| {
            for (boolop.values) |v| {
                if (valueContainsName(v, name)) return true;
            }
            return false;
        },
        .compare => |cmp| {
            if (valueContainsName(cmp.left.*, name)) return true;
            for (cmp.comparators) |c| {
                if (valueContainsName(c, name)) return true;
            }
            return false;
        },
        .call => |call| {
            if (valueContainsName(call.func.*, name)) return true;
            for (call.args) |arg| {
                if (valueContainsName(arg, name)) return true;
            }
            for (call.keyword_args) |kw| {
                if (valueContainsName(kw.value, name)) return true;
            }
            return false;
        },
        .attribute => |attr| {
            return valueContainsName(attr.value.*, name);
        },
        .subscript => |subscript| {
            if (valueContainsName(subscript.value.*, name)) return true;
            switch (subscript.slice) {
                .index => |idx| return valueContainsName(idx.*, name),
                .slice => |slice| {
                    if (slice.lower) |lower| {
                        if (valueContainsName(lower.*, name)) return true;
                    }
                    if (slice.upper) |upper| {
                        if (valueContainsName(upper.*, name)) return true;
                    }
                    if (slice.step) |step| {
                        if (valueContainsName(step.*, name)) return true;
                    }
                    return false;
                },
            }
        },
        .if_expr => |ie| {
            return valueContainsName(ie.condition.*, name) or
                valueContainsName(ie.body.*, name) or
                valueContainsName(ie.orelse_value.*, name);
        },
        .list => |list| {
            for (list.elts) |elt| {
                if (valueContainsName(elt, name)) return true;
            }
            return false;
        },
        .tuple => |tuple| {
            for (tuple.elts) |elt| {
                if (valueContainsName(elt, name)) return true;
            }
            return false;
        },
        .dict => |dict| {
            for (dict.keys) |k| {
                if (valueContainsName(k, name)) return true;
            }
            for (dict.values) |v| {
                if (valueContainsName(v, name)) return true;
            }
            return false;
        },
        .fstring => |fstr| {
            for (fstr.parts) |part| {
                switch (part) {
                    .expr => |e| if (valueContainsName(e.node.*, name)) return true,
                    .format_expr => |fe| if (valueContainsName(fe.expr.*, name)) return true,
                    .conv_expr => |ce| if (valueContainsName(ce.expr.*, name)) return true,
                    .literal => {},
                }
            }
            return false;
        },
        .listcomp => |lc| {
            if (valueContainsName(lc.elt.*, name)) return true;
            for (lc.generators) |gen| {
                if (valueContainsName(gen.iter.*, name)) return true;
                for (gen.ifs) |cond| {
                    if (valueContainsName(cond, name)) return true;
                }
            }
            return false;
        },
        .dictcomp => |dc| {
            if (valueContainsName(dc.key.*, name) or valueContainsName(dc.value.*, name)) return true;
            for (dc.generators) |gen| {
                if (valueContainsName(gen.iter.*, name)) return true;
                for (gen.ifs) |cond| {
                    if (valueContainsName(cond, name)) return true;
                }
            }
            return false;
        },
        .genexp => |ge| {
            if (valueContainsName(ge.elt.*, name)) return true;
            for (ge.generators) |gen| {
                if (valueContainsName(gen.iter.*, name)) return true;
                for (gen.ifs) |cond| {
                    if (valueContainsName(cond, name)) return true;
                }
            }
            return false;
        },
        .lambda => |lam| valueContainsName(lam.body.*, name),
        .starred => |s| valueContainsName(s.value.*, name),
        else => return false,
    }
}

/// Flatten nested string concatenation into a list of parts
/// (s1 + " ") + s2 becomes [s1, " ", s2]
pub fn flattenConcat(self: *NativeCodegen, node: ast.Node, parts: *std.ArrayList(ast.Node)) CodegenError!void {
    if (node == .binop and node.binop.op == .Add) {
        // Check if this is string concat
        const left_type = try self.type_inferrer.inferExpr(node.binop.left.*);
        const right_type = try self.type_inferrer.inferExpr(node.binop.right.*);

        if (string_traits.isString(left_type) or string_traits.isString(right_type)) {
            // Recursively flatten left side
            try flattenConcat(self, node.binop.left.*, parts);
            // Recursively flatten right side
            try flattenConcat(self, node.binop.right.*, parts);
            return;
        }
    }

    // Not a string concat, just add the node
    try parts.append(self.allocator, node);
}
