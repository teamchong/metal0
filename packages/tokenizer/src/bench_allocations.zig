const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;

pub fn main() !void {
    // Use GPA with verbose leak detection
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .verbose_log = false,
    }){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leaked!\n", .{});
        }
    }

    const allocator = gpa.allocator();

    // Load tokenizer and measure initialization
    const init_start = std.time.nanoTimestamp();
    var tokenizer = try Tokenizer.init("dist/cl100k_base_full.json", allocator);
    defer tokenizer.deinit();
    const init_end = std.time.nanoTimestamp();

    std.debug.print("Initialization time: {d:.2}ms\n\n", .{
        @as(f64, @floatFromInt(init_end - init_start)) / 1_000_000.0,
    });

    // Single encode
    const text = "Hello world, this is a test of the tokenizer performance.";

    const encode_start = std.time.nanoTimestamp();
    const tokens = try tokenizer.encode(text);
    defer allocator.free(tokens);
    const encode_end = std.time.nanoTimestamp();

    std.debug.print("Single encode:\n", .{});
    std.debug.print("  Time: {d:.3}ms\n", .{
        @as(f64, @floatFromInt(encode_end - encode_start)) / 1_000_000.0,
    });
    std.debug.print("  Tokens: {any}\n\n", .{tokens});

    // Test 100 iterations
    const iterations: usize = 100;
    const iter_start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        const tokens_iter = try tokenizer.encode(text);
        allocator.free(tokens_iter);
    }

    const iter_end = std.time.nanoTimestamp();

    std.debug.print("100 iterations:\n", .{});
    std.debug.print("  Total time: {d:.2}ms\n", .{
        @as(f64, @floatFromInt(iter_end - iter_start)) / 1_000_000.0,
    });
    std.debug.print("  Per-iteration: {d:.3}ms\n", .{
        @as(f64, @floatFromInt(iter_end - iter_start)) / 1_000_000.0 / @as(f64, @floatFromInt(iterations)),
    });

    // Test with larger text to see chunk behavior
    const large_text = "The quick brown fox jumps over the lazy dog. " ** 50;

    const large_start = std.time.nanoTimestamp();
    const large_tokens = try tokenizer.encode(large_text);
    defer allocator.free(large_tokens);
    const large_end = std.time.nanoTimestamp();

    std.debug.print("\nLarge text (2300 bytes):\n", .{});
    std.debug.print("  Time: {d:.3}ms\n", .{
        @as(f64, @floatFromInt(large_end - large_start)) / 1_000_000.0,
    });
    std.debug.print("  Tokens: {} tokens\n", .{large_tokens.len});
}
