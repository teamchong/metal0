/// Tests for AST Preprocessing
/// Unit tests for all submodules

const std = @import("std");
const control_flow = @import("control_flow.zig");
const state = @import("state.zig");
const constant_folding = @import("constant_folding.zig");

test "context stack operations" {
    const allocator = std.testing.allocator;

    var stack = control_flow.ContextStack.init(allocator);
    defer stack.deinit();

    try std.testing.expect(stack.isEmpty());
    try std.testing.expect(stack.top() == null);

    try stack.push(.{ .in_finally = true, .in_funcdef = false, .in_loop = false });
    try std.testing.expect(!stack.isEmpty());
    try std.testing.expect(stack.top().?.in_finally);

    stack.pop();
    try std.testing.expect(stack.isEmpty());
}

test "preprocess state control flow" {
    const allocator = std.testing.allocator;

    var preprocess_state = state.PreprocessState.init(allocator, "test.py");
    defer preprocess_state.deinit();

    try preprocess_state.enterFinally();
    try preprocess_state.beforeReturn(10, 0);
    try std.testing.expectEqual(@as(usize, 1), preprocess_state.warningCount());

    preprocess_state.exitFinally();
}

test "constant folding - binary ops" {
    const left = constant_folding.ConstValue{ .int_val = 10 };
    const right = constant_folding.ConstValue{ .int_val = 5 };

    const add_result = constant_folding.foldBinaryOp(.add, left, right);
    try std.testing.expect(add_result != null);
    try std.testing.expectEqual(@as(i64, 15), add_result.?.int_val);

    const sub_result = constant_folding.foldBinaryOp(.sub, left, right);
    try std.testing.expect(sub_result != null);
    try std.testing.expectEqual(@as(i64, 5), sub_result.?.int_val);

    const mult_result = constant_folding.foldBinaryOp(.mult, left, right);
    try std.testing.expect(mult_result != null);
    try std.testing.expectEqual(@as(i64, 50), mult_result.?.int_val);
}

test "constant folding - unary ops" {
    const int_val = constant_folding.ConstValue{ .int_val = 5 };
    const bool_val = constant_folding.ConstValue{ .bool_val = true };

    const neg_result = constant_folding.foldUnaryOp(.usub, int_val);
    try std.testing.expect(neg_result != null);
    try std.testing.expectEqual(@as(i64, -5), neg_result.?.int_val);

    const not_result = constant_folding.foldUnaryOp(.not_op, bool_val);
    try std.testing.expect(not_result != null);
    try std.testing.expect(!not_result.?.bool_val);
}

test "constant truthiness" {
    const none_val = constant_folding.ConstValue{ .none = {} };
    const true_val = constant_folding.ConstValue{ .bool_val = true };
    const zero_val = constant_folding.ConstValue{ .int_val = 0 };
    const one_val = constant_folding.ConstValue{ .int_val = 1 };
    const empty_str = constant_folding.ConstValue{ .str_val = "" };
    const non_empty = constant_folding.ConstValue{ .str_val = "hello" };

    try std.testing.expect(!none_val.isTruthy());
    try std.testing.expect(true_val.isTruthy());
    try std.testing.expect(!zero_val.isTruthy());
    try std.testing.expect(one_val.isTruthy());
    try std.testing.expect(!empty_str.isTruthy());
    try std.testing.expect(non_empty.isTruthy());
}

test "division by zero" {
    const left = constant_folding.ConstValue{ .int_val = 10 };
    const right = constant_folding.ConstValue{ .int_val = 0 };

    const result = constant_folding.foldBinaryOp(.floor_div, left, right);
    try std.testing.expect(result == null);

    const mod_result = constant_folding.foldBinaryOp(.mod, left, right);
    try std.testing.expect(mod_result == null);
}
