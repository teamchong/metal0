/// tests - Test suite for object_stack module

const std = @import("std");
const ObjectStackMod = @import("ObjectStack.zig");
const ObjectStack = ObjectStackMod.ObjectStack;
const ChunkedObjectStackMod = @import("ChunkedObjectStack.zig");
const ChunkedObjectStack = ChunkedObjectStackMod.ChunkedObjectStack;
const stack_mark = @import("stack_mark.zig");
const markStack = stack_mark.markStack;
const restoreStack = stack_mark.restoreStack;

test "object stack basic" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    try std.testing.expect(stack.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), stack.depth());

    // Use simple integers as mock objects
    var obj1: u32 = 1;
    var obj2: u32 = 2;
    var obj3: u32 = 3;

    try stack.push(&obj1);
    try stack.push(&obj2);
    try stack.push(&obj3);

    try std.testing.expectEqual(@as(usize, 3), stack.depth());
    try std.testing.expect(!stack.isEmpty());

    const top = stack.peek();
    try std.testing.expect(top == &obj3);

    const popped = try stack.pop();
    try std.testing.expect(popped == &obj3);
    try std.testing.expectEqual(@as(usize, 2), stack.depth());
}

test "object stack peek at" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    var obj1: u32 = 1;
    var obj2: u32 = 2;
    var obj3: u32 = 3;

    try stack.push(&obj1);
    try stack.push(&obj2);
    try stack.push(&obj3);

    try std.testing.expect(stack.peekAt(0) == &obj3);
    try std.testing.expect(stack.peekAt(1) == &obj2);
    try std.testing.expect(stack.peekAt(2) == &obj1);
    try std.testing.expect(stack.peekAt(3) == null);
}

test "object stack swap" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    var obj1: u32 = 1;
    var obj2: u32 = 2;

    try stack.push(&obj1);
    try stack.push(&obj2);

    try stack.swap();

    try std.testing.expect(stack.peekAt(0) == &obj1);
    try std.testing.expect(stack.peekAt(1) == &obj2);
}

test "object stack dup" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    var obj: u32 = 42;

    try stack.push(&obj);
    try stack.dup();

    try std.testing.expectEqual(@as(usize, 2), stack.depth());
    try std.testing.expect(stack.peekAt(0) == &obj);
    try std.testing.expect(stack.peekAt(1) == &obj);
}

test "object stack rotate" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    var obj1: u32 = 1;
    var obj2: u32 = 2;
    var obj3: u32 = 3;

    try stack.push(&obj1);
    try stack.push(&obj2);
    try stack.push(&obj3);

    // Stack: [1, 2, 3] (3 on top)
    // Rotate 3: [3, 1, 2]
    try stack.rotate(3);

    try std.testing.expect(stack.peekAt(0) == &obj2);
    try std.testing.expect(stack.peekAt(1) == &obj1);
    try std.testing.expect(stack.peekAt(2) == &obj3);
}

test "object stack clear" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    var obj: u32 = 42;

    try stack.push(&obj);
    try stack.push(&obj);

    stack.clear();

    try std.testing.expect(stack.isEmpty());
    try std.testing.expectEqual(@as(usize, 0), stack.depth());
}

test "object stack underflow" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    try std.testing.expectError(error.StackUnderflow, stack.pop());
}

test "stack mark and restore" {
    var stack = try ObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    var obj1: u32 = 1;
    var obj2: u32 = 2;

    try stack.push(&obj1);

    const mark = markStack(&stack);

    try stack.push(&obj2);
    try std.testing.expectEqual(@as(usize, 2), stack.depth());

    restoreStack(&stack, mark);
    try std.testing.expectEqual(@as(usize, 1), stack.depth());
}

test "chunked stack basic" {
    var stack = try ChunkedObjectStack.init(std.testing.allocator);
    defer stack.deinit();

    var obj: u32 = 42;

    // Push more than one chunk
    for (0..100) |_| {
        try stack.push(&obj);
    }

    try std.testing.expectEqual(@as(usize, 100), stack.depth());

    // Pop all
    for (0..100) |_| {
        _ = try stack.pop();
    }

    try std.testing.expectEqual(@as(usize, 0), stack.depth());
}
