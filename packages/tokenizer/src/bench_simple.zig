const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;

pub fn main() !void {
    const allocator = std.heap.c_allocator;
    
    var tok = try Tokenizer.init("dist/cl100k_base_full.json", allocator);
    
    const text1 = "The quick brown fox jumps over the lazy dog.";
    const text2 = "Hello world! Python is great for programming.";
    const text3 = "Machine learning and artificial intelligence are transforming technology.";
    
    // Warmup
    for (0..10) |_| {
        _ = try tok.encode(text1);
    }
    
    // Benchmark
    var timer = try std.time.Timer.start();
    for (0..10000) |_| {
        _ = try tok.encode(text1);
        _ = try tok.encode(text2);
        _ = try tok.encode(text3);
    }
    const elapsed_ns = timer.read();
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;
    
    std.debug.print("30000 encodes: {d:.0}ms\n", .{elapsed_ms});
}
