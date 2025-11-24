const std = @import("std");
const runtime = @import("src/runtime.zig");
const ast_executor = runtime.ast_executor;
const Node = ast_executor.Node;

test "execute constant int" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const node = Node{ .constant = .{ .value = .{ .int = 42 } } };
    const result = try ast_executor.execute(allocator, &node);
    defer runtime.decref(result, allocator);

    try std.testing.expectEqual(runtime.PyObject.TypeId.int, result.type_id);
    const PyInt = @import("src/pyint.zig").PyInt;
    try std.testing.expectEqual(@as(i64, 42), PyInt.getValue(result));
}

test "execute binop add" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create "1 + 2"
    const left_node = try allocator.create(Node);
    defer allocator.destroy(left_node);
    left_node.* = Node{ .constant = .{ .value = .{ .int = 1 } } };

    const right_node = try allocator.create(Node);
    defer allocator.destroy(right_node);
    right_node.* = Node{ .constant = .{ .value = .{ .int = 2 } } };

    const binop_node = Node{
        .binop = .{
            .left = left_node,
            .op = .Add,
            .right = right_node,
        },
    };

    const result = try ast_executor.execute(allocator, &binop_node);
    defer runtime.decref(result, allocator);

    const PyInt = @import("src/pyint.zig").PyInt;
    try std.testing.expectEqual(@as(i64, 3), PyInt.getValue(result));
}
