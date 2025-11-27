//! JSON Benchmark: shared/json vs std.json
//! Run: zig build-exe -OReleaseFast bench.zig -o bench && ./bench

const std = @import("std");
const shared_json = @import("json.zig");

const SMALL_JSON =
    \\{"name":"test","value":42,"active":true}
;

const MEDIUM_JSON =
    \\{"users":[{"id":1,"name":"Alice","email":"alice@example.com"},{"id":2,"name":"Bob","email":"bob@example.com"}],"meta":{"page":1,"total":100}}
;

fn generateLargeJson(allocator: std.mem.Allocator) ![]const u8 {
    var list = std.ArrayList(u8){};
    errdefer list.deinit(allocator);

    try list.appendSlice(allocator, "[");
    for (0..100) |i| {
        if (i > 0) try list.appendSlice(allocator, ",");
        try list.writer(allocator).print(
            \\{{"id":{d},"name":"User{d}","email":"user{d}@example.com","active":true,"score":98.5}}
        , .{ i, i, i });
    }
    try list.appendSlice(allocator, "]");

    return list.toOwnedSlice(allocator);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const large_json = try generateLargeJson(allocator);
    defer allocator.free(large_json);

    std.debug.print("=== JSON Benchmark: shared/json vs std.json ===\n\n", .{});

    std.debug.print("PARSE:\n", .{});
    try benchParse(allocator, "Small (~40B)", SMALL_JSON, 100_000);
    try benchParse(allocator, "Medium (~180B)", MEDIUM_JSON, 50_000);
    try benchParse(allocator, "Large (~10KB)", large_json, 5_000);

    std.debug.print("\nSTRINGIFY:\n", .{});
    try benchStringify(allocator, "Small", SMALL_JSON, 100_000);
    try benchStringify(allocator, "Medium", MEDIUM_JSON, 50_000);
}

fn benchParse(allocator: std.mem.Allocator, name: []const u8, json_data: []const u8, iterations: usize) !void {
    // Warmup
    for (0..100) |_| {
        var parsed = try shared_json.parse(allocator, json_data);
        parsed.deinit(allocator);
    }

    // shared/json
    var shared_time: u64 = 0;
    {
        const start = std.time.nanoTimestamp();
        for (0..iterations) |_| {
            var parsed = try shared_json.parse(allocator, json_data);
            parsed.deinit(allocator);
        }
        shared_time = @intCast(std.time.nanoTimestamp() - start);
    }

    // std.json
    var std_time: u64 = 0;
    {
        const start = std.time.nanoTimestamp();
        for (0..iterations) |_| {
            var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
            parsed.deinit();
        }
        std_time = @intCast(std.time.nanoTimestamp() - start);
    }

    const speedup = @as(f64, @floatFromInt(std_time)) / @as(f64, @floatFromInt(shared_time));
    std.debug.print("  {s:14} shared:{d:6}ms  std:{d:6}ms  {d:.2}x\n", .{
        name,
        shared_time / 1_000_000,
        std_time / 1_000_000,
        speedup,
    });
}

fn benchStringify(allocator: std.mem.Allocator, name: []const u8, json_data: []const u8, iterations: usize) !void {
    var parsed = try shared_json.parse(allocator, json_data);
    defer parsed.deinit(allocator);

    // Warmup
    for (0..100) |_| {
        const str = try shared_json.stringify(allocator, parsed);
        allocator.free(str);
    }

    // shared/json
    var shared_time: u64 = 0;
    {
        const start = std.time.nanoTimestamp();
        for (0..iterations) |_| {
            const str = try shared_json.stringify(allocator, parsed);
            allocator.free(str);
        }
        shared_time = @intCast(std.time.nanoTimestamp() - start);
    }

    // std.json stringify (Zig 0.15 API)
    var std_parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
    defer std_parsed.deinit();

    var std_time: u64 = 0;
    {
        const start = std.time.nanoTimestamp();
        for (0..iterations) |_| {
            var out: std.io.Writer.Allocating = .init(allocator);
            defer out.deinit();
            var ws: std.json.Stringify = .{ .writer = &out.writer };
            try ws.write(std_parsed.value);
        }
        std_time = @intCast(std.time.nanoTimestamp() - start);
    }

    const speedup = @as(f64, @floatFromInt(std_time)) / @as(f64, @floatFromInt(shared_time));
    std.debug.print("  {s:14} shared:{d:6}ms  std:{d:6}ms  {d:.2}x\n", .{
        name,
        shared_time / 1_000_000,
        std_time / 1_000_000,
        speedup,
    });
}
