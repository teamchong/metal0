const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const allocator_helper = @import("allocator_helper.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = allocator_helper.getBenchmarkAllocator(gpa);

    // Load cl100k_base with full BPE vocab
    var tokenizer = try Tokenizer.init("dist/cl100k_base_full.json", allocator);
    defer tokenizer.deinit();

    // Load benchmark data (583 texts matching Python benchmarks)
    const benchmark_json = try std.fs.cwd().readFileAlloc(allocator, "benchmark_data.json", 10 * 1024 * 1024);
    defer allocator.free(benchmark_json);

    const parsed = try std.json.parseFromSlice(
        struct { texts: [][]const u8 },
        allocator,
        benchmark_json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    const texts = parsed.value.texts;

    // Benchmark: 1000 iterations over all texts (matching Python benchmarks)
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        for (texts) |text| {
            _ = try tokenizer.encode(text);
            // Note: encode() uses arena allocation, tokens are freed by tokenizer.deinit()
        }
    }
}
