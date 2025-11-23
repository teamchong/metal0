/// Large-scale SIMD Benchmark - Test with realistic JSON data sizes
const std = @import("std");
const simd = @import("simd/dispatch.zig");
const scalar = @import("simd/scalar.zig");

const MB = 1024 * 1024;

fn benchmarkScan(comptime name: []const u8, comptime use_simd: bool, data: []const u8, iterations: usize) f64 {
    const start = std.time.nanoTimestamp();

    var i: usize = 0;
    var total_found: usize = 0;
    while (i < iterations) : (i += 1) {
        if (use_simd) {
            if (simd.findSpecialChar(data, 0)) |pos| {
                total_found += pos;
            }
        } else {
            if (scalar.findSpecialChar(data, 0)) |pos| {
                total_found += pos;
            }
        }
    }

    const end = std.time.nanoTimestamp();
    const elapsed = @as(f64, @floatFromInt(end - start)) / 1_000_000_000.0;
    const bytes_processed = data.len * iterations;
    const mb_per_sec = @as(f64, @floatFromInt(bytes_processed)) / elapsed / MB;

    std.debug.print("{s}:\n", .{name});
    std.debug.print("  Processed: {d:.1} MB\n", .{@as(f64, @floatFromInt(bytes_processed)) / MB});
    std.debug.print("  Time: {d:.3}s\n", .{elapsed});
    std.debug.print("  Speed: {d:.1} MB/s\n", .{mb_per_sec});
    std.debug.print("  Found positions sum: {} (verify correctness)\n\n", .{total_found});

    return mb_per_sec;
}

fn generateLargeJson(allocator: std.mem.Allocator, num_items: usize) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);

    var writer = buf.writer(allocator);

    try writer.writeAll("{\"items\":[");

    var i: usize = 0;
    while (i < num_items) : (i += 1) {
        if (i > 0) try writer.writeAll(",");
        try writer.print(
            "{{\"id\":{},\"name\":\"item_{}\",\"value\":{d},\"active\":{},\"tags\":[\"tag1\",\"tag2\",\"tag3\"]}}",
            .{ i, i, @as(f64, @floatFromInt(i)) * 1.5, i % 2 == 0 },
        );
    }

    try writer.writeAll("]}");

    return buf.toOwnedSlice(allocator);
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("======================================================================\n", .{});
    std.debug.print("SIMD Large-Scale Benchmark - Realistic JSON Performance\n", .{});
    std.debug.print("======================================================================\n\n", .{});

    std.debug.print("SIMD Implementation: {s}\n\n", .{simd.getSimdInfo()});

    // Test 1: Small JSON (1 KB) - Many iterations
    std.debug.print("Test 1: Small JSON (1 KB, 10000 iterations)\n", .{});
    std.debug.print("----------------------------------------------------------------------\n", .{});

    const small_json = try generateLargeJson(allocator, 5);
    defer allocator.free(small_json);
    std.debug.print("Data size: {} bytes\n\n", .{small_json.len});

    const small_scalar = benchmarkScan("Scalar scan", false, small_json, 10000);
    const small_simd = benchmarkScan("SIMD scan", true, small_json, 10000);
    std.debug.print("Speedup: {d:.2}x\n\n", .{small_simd / small_scalar});

    // Test 2: Medium JSON (100 KB) - Moderate iterations
    std.debug.print("Test 2: Medium JSON (100 KB, 1000 iterations)\n", .{});
    std.debug.print("----------------------------------------------------------------------\n", .{});

    const medium_json = try generateLargeJson(allocator, 500);
    defer allocator.free(medium_json);
    std.debug.print("Data size: {} bytes ({d:.1} KB)\n\n", .{ medium_json.len, @as(f64, @floatFromInt(medium_json.len)) / 1024.0 });

    const medium_scalar = benchmarkScan("Scalar scan", false, medium_json, 1000);
    const medium_simd = benchmarkScan("SIMD scan", true, medium_json, 1000);
    std.debug.print("Speedup: {d:.2}x\n\n", .{medium_simd / medium_scalar});

    // Test 3: Large JSON (1 MB) - Few iterations
    std.debug.print("Test 3: Large JSON (1 MB, 100 iterations)\n", .{});
    std.debug.print("----------------------------------------------------------------------\n", .{});

    const large_json = try generateLargeJson(allocator, 5000);
    defer allocator.free(large_json);
    std.debug.print("Data size: {} bytes ({d:.1} MB)\n\n", .{ large_json.len, @as(f64, @floatFromInt(large_json.len)) / MB });

    const large_scalar = benchmarkScan("Scalar scan", false, large_json, 100);
    const large_simd = benchmarkScan("SIMD scan", true, large_json, 100);
    std.debug.print("Speedup: {d:.2}x\n\n", .{large_simd / large_scalar});

    // Test 4: Very Large JSON (10 MB) - Single iteration
    std.debug.print("Test 4: Very Large JSON (10 MB, 10 iterations)\n", .{});
    std.debug.print("----------------------------------------------------------------------\n", .{});

    const xlarge_json = try generateLargeJson(allocator, 50000);
    defer allocator.free(xlarge_json);
    std.debug.print("Data size: {} bytes ({d:.1} MB)\n\n", .{ xlarge_json.len, @as(f64, @floatFromInt(xlarge_json.len)) / MB });

    const xlarge_scalar = benchmarkScan("Scalar scan", false, xlarge_json, 10);
    const xlarge_simd = benchmarkScan("SIMD scan", true, xlarge_json, 10);
    std.debug.print("Speedup: {d:.2}x\n\n", .{xlarge_simd / xlarge_scalar});

    // Summary
    std.debug.print("======================================================================\n", .{});
    std.debug.print("SUMMARY\n", .{});
    std.debug.print("======================================================================\n\n", .{});

    const avg_speedup = (small_simd / small_scalar +
        medium_simd / medium_scalar +
        large_simd / large_scalar +
        xlarge_simd / xlarge_scalar) / 4.0;

    std.debug.print("Average SIMD speedup: {d:.2}x\n", .{avg_speedup});
    std.debug.print("Peak SIMD performance: {d:.1} MB/s\n", .{@max(@max(small_simd, medium_simd), @max(large_simd, xlarge_simd))});

    const target_speed: f64 = 1000.0; // 1 GB/s
    const peak_speed = @max(@max(small_simd, medium_simd), @max(large_simd, xlarge_simd));

    if (peak_speed >= target_speed) {
        std.debug.print("\n✅ TARGET ACHIEVED! {d:.1} MB/s >= 1000 MB/s (1 GB/s)\n", .{peak_speed});
    } else {
        const progress = (peak_speed / target_speed) * 100.0;
        std.debug.print("\n📊 Progress: {d:.1}% of 1 GB/s target\n", .{progress});
        std.debug.print("   Current peak: {d:.1} MB/s\n", .{peak_speed});
        std.debug.print("   Need: {d:.1} MB/s more to reach goal\n", .{target_speed - peak_speed});
    }

    std.debug.print("\nNote: These benchmarks test SIMD string scanning only.\n", .{});
    std.debug.print("Full JSON parsing includes additional overhead.\n", .{});
}
