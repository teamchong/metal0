const std = @import("std");
const ast = @import("ast");
const comptime_eval = @import("comptime_eval");
const ComptimeEvaluator = comptime_eval.ComptimeEvaluator;
const ComptimeValue = comptime_eval.ComptimeValue;

test "comptime eval - int literals" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const node = ast.Node{ .constant = .{ .value = .{ .int = 42 } } };
    const result = evaluator.tryEval(node).?;

    try std.testing.expectEqual(ComptimeValue{ .int = 42 }, result);
}

test "comptime eval - float literals" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const node = ast.Node{ .constant = .{ .value = .{ .float = 3.14 } } };
    const result = evaluator.tryEval(node).?;

    try std.testing.expectEqual(ComptimeValue{ .float = 3.14 }, result);
}

test "comptime eval - bool literals" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const true_node = ast.Node{ .constant = .{ .value = .{ .bool = true } } };
    const true_result = evaluator.tryEval(true_node).?;
    try std.testing.expectEqual(ComptimeValue{ .bool = true }, true_result);

    const false_node = ast.Node{ .constant = .{ .value = .{ .bool = false } } };
    const false_result = evaluator.tryEval(false_node).?;
    try std.testing.expectEqual(ComptimeValue{ .bool = false }, false_result);
}

test "comptime eval - string literals" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const node = ast.Node{ .constant = .{ .value = .{ .string = "hello" } } };
    const result = evaluator.tryEval(node).?;

    try std.testing.expectEqualStrings("hello", result.string);
}

test "comptime eval - addition int+int" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 2 } } };

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .int = 3 } } };

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .Add,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .int = 5 }, result);
}

test "comptime eval - addition int+float" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 2 } } };

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .float = 3.5 } } };

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .Add,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .float = 5.5 }, result);
}

test "comptime eval - subtraction" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 10 } } };

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .int = 3 } } };

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .Sub,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .int = 7 }, result);
}

test "comptime eval - multiplication" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 10 } } };

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .int = 5 } } };

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .Mult,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .int = 50 }, result);
}

test "comptime eval - division int/int returns float" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 100 } } };

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .int = 4 } } };

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .Div,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .float = 25.0 }, result);
}

test "comptime eval - floor division" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 17 } } };

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .int = 5 } } };

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .FloorDiv,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .int = 3 }, result);
}

test "comptime eval - modulo" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 17 } } };

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .int = 5 } } };

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .Mod,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .int = 2 }, result);
}

test "comptime eval - power" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 2 } } };

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .int = 3 } } };

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .Pow,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .int = 8 }, result);
}

test "comptime eval - string concatenation" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .string = "hello" } } };

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .string = " world" } } };

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .Add,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqualStrings("hello world", result.string);
    std.testing.allocator.free(result.string);
}

test "comptime eval - string repetition" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .string = "hi" } } };

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .int = 3 } } };

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .Mult,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqualStrings("hihihi", result.string);
    std.testing.allocator.free(result.string);
}

test "comptime eval - comparison equal" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 5 } } };

    var comparators = [_]ast.Node{ast.Node{ .constant = .{ .value = .{ .int = 5 } } }};
    var ops = [_]ast.CompareOp{.Eq};

    const expr = ast.Node{ .compare = .{
        .left = left,
        .ops = &ops,
        .comparators = &comparators,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .bool = true }, result);
}

test "comptime eval - comparison not equal" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 5 } } };

    var comparators = [_]ast.Node{ast.Node{ .constant = .{ .value = .{ .int = 3 } } }};
    var ops = [_]ast.CompareOp{.NotEq};

    const expr = ast.Node{ .compare = .{
        .left = left,
        .ops = &ops,
        .comparators = &comparators,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .bool = true }, result);
}

test "comptime eval - comparison less than" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 3 } } };

    var comparators = [_]ast.Node{ast.Node{ .constant = .{ .value = .{ .int = 5 } } }};
    var ops = [_]ast.CompareOp{.Lt};

    const expr = ast.Node{ .compare = .{
        .left = left,
        .ops = &ops,
        .comparators = &comparators,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .bool = true }, result);
}

test "comptime eval - comparison greater than" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 10 } } };

    var comparators = [_]ast.Node{ast.Node{ .constant = .{ .value = .{ .int = 5 } } }};
    var ops = [_]ast.CompareOp{.Gt};

    const expr = ast.Node{ .compare = .{
        .left = left,
        .ops = &ops,
        .comparators = &comparators,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .bool = true }, result);
}

test "comptime eval - logical and (true)" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    var values = [_]ast.Node{
        ast.Node{ .constant = .{ .value = .{ .bool = true } } },
        ast.Node{ .constant = .{ .value = .{ .bool = true } } },
    };

    const expr = ast.Node{ .boolop = .{
        .op = .And,
        .values = &values,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .bool = true }, result);
}

test "comptime eval - logical and (false)" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    var values = [_]ast.Node{
        ast.Node{ .constant = .{ .value = .{ .bool = true } } },
        ast.Node{ .constant = .{ .value = .{ .bool = false } } },
    };

    const expr = ast.Node{ .boolop = .{
        .op = .And,
        .values = &values,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .bool = false }, result);
}

test "comptime eval - logical or (true)" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    var values = [_]ast.Node{
        ast.Node{ .constant = .{ .value = .{ .bool = true } } },
        ast.Node{ .constant = .{ .value = .{ .bool = false } } },
    };

    const expr = ast.Node{ .boolop = .{
        .op = .Or,
        .values = &values,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .bool = true }, result);
}

test "comptime eval - logical or (false)" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    var values = [_]ast.Node{
        ast.Node{ .constant = .{ .value = .{ .bool = false } } },
        ast.Node{ .constant = .{ .value = .{ .bool = false } } },
    };

    const expr = ast.Node{ .boolop = .{
        .op = .Or,
        .values = &values,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .bool = false }, result);
}

test "comptime eval - logical not" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const operand = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(operand);
    operand.* = ast.Node{ .constant = .{ .value = .{ .bool = true } } };

    const expr = ast.Node{ .unaryop = .{
        .op = .Not,
        .operand = operand,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .bool = false }, result);
}

test "comptime eval - unary minus" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const operand = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(operand);
    operand.* = ast.Node{ .constant = .{ .value = .{ .int = 42 } } };

    const expr = ast.Node{ .unaryop = .{
        .op = .USub,
        .operand = operand,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .int = -42 }, result);
}

test "comptime eval - unary plus" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const operand = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(operand);
    operand.* = ast.Node{ .constant = .{ .value = .{ .int = 42 } } };

    const expr = ast.Node{ .unaryop = .{
        .op = .UAdd,
        .operand = operand,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .int = 42 }, result);
}

test "comptime eval - cannot evaluate variables" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .name = .{ .id = "x" } };

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .int = 3 } } };

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .Add,
    } };

    const result = evaluator.tryEval(expr);
    try std.testing.expect(result == null);
}

test "comptime eval - division by zero int" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 10 } } };

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .int = 0 } } };

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .Div,
    } };

    const result = evaluator.tryEval(expr);
    try std.testing.expect(result == null);
}

test "comptime eval - division by zero float" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .float = 10.0 } } };

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .float = 0.0 } } };

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .Div,
    } };

    const result = evaluator.tryEval(expr);
    try std.testing.expect(result == null);
}

test "comptime eval - modulo by zero" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 10 } } };

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .int = 0 } } };

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .Mod,
    } };

    const result = evaluator.tryEval(expr);
    try std.testing.expect(result == null);
}

test "comptime eval - bitwise and" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 12 } } }; // 1100

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .int = 10 } } }; // 1010

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .BitAnd,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .int = 8 }, result); // 1000
}

test "comptime eval - bitwise or" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 12 } } }; // 1100

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .int = 10 } } }; // 1010

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .BitOr,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .int = 14 }, result); // 1110
}

test "comptime eval - bitwise xor" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    const left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(left);
    left.* = ast.Node{ .constant = .{ .value = .{ .int = 12 } } }; // 1100

    const right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(right);
    right.* = ast.Node{ .constant = .{ .value = .{ .int = 10 } } }; // 1010

    const expr = ast.Node{ .binop = .{
        .left = left,
        .right = right,
        .op = .BitXor,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .int = 6 }, result); // 0110
}

test "comptime eval - nested expression 2 + 3 * 4" {
    var evaluator = ComptimeEvaluator.init(std.testing.allocator);

    // Build (3 * 4)
    const mul_left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(mul_left);
    mul_left.* = ast.Node{ .constant = .{ .value = .{ .int = 3 } } };

    const mul_right = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(mul_right);
    mul_right.* = ast.Node{ .constant = .{ .value = .{ .int = 4 } } };

    const mul_expr = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(mul_expr);
    mul_expr.* = ast.Node{ .binop = .{
        .left = mul_left,
        .right = mul_right,
        .op = .Mult,
    } };

    // Build 2 + (3 * 4)
    const add_left = try std.testing.allocator.create(ast.Node);
    defer std.testing.allocator.destroy(add_left);
    add_left.* = ast.Node{ .constant = .{ .value = .{ .int = 2 } } };

    const expr = ast.Node{ .binop = .{
        .left = add_left,
        .right = mul_expr,
        .op = .Add,
    } };

    const result = evaluator.tryEval(expr).?;
    try std.testing.expectEqual(ComptimeValue{ .int = 14 }, result);
}
