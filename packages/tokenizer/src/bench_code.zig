const std = @import("std");
const Tokenizer = @import("tokenizer").Tokenizer;
const allocator_helper = @import("allocator_helper.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = allocator_helper.getBenchmarkAllocator(gpa);

    // Read test code
    const code = @embedFile("../../../test_code.py");
    
    std.debug.print("Code length: {} bytes\n\n", .{code.len});
    
    // Load tokenizer
    const vocab_file = try std.fs.cwd().readFileAlloc(allocator, "gpt2_vocab.json", 10_000_000);
    defer allocator.free(vocab_file);
    
    const merges_file = try std.fs.cwd().readFileAlloc(allocator, "gpt2_merges.txt", 10_000_000);
    defer allocator.free(merges_file);
    
    var tokenizer = try Tokenizer.init(allocator, vocab_file, merges_file);
    defer tokenizer.deinit();
    
    // Benchmark
    const iterations = 10000;
    const start = std.time.milliTimestamp();
    
    var i: usize = 0;
    var last_tokens: []u32 = undefined;
    while (i < iterations) : (i += 1) {
        if (i > 0) allocator.free(last_tokens);
        last_tokens = try tokenizer.encode(code);
    }
    
    const elapsed = std.time.milliTimestamp() - start;
    
    std.debug.print("PyAOT on CODE:\n", .{});
    std.debug.print("  {} iterations: {}ms\n", .{iterations, elapsed});
    std.debug.print("  Per iteration: {}μs\n", .{@divTrunc(elapsed * 1000, iterations)});
    std.debug.print("  Token count: {}\n", .{last_tokens.len});
    std.debug.print("  First 20 tokens: ", .{});
    for (last_tokens[0..@min(20, last_tokens.len)]) |token| {
        std.debug.print("{} ", .{token});
    }
    std.debug.print("\n", .{});
    
    allocator.free(last_tokens);
}
