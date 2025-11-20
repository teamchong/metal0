const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load cl100k_base with full BPE vocab
    var tokenizer = try Tokenizer.init("dist/cl100k_base_full.json", allocator);
    defer tokenizer.deinit();

    const TEXT = 
        \\The cat sat on the mat. The dog ran in the park. The bird flew in the sky. The fish swam in the sea. The snake slithered on the ground. The rabbit hopped in the field. The fox ran through the forest. The bear climbed the tree. The wolf howled at the moon. The deer grazed in the meadow.
    ;

    // Warmup
    {
        var i: usize = 0;
        while (i < 100) : (i += 1) {
            const tokens = try tokenizer.encode(TEXT);
            allocator.free(tokens);
        }
    }

    // Benchmark
    const iterations: usize = 60000;
    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const tokens = try tokenizer.encode(TEXT);
        allocator.free(tokens);
    }
    const end = std.time.nanoTimestamp();
    const elapsed_ms = @divFloor(end - start, 1_000_000);

    std.debug.print("{}ms\n", .{elapsed_ms});
}
