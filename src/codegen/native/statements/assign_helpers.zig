/// Helper functions for assignment code generation
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

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
        .call => |call| {
            if (valueContainsName(call.func.*, name)) return true;
            for (call.args) |arg| {
                if (valueContainsName(arg, name)) return true;
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

        if (left_type == .string or right_type == .string) {
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
