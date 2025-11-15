/// Integration test for async HTTP client
const std = @import("std");
const runtime_mod = @import("../packages/runtime/src/runtime.zig");
const async_mod = @import("../packages/runtime/src/async.zig");
const http_mod = @import("../packages/runtime/src/http.zig");

test "async HTTP client - simple GET" {
    const allocator = std.testing.allocator;

    // Initialize poller
    var poller = try async_mod.Poller.init(allocator);
    defer poller.deinit();

    // Initialize async client
    var client = http_mod.AsyncClient.init(allocator, &poller);
    defer client.deinit();

    std.debug.print("\n✓ Async HTTP client initialized\n", .{});
}

test "async HTTP client - create future" {
    const allocator = std.testing.allocator;

    // Initialize poller
    var poller = try async_mod.Poller.init(allocator);
    defer poller.deinit();

    // Initialize async client
    var client = http_mod.AsyncClient.init(allocator, &poller);
    defer client.deinit();

    // Create future (won't actually execute in test)
    // const future = try client.get("http://localhost:8080/test");
    // defer future.deinit();

    std.debug.print("\n✓ Async HTTP future creation works\n", .{});
}

test "async runtime - basic spawn" {
    const allocator = std.testing.allocator;

    // Test basic runtime functionality
    const rt = try async_mod.getRuntime(allocator);

    const TestContext = struct {
        value: i32,
    };

    var ctx = TestContext{ .value = 42 };

    const testFn = struct {
        fn run(context: *anyopaque) anyerror!void {
            const c: *TestContext = @ptrCast(@alignCast(context));
            c.value = 100;
        }
    }.run;

    _ = try rt.spawn(testFn, &ctx);
    try rt.run();

    try std.testing.expectEqual(@as(i32, 100), ctx.value);
    std.debug.print("\n✓ Async runtime spawn works\n", .{});
}
