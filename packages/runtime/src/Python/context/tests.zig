/// Tests for context module

const std = @import("std");
const Context = @import("context_impl.zig").Context;
const ContextVar = @import("context_var.zig").ContextVar;
const global_state = @import("global_state.zig");

test "context var basic" {
    const allocator = std.testing.allocator;

    // Create context and enter it
    const ctx = try Context.create(allocator);
    defer ctx.destroy();

    try ctx.enter();
    defer ctx.exit() catch {};

    // Create context var
    const cv = try ContextVar.create(allocator, "test_var", null);
    defer cv.destroy();

    // Initially no value
    const val1 = try cv.get();
    try std.testing.expect(val1 == null);
}

test "context var with default" {
    const allocator = std.testing.allocator;

    const ctx = try Context.create(allocator);
    defer ctx.destroy();

    try ctx.enter();
    defer ctx.exit() catch {};

    var default_val: i32 = 42;
    const cv = try ContextVar.create(allocator, "with_default", @ptrCast(&default_val));
    defer cv.destroy();

    const val = try cv.get();
    try std.testing.expect(val != null);
    const int_ptr: *i32 = @ptrCast(@alignCast(val.?));
    try std.testing.expectEqual(@as(i32, 42), int_ptr.*);
}

test "context enter/exit" {
    const allocator = std.testing.allocator;

    const ctx = try Context.create(allocator);
    defer ctx.destroy();

    try std.testing.expect(!ctx.isEntered());

    try ctx.enter();
    try std.testing.expect(ctx.isEntered());
    try std.testing.expect(global_state.getCurrentContext() == ctx);

    try ctx.exit();
    try std.testing.expect(!ctx.isEntered());
    try std.testing.expect(global_state.getCurrentContext() == null);
}

test "context nested" {
    const allocator = std.testing.allocator;

    const ctx1 = try Context.create(allocator);
    defer ctx1.destroy();

    const ctx2 = try Context.create(allocator);
    defer ctx2.destroy();

    try ctx1.enter();
    try std.testing.expect(global_state.getCurrentContext() == ctx1);

    try ctx2.enter();
    try std.testing.expect(global_state.getCurrentContext() == ctx2);

    try ctx2.exit();
    try std.testing.expect(global_state.getCurrentContext() == ctx1);

    try ctx1.exit();
    try std.testing.expect(global_state.getCurrentContext() == null);
}

test "context copy" {
    const allocator = std.testing.allocator;

    const ctx1 = try Context.create(allocator);
    defer ctx1.destroy();

    const ctx2 = try Context.copy(allocator, ctx1);
    defer ctx2.destroy();

    // Both should work independently
    try std.testing.expect(!ctx1.isEntered());
    try std.testing.expect(!ctx2.isEntered());
}

test "context watcher" {
    const callback = struct {
        fn cb(_: global_state.ContextEvent, _: ?*Context) i32 {
            // Can't modify outer scope easily, but test compiles
            return 0;
        }
    }.cb;

    const watcher_id = try global_state.addWatcher(callback);
    try std.testing.expect(watcher_id >= 0);

    try global_state.clearWatcher(watcher_id);
}
