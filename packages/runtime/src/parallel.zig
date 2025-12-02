/// Parallel execution utilities for metal0
/// Auto-parallelization of pure functions across multiple cores
const std = @import("std");

/// Parallel for loop - splits work across available cores
/// Only safe for pure functions (no side effects)
pub fn parallelFor(
    comptime T: type,
    items: []const T,
    comptime func: fn (T) T,
    allocator: std.mem.Allocator,
) ![]T {
    const result = try allocator.alloc(T, items.len);
    errdefer allocator.free(result);

    const num_threads = try std.Thread.getCpuCount();
    const chunk_size = (items.len + num_threads - 1) / num_threads;

    if (items.len < 64 or num_threads == 1) {
        // Small array or single core - just run sequentially
        for (items, 0..) |item, i| {
            result[i] = func(item);
        }
        return result;
    }

    var threads = try allocator.alloc(std.Thread, num_threads);
    defer allocator.free(threads);

    const Context = struct {
        items: []const T,
        result: []T,
        func: *const fn (T) T,
        start: usize,
        end: usize,
    };

    const worker = struct {
        fn run(ctx: *Context) void {
            for (ctx.start..ctx.end) |i| {
                if (i < ctx.items.len) {
                    ctx.result[i] = ctx.func(ctx.items[i]);
                }
            }
        }
    }.run;

    var contexts = try allocator.alloc(Context, num_threads);
    defer allocator.free(contexts);

    var spawned: usize = 0;
    errdefer {
        for (threads[0..spawned]) |t| t.join();
    }

    for (0..num_threads) |i| {
        const start = i * chunk_size;
        const end = @min(start + chunk_size, items.len);
        if (start >= items.len) break;

        contexts[i] = Context{
            .items = items,
            .result = result,
            .func = &func,
            .start = start,
            .end = end,
        };

        threads[i] = try std.Thread.spawn(.{}, worker, .{&contexts[i]});
        spawned += 1;
    }

    // Wait for all threads
    for (threads[0..spawned]) |t| t.join();

    return result;
}

/// Parallel map for i64 arrays (common case)
pub fn parallelMapI64(
    items: []const i64,
    comptime op: ParallelOp,
    constant: i64,
    allocator: std.mem.Allocator,
) ![]i64 {
    const result = try allocator.alloc(i64, items.len);
    errdefer allocator.free(result);

    const num_threads = try std.Thread.getCpuCount();

    if (items.len < 256 or num_threads == 1) {
        // Small array - sequential
        for (items, 0..) |item, i| {
            result[i] = applyOp(op, item, constant);
        }
        return result;
    }

    const chunk_size = (items.len + num_threads - 1) / num_threads;
    var threads = try allocator.alloc(std.Thread, num_threads);
    defer allocator.free(threads);

    const Context = struct {
        items: []const i64,
        result: []i64,
        op: ParallelOp,
        constant: i64,
        start: usize,
        end: usize,
    };

    const worker = struct {
        fn run(ctx: *Context) void {
            for (ctx.start..ctx.end) |i| {
                if (i < ctx.items.len) {
                    ctx.result[i] = applyOp(ctx.op, ctx.items[i], ctx.constant);
                }
            }
        }
    }.run;

    var contexts = try allocator.alloc(Context, num_threads);
    defer allocator.free(contexts);

    var spawned: usize = 0;
    errdefer {
        for (threads[0..spawned]) |t| t.join();
    }

    for (0..num_threads) |i| {
        const start = i * chunk_size;
        const end = @min(start + chunk_size, items.len);
        if (start >= items.len) break;

        contexts[i] = Context{
            .items = items,
            .result = result,
            .op = op,
            .constant = constant,
            .start = start,
            .end = end,
        };

        threads[i] = try std.Thread.spawn(.{}, worker, .{&contexts[i]});
        spawned += 1;
    }

    for (threads[0..spawned]) |t| t.join();

    return result;
}

pub const ParallelOp = enum {
    add,
    sub,
    mul,
    div,
    neg,
    square,
    bit_and,
    bit_or,
    bit_xor,
};

fn applyOp(op: ParallelOp, x: i64, c: i64) i64 {
    return switch (op) {
        .add => x +% c,
        .sub => x -% c,
        .mul => x *% c,
        .div => if (c != 0) @divTrunc(x, c) else 0,
        .neg => -%x,
        .square => x *% x,
        .bit_and => x & c,
        .bit_or => x | c,
        .bit_xor => x ^ c,
    };
}

/// Parallel range map - generates and maps in parallel
/// [op(x) for x in range(start, end)]
pub fn parallelRangeMap(
    start: i64,
    end: i64,
    comptime op: ParallelOp,
    constant: i64,
    allocator: std.mem.Allocator,
) ![]i64 {
    if (end <= start) return try allocator.alloc(i64, 0);

    const count: usize = @intCast(end - start);
    const result = try allocator.alloc(i64, count);
    errdefer allocator.free(result);

    const num_threads = try std.Thread.getCpuCount();

    if (count < 1024 or num_threads == 1) {
        // Small range - sequential
        for (0..count) |i| {
            const x = start + @as(i64, @intCast(i));
            result[i] = applyOp(op, x, constant);
        }
        return result;
    }

    const chunk_size = (count + num_threads - 1) / num_threads;
    var threads = try allocator.alloc(std.Thread, num_threads);
    defer allocator.free(threads);

    const Context = struct {
        result: []i64,
        op: ParallelOp,
        constant: i64,
        range_start: i64,
        chunk_start: usize,
        chunk_end: usize,
    };

    const worker = struct {
        fn run(ctx: *Context) void {
            for (ctx.chunk_start..ctx.chunk_end) |i| {
                if (i < ctx.result.len) {
                    const x = ctx.range_start + @as(i64, @intCast(i));
                    ctx.result[i] = applyOp(ctx.op, x, ctx.constant);
                }
            }
        }
    }.run;

    var contexts = try allocator.alloc(Context, num_threads);
    defer allocator.free(contexts);

    var spawned: usize = 0;
    errdefer {
        for (threads[0..spawned]) |t| t.join();
    }

    for (0..num_threads) |i| {
        const chunk_start = i * chunk_size;
        const chunk_end = @min(chunk_start + chunk_size, count);
        if (chunk_start >= count) break;

        contexts[i] = Context{
            .result = result,
            .op = op,
            .constant = constant,
            .range_start = start,
            .chunk_start = chunk_start,
            .chunk_end = chunk_end,
        };

        threads[i] = try std.Thread.spawn(.{}, worker, .{&contexts[i]});
        spawned += 1;
    }

    for (threads[0..spawned]) |t| t.join();

    return result;
}

test "parallelRangeMap basic" {
    const allocator = std.testing.allocator;

    // [x * 2 for x in range(10)]
    const result = try parallelRangeMap(0, 10, .mul, 2, allocator);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 10), result.len);
    try std.testing.expectEqual(@as(i64, 0), result[0]); // 0 * 2
    try std.testing.expectEqual(@as(i64, 10), result[5]); // 5 * 2
    try std.testing.expectEqual(@as(i64, 18), result[9]); // 9 * 2
}

test "parallelMapI64 basic" {
    const allocator = std.testing.allocator;

    const items = [_]i64{ 1, 2, 3, 4, 5 };
    const result = try parallelMapI64(&items, .mul, 3, allocator);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(i64, 3), result[0]);
    try std.testing.expectEqual(@as(i64, 6), result[1]);
    try std.testing.expectEqual(@as(i64, 15), result[4]);
}
