const std = @import("std");
const mvzr = @import("src/mvzr.zig");
const allocator_helper = @import("src/allocator_helper.zig");

const Benchmark = struct {
    name: []const u8,
    pattern: []const u8,
};

fn loadData(allocator: std.mem.Allocator) ![]u8 {
    const file = try std.fs.cwd().openFile("bench_data.txt", .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 1024 * 1024);
}

fn benchmarkPattern(name: []const u8, pattern: []const u8, text: []const u8, iterations: usize) !void {
    const regex = mvzr.compile(pattern) orelse {
        std.debug.print("{s:<20} COMPILE FAILED\n", .{name});
        return;
    };

    // Warmup
    var warmup: usize = 0;
    while (warmup < 100) : (warmup += 1) {
        var it = regex.iterator(text);
        while (it.next()) |_| {}
    }

    // Count matches
    var match_count: usize = 0;
    var it = regex.iterator(text);
    while (it.next()) |_| {
        match_count += 1;
    }

    // Benchmark
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var iter = regex.iterator(text);
        while (iter.next()) |_| {}
    }
    const end = std.time.nanoTimestamp();

    const elapsed_ns = @as(f64, @floatFromInt(end - start));
    const total_ms = elapsed_ns / 1_000_000.0;
    const avg_us = (elapsed_ns / @as(f64, @floatFromInt(iterations))) / 1000.0;

    std.debug.print("{s:<20} {d:<10} {d:<12.2} {d:<12.2}\n", .{ name, match_count, avg_us, total_ms });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Use fast C allocator on native (29x faster than GPA)
    const allocator = allocator_helper.getBenchmarkAllocator(gpa);

    const text = try loadData(allocator);
    defer allocator.free(text);

    const benchmarks = [_]Benchmark{
        .{ .name = "Email", .pattern = "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]+" },
        .{ .name = "URL", .pattern = "https?://[^ ]+" },
        .{ .name = "Phone", .pattern = "\\(\\d\\d\\d\\)\\s?\\d\\d\\d-\\d\\d\\d\\d" },
        .{ .name = "Digits", .pattern = "\\d+" },
        .{ .name = "Word Boundary", .pattern = "\\b[a-z][a-z][a-z][a-z]+\\b" },
        .{ .name = "Date ISO", .pattern = "\\d\\d\\d\\d-\\d\\d-\\d\\d" },
        .{ .name = "IPv4", .pattern = "\\b\\d+\\.\\d+\\.\\d+\\.\\d+\\b" },
        .{ .name = "Version", .pattern = "v?\\d+\\.\\d+\\.\\d+" },
        .{ .name = "Alphanumeric", .pattern = "[a-z]+\\d+" },
    };

    std.debug.print("======================================================================\n", .{});
    std.debug.print("PyAOT/Zig Regex Benchmark (mvzr)\n", .{});
    std.debug.print("======================================================================\n", .{});
    std.debug.print("{s:<20} {s:<10} {s:<12} {s:<12}\n", .{ "Pattern", "Matches", "Avg (µs)", "Total (ms)" });
    std.debug.print("----------------------------------------------------------------------\n", .{});

    inline for (benchmarks) |bench| {
        try benchmarkPattern(bench.name, bench.pattern, text, 10000);
    }

    std.debug.print("----------------------------------------------------------------------\n", .{});
    std.debug.print("======================================================================\n", .{});
}
