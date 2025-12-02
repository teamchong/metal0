/// Self-usage detection for method bodies
const std = @import("std");
const ast = @import("ast");

/// unittest assertion methods that dispatch to runtime (self isn't used in generated code)
/// Public so other modules can check against this list
pub const unittest_assertion_methods = std.StaticStringMap(void).initComptime(.{
    .{ "assertEqual", {} },
    .{ "assertTrue", {} },
    .{ "assertFalse", {} },
    .{ "assertIsNone", {} },
    .{ "assertGreater", {} },
    .{ "assertLess", {} },
    .{ "assertGreaterEqual", {} },
    .{ "assertLessEqual", {} },
    .{ "assertNotEqual", {} },
    .{ "assertIs", {} },
    .{ "assertIsNot", {} },
    .{ "assertIsNotNone", {} },
    .{ "assertIn", {} },
    .{ "assertNotIn", {} },
    .{ "assertAlmostEqual", {} },
    .{ "assertNotAlmostEqual", {} },
    .{ "assertCountEqual", {} },
    .{ "assertRaises", {} },
    .{ "assertRaisesRegex", {} },
    .{ "assertWarns", {} },
    .{ "assertWarnsRegex", {} },
    .{ "assertLogs", {} },
    .{ "assertNoLogs", {} },
    .{ "assertRegex", {} },
    .{ "assertNotRegex", {} },
    .{ "assertIsInstance", {} },
    .{ "assertNotIsInstance", {} },
    .{ "assertIsSubclass", {} },
    .{ "assertNotIsSubclass", {} },
    .{ "assertMultiLineEqual", {} },
    .{ "assertSequenceEqual", {} },
    .{ "assertListEqual", {} },
    .{ "assertTupleEqual", {} },
    .{ "assertSetEqual", {} },
    .{ "assertDictEqual", {} },
    .{ "assertHasAttr", {} },
    .{ "assertNotHasAttr", {} },
    .{ "assertStartsWith", {} },
    .{ "assertNotStartsWith", {} },
    .{ "assertEndsWith", {} },
    .{ "assertNotEndsWith", {} },
    .{ "assertFloatsAreIdentical", {} },
    // Note: addCleanup is NOT in this list because it needs self in generated code
    // (unlike assertions which dispatch to runtime.unittest without self)
    .{ "subTest", {} },
    .{ "fail", {} },
    .{ "skipTest", {} },
});

/// Check if the first parameter (typically 'self') is used in method body
/// NOTE: Excludes unittest assertion methods like self.assertEqual() because
/// they're dispatched to runtime.unittest and don't actually use self
pub fn usesSelf(body: []ast.Node) bool {
    return usesSelfWithContext(body, true);
}

/// Check if the first parameter is used, with configurable parameter name
/// This handles cases like `def method(test_self):` where Python uses non-"self" names
pub fn usesFirstParam(body: []ast.Node, first_param_name: []const u8) bool {
    return usesFirstParamWithContext(body, first_param_name, true);
}

/// Check if the first parameter is used in method body, with context about parent class
/// @param first_param_name: the actual name of the first parameter (could be "self", "test_self", "cls", etc.)
/// @param has_parent: whether the class has a known parent class for super() calls
/// If has_parent is false, super() calls don't count as using self because
/// they will be compiled to no-ops ({})
pub fn usesFirstParamWithContext(body: []ast.Node, first_param_name: []const u8, has_parent: bool) bool {
    for (body) |stmt| {
        if (stmtUsesFirstParamWithContext(stmt, first_param_name, has_parent)) return true;
    }
    return false;
}

/// Check if 'self' is used in method body, with context about parent class
/// @param has_parent: whether the class has a known parent class for super() calls
/// If has_parent is false, super() calls don't count as using self because
/// they will be compiled to no-ops ({})
pub fn usesSelfWithContext(body: []ast.Node, has_parent: bool) bool {
    return usesFirstParamWithContext(body, "self", has_parent);
}

fn stmtUsesSelf(node: ast.Node) bool {
    return stmtUsesSelfWithContext(node, true);
}

fn stmtUsesSelfWithContext(node: ast.Node, has_parent: bool) bool {
    return stmtUsesFirstParamWithContext(node, "self", has_parent);
}

fn stmtUsesFirstParamWithContext(node: ast.Node, param_name: []const u8, has_parent: bool) bool {
    return switch (node) {
        .assign => |assign| {
            // Check if target is param.attr
            for (assign.targets) |target| {
                if (exprUsesFirstParamWithContext(target, param_name, has_parent)) return true;
            }
            // Check if value uses param
            return exprUsesFirstParamWithContext(assign.value.*, param_name, has_parent);
        },
        .aug_assign => |aug| {
            // Check if target is param.attr (e.g., self.count += 1)
            if (exprUsesFirstParamWithContext(aug.target.*, param_name, has_parent)) return true;
            return exprUsesFirstParamWithContext(aug.value.*, param_name, has_parent);
        },
        .expr_stmt => |expr| exprUsesFirstParamWithContext(expr.value.*, param_name, has_parent),
        .return_stmt => |ret| if (ret.value) |val| exprUsesFirstParamWithContext(val.*, param_name, has_parent) else false,
        .if_stmt => |if_stmt| {
            if (exprUsesFirstParamWithContext(if_stmt.condition.*, param_name, has_parent)) return true;
            if (usesFirstParamWithContext(if_stmt.body, param_name, has_parent)) return true;
            if (usesFirstParamWithContext(if_stmt.else_body, param_name, has_parent)) return true;
            return false;
        },
        .while_stmt => |while_stmt| {
            if (exprUsesFirstParamWithContext(while_stmt.condition.*, param_name, has_parent)) return true;
            return usesFirstParamWithContext(while_stmt.body, param_name, has_parent);
        },
        .for_stmt => |for_stmt| {
            // Check both the iterator expression AND the body
            if (exprUsesFirstParamWithContext(for_stmt.iter.*, param_name, has_parent)) return true;
            return usesFirstParamWithContext(for_stmt.body, param_name, has_parent);
        },
        .try_stmt => |try_stmt| {
            // Check try body
            if (usesFirstParamWithContext(try_stmt.body, param_name, has_parent)) return true;
            // Check exception handlers
            for (try_stmt.handlers) |handler| {
                if (usesFirstParamWithContext(handler.body, param_name, has_parent)) return true;
            }
            // Check else body
            if (usesFirstParamWithContext(try_stmt.else_body, param_name, has_parent)) return true;
            // Check finally body
            if (usesFirstParamWithContext(try_stmt.finalbody, param_name, has_parent)) return true;
            return false;
        },
        .function_def => |func_def| {
            // Check if nested function body uses param (closures that capture param)
            return usesFirstParamWithContext(func_def.body, param_name, has_parent);
        },
        .with_stmt => |with_stmt| {
            // Check if context expression uses param
            // Skip unittest context managers (param.subTest, param.assertRaises, etc.)
            // because they're dispatched to runtime and don't actually use param
            const is_unittest_context = blk: {
                if (with_stmt.context_expr.* == .call) {
                    const call = with_stmt.context_expr.call;
                    if (call.func.* == .attribute) {
                        const func_attr = call.func.attribute;
                        if (func_attr.value.* == .name and
                            std.mem.eql(u8, func_attr.value.name.id, param_name) and
                            unittest_assertion_methods.has(func_attr.attr))
                        {
                            break :blk true;
                        }
                    }
                }
                break :blk false;
            };
            if (!is_unittest_context and exprUsesFirstParamWithContext(with_stmt.context_expr.*, param_name, has_parent)) return true;
            // Check if body uses param
            return usesFirstParamWithContext(with_stmt.body, param_name, has_parent);
        },
        else => false,
    };
}

/// Check if expression uses self - for with statement context expressions
/// This version does NOT filter out unittest methods (self.subTest) because
/// the context manager pattern still uses self even if the method is a unittest helper
fn exprUsesSelfForWith(node: ast.Node) bool {
    return switch (node) {
        .name => |name| std.mem.eql(u8, name.id, "self"),
        .attribute => |attr| exprUsesSelfForWith(attr.value.*),
        .call => |call| {
            // For with statements, we want to detect self usage even in unittest methods
            if (exprUsesSelfForWith(call.func.*)) return true;
            for (call.args) |arg| {
                if (exprUsesSelfForWith(arg)) return true;
            }
            return false;
        },
        else => false,
    };
}

/// Check if expression uses self without filtering unittest methods
/// Used for lambda closures which need to capture self even when calling unittest methods
fn exprUsesSelfRaw(node: ast.Node) bool {
    return exprUsesFirstParamRaw(node, "self");
}

/// Check if expression uses the first parameter without filtering unittest methods
/// Used for lambda closures which need to capture the param even when calling unittest methods
fn exprUsesFirstParamRaw(node: ast.Node, param_name: []const u8) bool {
    return switch (node) {
        .name => |name| std.mem.eql(u8, name.id, param_name),
        .attribute => |attr| exprUsesFirstParamRaw(attr.value.*, param_name),
        .call => |call| {
            if (exprUsesFirstParamRaw(call.func.*, param_name)) return true;
            for (call.args) |arg| {
                if (exprUsesFirstParamRaw(arg, param_name)) return true;
            }
            for (call.keyword_args) |kw| {
                if (exprUsesFirstParamRaw(kw.value, param_name)) return true;
            }
            return false;
        },
        .binop => |binop| exprUsesFirstParamRaw(binop.left.*, param_name) or exprUsesFirstParamRaw(binop.right.*, param_name),
        .boolop => |boolop| blk: {
            for (boolop.values) |value| {
                if (exprUsesFirstParamRaw(value, param_name)) break :blk true;
            }
            break :blk false;
        },
        .compare => |comp| blk: {
            if (exprUsesFirstParamRaw(comp.left.*, param_name)) break :blk true;
            for (comp.comparators) |c| {
                if (exprUsesFirstParamRaw(c, param_name)) break :blk true;
            }
            break :blk false;
        },
        .subscript => |sub| exprUsesFirstParamRaw(sub.value.*, param_name) or
            (if (sub.slice == .index) exprUsesFirstParamRaw(sub.slice.index.*, param_name) else false),
        .unaryop => |unary| exprUsesFirstParamRaw(unary.operand.*, param_name),
        .if_expr => |if_expr| exprUsesFirstParamRaw(if_expr.condition.*, param_name) or
            exprUsesFirstParamRaw(if_expr.body.*, param_name) or exprUsesFirstParamRaw(if_expr.orelse_value.*, param_name),
        .tuple => |tup| blk: {
            for (tup.elts) |elt| if (exprUsesFirstParamRaw(elt, param_name)) break :blk true;
            break :blk false;
        },
        .list => |list| blk: {
            for (list.elts) |elt| if (exprUsesFirstParamRaw(elt, param_name)) break :blk true;
            break :blk false;
        },
        .lambda => |lambda| exprUsesFirstParamRaw(lambda.body.*, param_name),
        else => false,
    };
}

fn exprUsesSelf(node: ast.Node) bool {
    return exprUsesSelfWithContext(node, true);
}

fn exprUsesSelfWithContext(node: ast.Node, has_parent: bool) bool {
    return exprUsesFirstParamWithContext(node, "self", has_parent);
}

fn exprUsesFirstParamWithContext(node: ast.Node, param_name: []const u8, has_parent: bool) bool {
    return switch (node) {
        .name => |name| std.mem.eql(u8, name.id, param_name),
        .attribute => |attr| {
            // Check for unittest assertion method references (e.g., eq = self.assertEqual)
            // These are dispatched to runtime.unittest and don't actually use self
            if (attr.value.* == .name and
                std.mem.eql(u8, attr.value.name.id, param_name) and
                unittest_assertion_methods.has(attr.attr))
            {
                return false;
            }
            return exprUsesFirstParamWithContext(attr.value.*, param_name, has_parent);
        },
        .call => |call| {
            // Check for super() calls - they need self ONLY if parent class is known
            // If no parent, super() compiles to no-op {} and doesn't use self
            if (call.func.* == .name and std.mem.eql(u8, call.func.name.id, "super")) {
                return has_parent; // Only uses self if parent exists
            }
            // Also check for super().method() pattern (attribute on super() result)
            if (call.func.* == .attribute) {
                const func_attr = call.func.attribute;
                // Check if value is a super() call
                if (func_attr.value.* == .call) {
                    const inner_call = func_attr.value.call;
                    if (inner_call.func.* == .name and std.mem.eql(u8, inner_call.func.name.id, "super")) {
                        return has_parent; // Only uses self if parent exists
                    }
                }
                // Check for unittest assertion methods (param.assertEqual, etc.)
                // These are dispatched to runtime.unittest and don't actually use param
                if (func_attr.value.* == .name and
                    std.mem.eql(u8, func_attr.value.name.id, param_name) and
                    unittest_assertion_methods.has(func_attr.attr))
                {
                    // This is a unittest assertion - param isn't actually used
                    // But still check the arguments
                    for (call.args) |arg| {
                        if (exprUsesFirstParamWithContext(arg, param_name, has_parent)) return true;
                    }
                    return false;
                }
            }
            if (exprUsesFirstParamWithContext(call.func.*, param_name, has_parent)) return true;
            for (call.args) |arg| {
                if (exprUsesFirstParamWithContext(arg, param_name, has_parent)) return true;
            }
            return false;
        },
        .binop => |binop| exprUsesFirstParamWithContext(binop.left.*, param_name, has_parent) or exprUsesFirstParamWithContext(binop.right.*, param_name, has_parent),
        .boolop => |boolop| {
            // Check all values in the and/or expression
            for (boolop.values) |value| {
                if (exprUsesFirstParamWithContext(value, param_name, has_parent)) return true;
            }
            return false;
        },
        .compare => |comp| {
            if (exprUsesFirstParamWithContext(comp.left.*, param_name, has_parent)) return true;
            for (comp.comparators) |c| {
                if (exprUsesFirstParamWithContext(c, param_name, has_parent)) return true;
            }
            return false;
        },
        .subscript => |sub| {
            if (exprUsesFirstParamWithContext(sub.value.*, param_name, has_parent)) return true;
            return switch (sub.slice) {
                .index => |idx| exprUsesFirstParamWithContext(idx.*, param_name, has_parent),
                .slice => |sl| {
                    if (sl.lower) |l| if (exprUsesFirstParamWithContext(l.*, param_name, has_parent)) return true;
                    if (sl.upper) |u| if (exprUsesFirstParamWithContext(u.*, param_name, has_parent)) return true;
                    if (sl.step) |s| if (exprUsesFirstParamWithContext(s.*, param_name, has_parent)) return true;
                    return false;
                },
            };
        },
        .tuple => |tup| {
            for (tup.elts) |elt| {
                if (exprUsesFirstParamWithContext(elt, param_name, has_parent)) return true;
            }
            return false;
        },
        .list => |list| {
            for (list.elts) |elt| {
                if (exprUsesFirstParamWithContext(elt, param_name, has_parent)) return true;
            }
            return false;
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                if (exprUsesFirstParamWithContext(key, param_name, has_parent)) return true;
            }
            for (dict.values) |val| {
                if (exprUsesFirstParamWithContext(val, param_name, has_parent)) return true;
            }
            return false;
        },
        .unaryop => |unary| exprUsesFirstParamWithContext(unary.operand.*, param_name, has_parent),
        .if_expr => |if_expr| {
            if (exprUsesFirstParamWithContext(if_expr.condition.*, param_name, has_parent)) return true;
            if (exprUsesFirstParamWithContext(if_expr.body.*, param_name, has_parent)) return true;
            if (exprUsesFirstParamWithContext(if_expr.orelse_value.*, param_name, has_parent)) return true;
            return false;
        },
        .lambda => |lambda| {
            // Check if param is used in the lambda body
            // This is critical for closures that capture param
            // Use raw check (without unittest filtering) because lambda closures
            // need to capture param even when calling unittest assertion methods
            return exprUsesFirstParamRaw(lambda.body.*, param_name);
        },
        else => false,
    };
}
