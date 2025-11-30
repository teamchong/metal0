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
    .{ "addCleanup", {} },
    .{ "subTest", {} },
    .{ "fail", {} },
    .{ "skipTest", {} },
});

/// Check if 'self' is used in method body
/// NOTE: Excludes unittest assertion methods like self.assertEqual() because
/// they're dispatched to runtime.unittest and don't actually use self
pub fn usesSelf(body: []ast.Node) bool {
    for (body) |stmt| {
        if (stmtUsesSelf(stmt)) return true;
    }
    return false;
}

fn stmtUsesSelf(node: ast.Node) bool {
    return switch (node) {
        .assign => |assign| {
            // Check if target is self.attr
            for (assign.targets) |target| {
                if (exprUsesSelf(target)) return true;
            }
            // Check if value uses self
            return exprUsesSelf(assign.value.*);
        },
        .aug_assign => |aug| {
            // Check if target is self.attr (e.g., self.count += 1)
            if (exprUsesSelf(aug.target.*)) return true;
            return exprUsesSelf(aug.value.*);
        },
        .expr_stmt => |expr| exprUsesSelf(expr.value.*),
        .return_stmt => |ret| if (ret.value) |val| exprUsesSelf(val.*) else false,
        .if_stmt => |if_stmt| {
            if (exprUsesSelf(if_stmt.condition.*)) return true;
            if (usesSelf(if_stmt.body)) return true;
            if (usesSelf(if_stmt.else_body)) return true;
            return false;
        },
        .while_stmt => |while_stmt| {
            if (exprUsesSelf(while_stmt.condition.*)) return true;
            return usesSelf(while_stmt.body);
        },
        .for_stmt => |for_stmt| {
            // Check both the iterator expression AND the body
            if (exprUsesSelf(for_stmt.iter.*)) return true;
            return usesSelf(for_stmt.body);
        },
        .try_stmt => |try_stmt| {
            // Check try body
            if (usesSelf(try_stmt.body)) return true;
            // Check exception handlers
            for (try_stmt.handlers) |handler| {
                if (usesSelf(handler.body)) return true;
            }
            // Check else body
            if (usesSelf(try_stmt.else_body)) return true;
            // Check finally body
            if (usesSelf(try_stmt.finalbody)) return true;
            return false;
        },
        .function_def => |func_def| {
            // Check if nested function body uses self (closures that capture self)
            return usesSelf(func_def.body);
        },
        .with_stmt => |with_stmt| {
            // Check if context expression uses self
            // Skip unittest context managers (self.subTest, self.assertRaises, etc.)
            // because they're dispatched to runtime and don't actually use self
            const is_unittest_context = blk: {
                if (with_stmt.context_expr.* == .call) {
                    const call = with_stmt.context_expr.call;
                    if (call.func.* == .attribute) {
                        const func_attr = call.func.attribute;
                        if (func_attr.value.* == .name and
                            std.mem.eql(u8, func_attr.value.name.id, "self") and
                            unittest_assertion_methods.has(func_attr.attr))
                        {
                            break :blk true;
                        }
                    }
                }
                break :blk false;
            };
            if (!is_unittest_context and exprUsesSelf(with_stmt.context_expr.*)) return true;
            // Check if body uses self
            return usesSelf(with_stmt.body);
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

fn exprUsesSelf(node: ast.Node) bool {
    return switch (node) {
        .name => |name| std.mem.eql(u8, name.id, "self"),
        .attribute => |attr| {
            // Check for unittest assertion method references (e.g., eq = self.assertEqual)
            // These are dispatched to runtime.unittest and don't actually use self
            if (attr.value.* == .name and
                std.mem.eql(u8, attr.value.name.id, "self") and
                unittest_assertion_methods.has(attr.attr))
            {
                return false;
            }
            return exprUsesSelf(attr.value.*);
        },
        .call => |call| {
            // Check for super() calls - they need self because super().foo()
            // translates to ParentClass.foo(self)
            if (call.func.* == .name and std.mem.eql(u8, call.func.name.id, "super")) {
                return true;
            }
            // Also check for super().method() pattern (attribute on super() result)
            if (call.func.* == .attribute) {
                const func_attr = call.func.attribute;
                // Check if value is a super() call
                if (func_attr.value.* == .call) {
                    const inner_call = func_attr.value.call;
                    if (inner_call.func.* == .name and std.mem.eql(u8, inner_call.func.name.id, "super")) {
                        return true;
                    }
                }
                // Check for unittest assertion methods (self.assertEqual, etc.)
                // These are dispatched to runtime.unittest and don't actually use self
                if (func_attr.value.* == .name and
                    std.mem.eql(u8, func_attr.value.name.id, "self") and
                    unittest_assertion_methods.has(func_attr.attr))
                {
                    // This is a unittest assertion - self isn't actually used
                    // But still check the arguments
                    for (call.args) |arg| {
                        if (exprUsesSelf(arg)) return true;
                    }
                    return false;
                }
            }
            if (exprUsesSelf(call.func.*)) return true;
            for (call.args) |arg| {
                if (exprUsesSelf(arg)) return true;
            }
            return false;
        },
        .binop => |binop| exprUsesSelf(binop.left.*) or exprUsesSelf(binop.right.*),
        .compare => |comp| {
            if (exprUsesSelf(comp.left.*)) return true;
            for (comp.comparators) |c| {
                if (exprUsesSelf(c)) return true;
            }
            return false;
        },
        .subscript => |sub| {
            if (exprUsesSelf(sub.value.*)) return true;
            return switch (sub.slice) {
                .index => |idx| exprUsesSelf(idx.*),
                .slice => |sl| {
                    if (sl.lower) |l| if (exprUsesSelf(l.*)) return true;
                    if (sl.upper) |u| if (exprUsesSelf(u.*)) return true;
                    if (sl.step) |s| if (exprUsesSelf(s.*)) return true;
                    return false;
                },
            };
        },
        .tuple => |tup| {
            for (tup.elts) |elt| {
                if (exprUsesSelf(elt)) return true;
            }
            return false;
        },
        .list => |list| {
            for (list.elts) |elt| {
                if (exprUsesSelf(elt)) return true;
            }
            return false;
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                if (exprUsesSelf(key)) return true;
            }
            for (dict.values) |val| {
                if (exprUsesSelf(val)) return true;
            }
            return false;
        },
        .unaryop => |unary| exprUsesSelf(unary.operand.*),
        .if_expr => |if_expr| {
            if (exprUsesSelf(if_expr.condition.*)) return true;
            if (exprUsesSelf(if_expr.body.*)) return true;
            if (exprUsesSelf(if_expr.orelse_value.*)) return true;
            return false;
        },
        .lambda => |lambda| {
            // Check if self is used in the lambda body
            // This is critical for closures that capture self
            return exprUsesSelf(lambda.body.*);
        },
        else => false,
    };
}
