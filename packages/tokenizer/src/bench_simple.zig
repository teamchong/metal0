const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    var tok = try Tokenizer.init("dist/cl100k_base_full.json", allocator);
    defer tok.deinit();

    const text1 = "The quick brown fox jumps over the lazy dog.";
    const text2 = "Hello world! Python is great for programming.";
    const text3 = "Machine learning and artificial intelligence are transforming technology.";

    // Warmup
    for (0..10) |_| {
        _ = try tok.encode(text1);
        // Note: encode() returns arena-allocated memory, don't free!
    }

    // Benchmark - same as compare_all.py (30K iterations, cycling through texts)
    const iterations = 60000;
    var timer = try std.time.Timer.start();
    for (0..iterations) |i| {
        switch (i % 3) {
            0 => _ = try tok.encode(text1),
            1 => _ = try tok.encode(text2),
            2 => _ = try tok.encode(text3),
            else => unreachable,
        }
    }
    const elapsed_ns = timer.read();
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;

    // Match compare_all.py output format
    std.debug.print("60000 iterations: {d:.0}ms total\n", .{elapsed_ms});
}
