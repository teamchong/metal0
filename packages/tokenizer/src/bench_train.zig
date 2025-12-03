/// BPE Training Benchmark (Zig native)
/// Trains BPE tokenizer on sample data to measure training performance.
const std = @import("std");
const BpeTrainer = @import("bpe_trainer.zig").BpeTrainer;

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    // Sample training data
    const texts = [_][]const u8{
        "The quick brown fox jumps over the lazy dog.",
        "Hello world! Python is great for programming.",
        "Machine learning and artificial intelligence are transforming technology.",
        "Natural language processing enables computers to understand human text.",
        "Deep learning models require large amounts of training data.",
    };

    const vocab_size: usize = 32000;
    const iterations: usize = 300;

    std.debug.print("BPE Training Benchmark: {d} texts x {d} iterations\n", .{ texts.len, iterations });
    std.debug.print("Vocab size: {d}\n\n", .{vocab_size});

    var timer = try std.time.Timer.start();

    for (0..iterations) |_| {
        var trainer = try BpeTrainer.init(vocab_size, allocator);
        _ = try trainer.trainFromIterator(&texts);
        trainer.deinit();
    }

    const elapsed_ns = timer.read();
    const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000.0;

    std.debug.print("Completed {d} training iterations in {d:.2}ms\n", .{ iterations, elapsed_ms });
    std.debug.print("Average: {d:.2}ms per iteration\n", .{ elapsed_ms / @as(f64, @floatFromInt(iterations)) });
}
