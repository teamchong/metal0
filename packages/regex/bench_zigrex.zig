const std = @import("std");
const Regex = @import("src/zig-regex/regex.zig").Regex;

fn loadData(allocator: std.mem.Allocator) ![]u8 {
    const file = try std.fs.cwd().openFile("bench_data.txt", .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 1024 * 1024);
}

fn benchmarkPattern(allocator: std.mem.Allocator, name: []const u8, pattern: []const u8, text: []const u8, iterations: usize) !void {
    var regex = Regex.compile(allocator, pattern) catch {
        std.debug.print("{s:<20} COMPILE FAILED\n", .{name});
        return;
    };
    defer regex.deinit();

    // Warmup
    var warmup: usize = 0;
    while (warmup < 100) : (warmup += 1) {
        _ = try regex.findAll(allocator, text);
    }

    // Count matches
    const all_matches = try regex.findAll(allocator, text);
    defer allocator.free(all_matches);
    const match_count = all_matches.len;

    // Benchmark
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const matches = try regex.findAll(allocator, text);
        allocator.free(matches);
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
    const allocator = gpa.allocator();

    const text = try loadData(allocator);
    defer allocator.free(text);

    const benchmarks = [_]struct { name: []const u8, pattern: []const u8 }{
        .{ .name = "Email", .pattern = "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]+" },
        .{ .name = "URL", .pattern = "https?://[^ ]+" },
        .{ .name = "Phone", .pattern = "\\(\\d{3}\\)\\s?\\d{3}-\\d{4}" },
        .{ .name = "Digits", .pattern = "\\d+" },
        .{ .name = "Word Boundary", .pattern = "\\b[a-z]{4,}\\b" },
        .{ .name = "Date ISO", .pattern = "\\d{4}-\\d{2}-\\d{2}" },
        .{ .name = "IPv4", .pattern = "\\b\\d+\\.\\d+\\.\\d+\\.\\d+\\b" },
        .{ .name = "Version", .pattern = "v?\\d+\\.\\d+\\.\\d+" },
        .{ .name = "Alphanumeric", .pattern = "[a-z]+\\d+" },
    };

    std.debug.print("======================================================================\n", .{});
    std.debug.print("zig-regex Benchmark (Thompson NFA)\n", .{});
    std.debug.print("======================================================================\n", .{});
    std.debug.print("{s:<20} {s:<10} {s:<12} {s:<12}\n", .{ "Pattern", "Matches", "Avg (µs)", "Total (ms)" });
    std.debug.print("----------------------------------------------------------------------\n", .{});

    inline for (benchmarks) |bench| {
        try benchmarkPattern(allocator, bench.name, bench.pattern, text, 10000);
    }

    std.debug.print("----------------------------------------------------------------------\n", .{});
    std.debug.print("======================================================================\n", .{});
}
