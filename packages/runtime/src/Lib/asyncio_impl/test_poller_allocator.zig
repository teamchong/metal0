const std = @import("std");
const testing = std.testing;

// Import components to test
const common = @import("poller/common.zig");
const Poller = common.Poller;
const Task = @import("task.zig").Task;
const TaskArena = @import("allocator/arena.zig").TaskArena;
const ArenaPool = @import("allocator/arena.zig").ArenaPool;
const Pool = @import("allocator/pool.zig").Pool;
const DynamicPool = @import("allocator/pool.zig").DynamicPool;
const ThreadLocalAllocator = @import("allocator/threadlocal.zig").ThreadLocalAllocator;
const TLAllocatorRegistry = @import("allocator/threadlocal.zig").TLAllocatorRegistry;

// Dummy task function for testing
fn dummyTaskFunc(_: *anyopaque) anyerror!void {}

// ============================================================================
// POLLER TESTS
// ============================================================================

test "Poller init and deinit" {
    var poller = try Poller.init(testing.allocator);
    defer poller.deinit();

    // Basic check that it initialized
    try testing.expect(true);
}

test "Poller register and unregister fd" {
    var poller = try Poller.init(testing.allocator);
    defer poller.deinit();

    // Create a pipe for testing
    var fds: [2]std.posix.fd_t = undefined;
    try std.posix.pipe(&fds);
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    // Create dummy task
    var task_data: u8 = 0;
    var task = Task.init(1, dummyTaskFunc, &task_data);

    // Register for read events
    try poller.register(fds[0], common.READABLE, &task);

    const stats1 = poller.getStats();
    try testing.expectEqual(@as(u64, 1), stats1.total_registered);

    // Unregister
    try poller.unregister(fds[0]);

    const stats2 = poller.getStats();
    try testing.expectEqual(@as(u64, 1), stats2.total_unregistered);
}

test "Poller wait with timeout" {
    var poller = try Poller.init(testing.allocator);
    defer poller.deinit();

    // Wait with 1ms timeout (should return immediately with no events)
    const events = try poller.wait(1);
    try testing.expectEqual(@as(usize, 0), events.len);

    const stats = poller.getStats();
    try testing.expectEqual(@as(u64, 1), stats.total_waits);
    try testing.expectEqual(@as(u64, 1), stats.total_timeouts);
}

test "Poller detect write ready" {
    var poller = try Poller.init(testing.allocator);
    defer poller.deinit();

    // Create a pipe
    var fds: [2]std.posix.fd_t = undefined;
    try std.posix.pipe(&fds);
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    // Create dummy task
    var task_data: u8 = 0;
    var task = Task.init(1, dummyTaskFunc, &task_data);

    // Register for write events (pipe write end is always writable)
    try poller.register(fds[1], common.WRITABLE, &task);

    // Wait should return immediately with write event
    const events = try poller.wait(10);
    try testing.expect(events.len > 0);
    try testing.expect(events[0].events & common.WRITABLE != 0);
    try testing.expectEqual(fds[1], events[0].fd);
    try testing.expectEqual(&task, events[0].task);
}

test "Poller detect read ready" {
    var poller = try Poller.init(testing.allocator);
    defer poller.deinit();

    // Create a pipe
    var fds: [2]std.posix.fd_t = undefined;
    try std.posix.pipe(&fds);
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    // Create dummy task
    var task_data: u8 = 0;
    var task = Task.init(1, dummyTaskFunc, &task_data);

    // Register for read events
    try poller.register(fds[0], common.READABLE, &task);

    // Write data to pipe
    const msg = "test";
    _ = try std.posix.write(fds[1], msg);

    // Wait should return with read event
    const events = try poller.wait(10);
    try testing.expect(events.len > 0);
    try testing.expect(events[0].events & common.READABLE != 0);
    try testing.expectEqual(fds[0], events[0].fd);
}

test "Poller multiple events" {
    var poller = try Poller.init(testing.allocator);
    defer poller.deinit();

    // Create two pipes
    var fds1: [2]std.posix.fd_t = undefined;
    var fds2: [2]std.posix.fd_t = undefined;
    try std.posix.pipe(&fds1);
    defer std.posix.close(fds1[0]);
    defer std.posix.close(fds1[1]);
    try std.posix.pipe(&fds2);
    defer std.posix.close(fds2[0]);
    defer std.posix.close(fds2[1]);

    var task_data1: u8 = 0;
    var task_data2: u8 = 0;
    var task1 = Task.init(1, dummyTaskFunc, &task_data1);
    var task2 = Task.init(2, dummyTaskFunc, &task_data2);

    // Register both for write (both should be ready)
    try poller.register(fds1[1], common.WRITABLE, &task1);
    try poller.register(fds2[1], common.WRITABLE, &task2);

    // Should get both events
    const events = try poller.wait(10);
    try testing.expect(events.len == 2);
}

test "Poller statistics tracking" {
    var poller = try Poller.init(testing.allocator);
    defer poller.deinit();

    var fds: [2]std.posix.fd_t = undefined;
    try std.posix.pipe(&fds);
    defer std.posix.close(fds[0]);
    defer std.posix.close(fds[1]);

    var task = Task.init(1, dummyTaskFunc, @ptrCast(&poller));

    try poller.register(fds[1], common.WRITABLE, &task);
    _ = try poller.wait(1);

    const stats = poller.getStats();
    try testing.expectEqual(@as(u64, 1), stats.total_registered);
    try testing.expectEqual(@as(u64, 1), stats.total_waits);
    try testing.expect(stats.total_events > 0);

    poller.resetStats();
    const reset_stats = poller.getStats();
    try testing.expectEqual(@as(u64, 0), reset_stats.total_registered);
}

test "Event mask to string conversion" {
    const none = try common.eventMaskToString(testing.allocator, 0);
    defer testing.allocator.free(none);
    try testing.expectEqualStrings("NONE", none);

    const readable = try common.eventMaskToString(testing.allocator, common.READABLE);
    defer testing.allocator.free(readable);
    try testing.expectEqualStrings("READABLE", readable);

    const rw = try common.eventMaskToString(testing.allocator, common.READABLE | common.WRITABLE);
    defer testing.allocator.free(rw);
    try testing.expectEqualStrings("READABLE | WRITABLE", rw);
}

// ============================================================================
// ARENA ALLOCATOR TESTS
// ============================================================================

test "TaskArena init and deinit" {
    var task_data: u8 = 0;
    var task = Task.init(1, dummyTaskFunc, &task_data);
    var arena = TaskArena.init(testing.allocator, &task);
    defer arena.deinit();

    try testing.expectEqual(&task, arena.task);
    try testing.expectEqual(@as(usize, 0), arena.total_allocated);
}

test "TaskArena allocation" {
    var task_data: u8 = 0;
    var task = Task.init(1, dummyTaskFunc, &task_data);
    var arena = TaskArena.init(testing.allocator, &task);
    defer arena.deinit();

    // Allocate some memory
    const data1 = try arena.allocator().alloc(u8, 100);
    const data2 = try arena.allocator().alloc(u8, 200);

    // Write to ensure it works
    data1[0] = 42;
    data2[0] = 84;

    try testing.expectEqual(@as(u8, 42), data1[0]);
    try testing.expectEqual(@as(u8, 84), data2[0]);
}

test "TaskArena reset retains capacity" {
    var task_data: u8 = 0;
    var task = Task.init(1, dummyTaskFunc, &task_data);
    var arena = TaskArena.init(testing.allocator, &task);
    defer arena.deinit();

    // Allocate
    _ = try arena.allocator().alloc(u8, 1000);

    // Reset
    arena.reset();

    try testing.expectEqual(@as(usize, 0), arena.total_allocated);

    // Can allocate again
    const data = try arena.allocator().alloc(u8, 500);
    data[0] = 1;
    try testing.expectEqual(@as(u8, 1), data[0]);
}

test "ArenaPool acquire and release" {
    var pool = ArenaPool.init(testing.allocator);
    defer pool.deinit();

    var task_data1: u8 = 0;
    var task_data2: u8 = 0;
    var task1 = Task.init(1, dummyTaskFunc, &task_data1);
    var task2 = Task.init(2, dummyTaskFunc, &task_data2);

    // Acquire first arena (should create new)
    const arena1 = try pool.acquire(&task1);
    try testing.expectEqual(@as(u64, 1), pool.total_created);
    try testing.expectEqual(@as(u64, 0), pool.total_reused);

    // Return it
    try pool.release(arena1);
    try testing.expectEqual(@as(u64, 1), pool.total_returned);

    // Acquire again (should reuse)
    const arena2 = try pool.acquire(&task2);
    try testing.expectEqual(@as(u64, 1), pool.total_created);
    try testing.expectEqual(@as(u64, 1), pool.total_reused);
    try testing.expectEqual(arena1, arena2);

    // Return it
    try pool.release(arena2);
}

test "ArenaPool statistics" {
    var pool = ArenaPool.init(testing.allocator);
    defer pool.deinit();

    var task_data: u8 = 0;
    var task = Task.init(1, dummyTaskFunc, &task_data);

    const arena1 = try pool.acquire(&task);
    const arena2 = try pool.acquire(&task);

    try pool.release(arena1);
    try pool.release(arena2);

    const stats = pool.getStats();
    try testing.expectEqual(@as(usize, 2), stats.available);
    try testing.expectEqual(@as(u64, 2), stats.total_created);
    try testing.expectEqual(@as(u64, 2), stats.total_returned);
}

// ============================================================================
// OBJECT POOL TESTS
// ============================================================================

test "Pool basic operations" {
    const IntPool = Pool(u32, 10);
    var pool = IntPool.init();

    try testing.expectEqual(@as(usize, 10), pool.available());

    // Acquire
    const obj1 = pool.acquire().?;
    obj1.* = 42;
    try testing.expectEqual(@as(u32, 42), obj1.*);
    try testing.expectEqual(@as(usize, 9), pool.available());

    // Release
    pool.release(obj1);
    try testing.expectEqual(@as(usize, 10), pool.available());
}

test "Pool exhaustion" {
    const IntPool = Pool(u32, 3);
    var pool = IntPool.init();

    // Acquire all
    const obj1 = pool.acquire().?;
    const obj2 = pool.acquire().?;
    const obj3 = pool.acquire().?;

    // Pool exhausted
    const obj4 = pool.acquire();
    try testing.expect(obj4 == null);

    // Release one
    pool.release(obj1);

    // Can acquire again
    const obj5 = pool.acquire().?;
    obj5.* = 100;

    pool.release(obj2);
    pool.release(obj3);
    pool.release(obj5);
}

test "Pool statistics" {
    const IntPool = Pool(u32, 10);
    var pool = IntPool.init();

    const obj1 = pool.acquire().?;
    const obj2 = pool.acquire().?;
    const obj3 = pool.acquire().?;

    const stats = pool.stats();
    try testing.expectEqual(@as(usize, 3), stats.in_use);
    try testing.expectEqual(@as(u64, 3), stats.total_acquired);

    pool.release(obj1);
    pool.release(obj2);
    pool.release(obj3);
}

test "DynamicPool overflow" {
    const IntPool = DynamicPool(u32, 3);
    var pool = IntPool.init(testing.allocator);
    defer pool.deinit();

    // Acquire from static pool
    const obj1 = try pool.acquire();
    const obj2 = try pool.acquire();
    const obj3 = try pool.acquire();

    // Next should overflow
    const obj4 = try pool.acquire();
    const obj5 = try pool.acquire();

    const stats = pool.stats();
    try testing.expectEqual(@as(usize, 3), stats.static_in_use);
    try testing.expectEqual(@as(u64, 2), stats.total_overflow);

    try pool.release(obj1);
    try pool.release(obj2);
    try pool.release(obj3);
    try pool.release(obj4);
    try pool.release(obj5);
}

// ============================================================================
// THREAD-LOCAL ALLOCATOR TESTS
// ============================================================================

test "ThreadLocalAllocator basic" {
    var tl_alloc = ThreadLocalAllocator.init(testing.allocator);
    defer tl_alloc.deinit();

    try testing.expect(tl_alloc.isOwner());

    const data = try tl_alloc.allocator().alloc(u8, 100);
    data[0] = 42;
    try testing.expectEqual(@as(u8, 42), data[0]);
}

test "ThreadLocalAllocator reset" {
    var tl_alloc = ThreadLocalAllocator.init(testing.allocator);
    defer tl_alloc.deinit();

    _ = try tl_alloc.allocator().alloc(u8, 1000);
    tl_alloc.reset();

    try testing.expectEqual(@as(usize, 0), tl_alloc.total_allocated);
}

test "TLAllocatorRegistry basic" {
    var registry = TLAllocatorRegistry.init(testing.allocator);
    defer registry.deinit();

    // Get allocator for current thread
    const alloc1 = try registry.getOrCreate();
    try testing.expect(alloc1.isOwner());

    // Get again (should return same instance)
    const alloc2 = try registry.getOrCreate();
    try testing.expectEqual(alloc1, alloc2);

    try testing.expectEqual(@as(usize, 1), registry.threadCount());
}

test "TLAllocatorRegistry multi-thread" {
    var registry = TLAllocatorRegistry.init(testing.allocator);
    defer registry.deinit();

    const ThreadContext = struct {
        registry: *TLAllocatorRegistry,
        success: *std.atomic.Value(bool),
    };

    var success = std.atomic.Value(bool).init(true);

    const threadFunc = struct {
        fn run(ctx: *ThreadContext) void {
            const alloc = ctx.registry.getOrCreate() catch {
                ctx.success.store(false, .release);
                return;
            };

            if (!alloc.isOwner()) {
                ctx.success.store(false, .release);
                return;
            }

            const data = alloc.allocator().alloc(u8, 100) catch {
                ctx.success.store(false, .release);
                return;
            };

            data[0] = 42;
            if (data[0] != 42) {
                ctx.success.store(false, .release);
            }
        }
    }.run;

    var ctx = ThreadContext{
        .registry = &registry,
        .success = &success,
    };

    const thread = try std.Thread.spawn(.{}, threadFunc, .{&ctx});
    thread.join();

    try testing.expect(success.load(.acquire));
    try testing.expectEqual(@as(usize, 2), registry.threadCount());
}
