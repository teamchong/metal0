const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const allocator_helper = @import("allocator_helper.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = allocator_helper.getBenchmarkAllocator(gpa);

    var tokenizer = try Tokenizer.init("cl100k_base.json", allocator);
    defer tokenizer.deinit();

    const test_text = "The quick brown fox " ** 10;

    // Warm up
    {
        const tokens = try tokenizer.encode(test_text);
        allocator.free(tokens);
    }

    // Measure 1000 encodes
    const iterations: usize = 1000;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var encode_count: usize = 0;
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const tokens = try tokenizer.encode(test_text);
        allocator.free(tokens);
        encode_count += 1;
    }

    // Test with arena
    var arena2 = std.heap.ArenaAllocator.init(allocator);
    defer arena2.deinit();

    i = 0;
    while (i < iterations) : (i += 1) {
        const tokens = try tokenizer.encode(test_text);
        allocator.free(tokens);
    }

    std.debug.print("Completed {} iterations successfully\n", .{encode_count});
    std.debug.print("Test purpose: Manual profiling with dtrace/instruments\n", .{});
}
