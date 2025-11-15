/// String Scanning Benchmark - Test SIMD on realistic string data
const std = @import("std");
const simd = @import("simd/dispatch.zig");
const scalar = @import("simd/scalar.zig");

const MB = 1024 * 1024;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("======================================================================\n", .{});
    std.debug.print("String Scanning Benchmark - SIMD vs Scalar\n", .{});
    std.debug.print("======================================================================\n\n", .{});

    std.debug.print("SIMD Implementation: {s}\n\n", .{simd.getSimdInfo()});

    // Generate a large string with special char at the end
    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    // Add 1 MB of regular text (no special chars)
    var i: usize = 0;
    while (i < 1024) : (i += 1) {
        try buf.writer(allocator).writeAll("This is a test string with no special characters yet ");
    }

    // Add special character at 80% through
    const special_pos = buf.items.len * 4 / 5;
    buf.items[special_pos] = '{';

    const test_data = buf.items;
    const iterations: usize = 100;

    std.debug.print("Test data size: {d:.1} KB\n", .{@as(f64, @floatFromInt(test_data.len)) / 1024.0});
    std.debug.print("Special char '{c}' at position: {}\n", .{ '{', special_pos });
    std.debug.print("Iterations: {}\n\n", .{iterations});

    // Benchmark scalar
    std.debug.print("Running scalar scan...\n", .{});
    const start_scalar = std.time.nanoTimestamp();
    var scalar_sum: usize = 0;
    i = 0;
    while (i < iterations) : (i += 1) {
        if (scalar.findSpecialChar(test_data, 0)) |pos| {
            scalar_sum += pos;
        }
    }
    const end_scalar = std.time.nanoTimestamp();
    const elapsed_scalar = @as(f64, @floatFromInt(end_scalar - start_scalar)) / 1_000_000_000.0;
    const bytes_scalar = test_data.len * iterations;
    const mb_scalar = @as(f64, @floatFromInt(bytes_scalar)) / elapsed_scalar / MB;

    std.debug.print("Scalar scan:\n", .{});
    std.debug.print("  Time: {d:.6}s\n", .{elapsed_scalar});
    std.debug.print("  Speed: {d:.1} MB/s\n", .{mb_scalar});
    std.debug.print("  Verification: {} (should be {})\n\n", .{ scalar_sum, special_pos * iterations });

    // Benchmark SIMD
    std.debug.print("Running SIMD scan...\n", .{});
    const start_simd = std.time.nanoTimestamp();
    var simd_sum: usize = 0;
    i = 0;
    while (i < iterations) : (i += 1) {
        if (simd.findSpecialChar(test_data, 0)) |pos| {
            simd_sum += pos;
        }
    }
    const end_simd = std.time.nanoTimestamp();
    const elapsed_simd = @as(f64, @floatFromInt(end_simd - start_simd)) / 1_000_000_000.0;
    const bytes_simd = test_data.len * iterations;
    const mb_simd = @as(f64, @floatFromInt(bytes_simd)) / elapsed_simd / MB;

    std.debug.print("SIMD scan:\n", .{});
    std.debug.print("  Time: {d:.6}s\n", .{elapsed_simd});
    std.debug.print("  Speed: {d:.1} MB/s\n", .{mb_simd});
    std.debug.print("  Verification: {} (should be {})\n\n", .{ simd_sum, special_pos * iterations });

    // Results
    std.debug.print("======================================================================\n", .{});
    std.debug.print("RESULTS\n", .{});
    std.debug.print("======================================================================\n\n", .{});

    const speedup = mb_simd / mb_scalar;
    std.debug.print("SIMD Speedup: {d:.2}x\n", .{speedup});
    std.debug.print("Scalar: {d:.1} MB/s\n", .{mb_scalar});
    std.debug.print("SIMD:   {d:.1} MB/s\n\n", .{mb_simd});

    const target_speed: f64 = 1000.0; // 1 GB/s
    if (mb_simd >= target_speed) {
        std.debug.print("✅ TARGET ACHIEVED! {d:.1} MB/s >= 1000 MB/s\n", .{mb_simd});
    } else {
        const progress = (mb_simd / target_speed) * 100.0;
        std.debug.print("📊 Progress: {d:.1}% of 1 GB/s target\n", .{progress});
        std.debug.print("   Need: {d:.1} MB/s more\n", .{target_speed - mb_simd});
    }

    // Test hasEscapes
    std.debug.print("\n----------------------------------------------------------------------\n", .{});
    std.debug.print("hasEscapes Benchmark\n", .{});
    std.debug.print("----------------------------------------------------------------------\n\n", .{});

    const no_escape_data = "hello world this is a test without escapes " ** 1000;

    const escape_iterations: usize = 1000;

    // Scalar hasEscapes (no escapes)
    var start = std.time.nanoTimestamp();
    var has_esc: bool = false;
    i = 0;
    while (i < escape_iterations) : (i += 1) {
        has_esc = scalar.hasEscapes(no_escape_data);
    }
    var end = std.time.nanoTimestamp();
    var elapsed = @as(f64, @floatFromInt(end - start)) / 1_000_000_000.0;
    const no_esc_scalar_speed = @as(f64, @floatFromInt(no_escape_data.len * escape_iterations)) / elapsed / MB;

    std.debug.print("Scalar hasEscapes (no escapes): {d:.1} MB/s (result: {})\n", .{ no_esc_scalar_speed, has_esc });

    // SIMD hasEscapes (no escapes)
    start = std.time.nanoTimestamp();
    i = 0;
    while (i < escape_iterations) : (i += 1) {
        has_esc = simd.hasEscapes(no_escape_data);
    }
    end = std.time.nanoTimestamp();
    elapsed = @as(f64, @floatFromInt(end - start)) / 1_000_000_000.0;
    const no_esc_simd_speed = @as(f64, @floatFromInt(no_escape_data.len * escape_iterations)) / elapsed / MB;

    std.debug.print("SIMD hasEscapes (no escapes):   {d:.1} MB/s (result: {})\n", .{ no_esc_simd_speed, has_esc });
    std.debug.print("Speedup: {d:.2}x\n\n", .{no_esc_simd_speed / no_esc_scalar_speed});

    // Test countMatching
    std.debug.print("----------------------------------------------------------------------\n", .{});
    std.debug.print("countMatching Benchmark\n", .{});
    std.debug.print("----------------------------------------------------------------------\n\n", .{});

    const count_data = "a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z," ** 1000;
    const count_iterations: usize = 1000;

    // Scalar count
    start = std.time.nanoTimestamp();
    var count: usize = 0;
    i = 0;
    while (i < count_iterations) : (i += 1) {
        count = scalar.countMatching(count_data, ',');
    }
    end = std.time.nanoTimestamp();
    elapsed = @as(f64, @floatFromInt(end - start)) / 1_000_000_000.0;
    const count_scalar_speed = @as(f64, @floatFromInt(count_data.len * count_iterations)) / elapsed / MB;

    std.debug.print("Scalar countMatching: {d:.1} MB/s (found {} commas)\n", .{ count_scalar_speed, count });

    // SIMD count
    start = std.time.nanoTimestamp();
    i = 0;
    while (i < count_iterations) : (i += 1) {
        count = simd.countMatching(count_data, ',');
    }
    end = std.time.nanoTimestamp();
    elapsed = @as(f64, @floatFromInt(end - start)) / 1_000_000_000.0;
    const count_simd_speed = @as(f64, @floatFromInt(count_data.len * count_iterations)) / elapsed / MB;

    std.debug.print("SIMD countMatching:   {d:.1} MB/s (found {} commas)\n", .{ count_simd_speed, count });
    std.debug.print("Speedup: {d:.2}x\n\n", .{count_simd_speed / count_scalar_speed});

    // Overall summary
    std.debug.print("======================================================================\n", .{});
    std.debug.print("OVERALL SUMMARY\n", .{});
    std.debug.print("======================================================================\n\n", .{});

    const avg_speedup = (speedup + (no_esc_simd_speed / no_esc_scalar_speed) + (count_simd_speed / count_scalar_speed)) / 3.0;
    const peak_speed = @max(@max(mb_simd, no_esc_simd_speed), count_simd_speed);

    std.debug.print("Average SIMD speedup: {d:.2}x\n", .{avg_speedup});
    std.debug.print("Peak SIMD speed: {d:.1} MB/s\n", .{peak_speed});

    if (peak_speed >= 1000.0) {
        std.debug.print("\n✅ TARGET ACHIEVED!\n", .{});
    }
}
