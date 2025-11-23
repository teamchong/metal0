/// SIMD Benchmark - Compare scalar vs SIMD performance
const std = @import("std");
const simd = @import("simd/dispatch.zig");
const scalar = @import("simd/scalar.zig");

const MB = 1024 * 1024;

fn benchmark(comptime name: []const u8, comptime func: anytype, data: []const u8, iterations: usize) !void {
    // Warmup
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        _ = func(data, 0);
    }

    // Benchmark
    const start = std.time.milliTimestamp();
    i = 0;
    while (i < iterations) : (i += 1) {
        _ = func(data, 0);
    }
    const end = std.time.milliTimestamp();

    const elapsed = @as(f64, @floatFromInt(end - start)) / 1000.0; // Convert to seconds
    const bytes_processed = data.len * iterations;
    const mb_per_sec = @as(f64, @floatFromInt(bytes_processed)) / elapsed / MB;

    std.debug.print("{s}:\n", .{name});
    std.debug.print("  Data size: {} bytes\n", .{data.len});
    std.debug.print("  Iterations: {}\n", .{iterations});
    std.debug.print("  Time: {d:.3}s\n", .{elapsed});
    std.debug.print("  Speed: {d:.1} MB/s\n", .{mb_per_sec});
    std.debug.print("  Speedup: {d:.1}x\n\n", .{mb_per_sec / 100.0});
}

fn generateJsonData(allocator: std.mem.Allocator, size: usize) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);

    var writer = buf.writer(allocator);

    try writer.writeAll("{\"items\":[");

    var i: usize = 0;
    while (i < size / 100) : (i += 1) {
        if (i > 0) try writer.writeAll(",");
        try writer.print("{{\"id\":{},\"name\":\"item_{}\",\"value\":{d}}}", .{ i, i, @as(f64, @floatFromInt(i)) * 1.5 });
    }

    try writer.writeAll("]}");

    return buf.toOwnedSlice(allocator);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("======================================================================\n", .{});
    std.debug.print("SIMD Benchmark - JSON String Scanning\n", .{});
    std.debug.print("=" ** 70 ++ "\n\n", .{});

    std.debug.print("SIMD Implementation: {s}\n\n", .{simd.getSimdInfo()});

    // Generate test data
    const data = try generateJsonData(allocator, 100_000);
    defer allocator.free(data);

    std.debug.print("Test 1: Find Special Characters\n", .{});
    std.debug.print("----------------------------------------------------------------------\n", .{});
    try benchmark("Scalar findSpecialChar", scalar.findSpecialChar, data, 1000);
    try benchmark("SIMD findSpecialChar", simd.findSpecialChar, data, 1000);

    std.debug.print("\nTest 2: Count Matching Characters\n", .{});
    std.debug.print("----------------------------------------------------------------------\n", .{});

    const test_data_count = "aaa,bbb,ccc,ddd,eee,fff,ggg,hhh,iii,jjj" ** 1000;

    var count_scalar: usize = 0;
    const start_scalar = std.time.milliTimestamp();
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        count_scalar = scalar.countMatching(test_data_count, ',');
    }
    const end_scalar = std.time.milliTimestamp();
    const elapsed_scalar = @as(f64, @floatFromInt(end_scalar - start_scalar)) / 1000.0;
    const mb_scalar = @as(f64, @floatFromInt(test_data_count.len * 1000)) / elapsed_scalar / MB;

    std.debug.print("Scalar countMatching:\n", .{});
    std.debug.print("  Speed: {d:.1} MB/s\n", .{mb_scalar});
    std.debug.print("  Result: {} commas\n\n", .{count_scalar});

    var count_simd: usize = 0;
    const start_simd = std.time.milliTimestamp();
    i = 0;
    while (i < 1000) : (i += 1) {
        count_simd = simd.countMatching(test_data_count, ',');
    }
    const end_simd = std.time.milliTimestamp();
    const elapsed_simd = @as(f64, @floatFromInt(end_simd - start_simd)) / 1000.0;
    const mb_simd = @as(f64, @floatFromInt(test_data_count.len * 1000)) / elapsed_simd / MB;

    std.debug.print("SIMD countMatching:\n", .{});
    std.debug.print("  Speed: {d:.1} MB/s\n", .{mb_simd});
    std.debug.print("  Result: {} commas\n", .{count_simd});
    std.debug.print("  Speedup: {d:.1}x\n\n", .{mb_simd / mb_scalar});

    std.debug.print("\nTest 3: Check for Escapes\n", .{});
    std.debug.print("----------------------------------------------------------------------\n", .{});

    const with_escape_data = "hello\\nworld\\twith\\rescapes!" ** 1000;

    var has_esc_scalar: bool = false;
    const start_esc_scalar = std.time.milliTimestamp();
    i = 0;
    while (i < 1000) : (i += 1) {
        has_esc_scalar = scalar.hasEscapes(with_escape_data);
    }
    const end_esc_scalar = std.time.milliTimestamp();
    const elapsed_esc_scalar = @as(f64, @floatFromInt(end_esc_scalar - start_esc_scalar)) / 1000.0;
    const mb_esc_scalar = @as(f64, @floatFromInt(with_escape_data.len * 1000)) / elapsed_esc_scalar / MB;

    std.debug.print("Scalar hasEscapes:\n", .{});
    std.debug.print("  Speed: {d:.1} MB/s\n", .{mb_esc_scalar});
    std.debug.print("  Result: {}\n\n", .{has_esc_scalar});

    var has_esc_simd: bool = false;
    const start_esc_simd = std.time.milliTimestamp();
    i = 0;
    while (i < 1000) : (i += 1) {
        has_esc_simd = simd.hasEscapes(with_escape_data);
    }
    const end_esc_simd = std.time.milliTimestamp();
    const elapsed_esc_simd = @as(f64, @floatFromInt(end_esc_simd - start_esc_simd)) / 1000.0;
    const mb_esc_simd = @as(f64, @floatFromInt(with_escape_data.len * 1000)) / elapsed_esc_simd / MB;

    std.debug.print("SIMD hasEscapes:\n", .{});
    std.debug.print("  Speed: {d:.1} MB/s\n", .{mb_esc_simd});
    std.debug.print("  Result: {}\n", .{has_esc_simd});
    std.debug.print("  Speedup: {d:.1}x\n\n", .{mb_esc_simd / mb_esc_scalar});

    std.debug.print("======================================================================\n", .{});
    std.debug.print("Target: 1000 MB/s (1 GB/s)\n", .{});
    std.debug.print("Baseline: ~100 MB/s\n", .{});
    std.debug.print("======================================================================\n", .{});
}
