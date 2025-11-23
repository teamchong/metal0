const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const allocator_helper = @import("allocator_helper.zig");

// Global timing counters (thread-local in production)
var time_regex_split: u64 = 0;
var time_cache_lookup: u64 = 0;
var time_encoder_init: u64 = 0;
var time_aho_corasick: u64 = 0;
var time_bitfield: u64 = 0;
var time_token_merge: u64 = 0;
var time_arena_alloc: u64 = 0;
var time_total_encode: u64 = 0;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = allocator_helper.getBenchmarkAllocator(gpa);

    // Load test data
    const test_file = try std.fs.cwd().readFileAlloc(allocator, "data/test_data.json", 10 * 1024 * 1024);
    defer allocator.free(test_file);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, test_file, .{});
    defer parsed.deinit();

    const texts_json = parsed.value.object.get("texts").?.array;

    // Load tokenizer
    var tokenizer = try Tokenizer.init("dist/cl100k_base_full.json", allocator);
    defer tokenizer.deinit();

    const iterations: usize = 100;
    const num_texts = texts_json.items.len;

    std.debug.print("📊 Profiling {} texts × {} iterations\n", .{ num_texts, iterations });
    std.debug.print("============================================================\n\n", .{});

    // Warmup
    {
        var i: usize = 0;
        while (i < 10) : (i += 1) {
            for (texts_json.items) |text_val| {
                const text = text_val.string;
                _ = try tokenizer.encode(text);
            }
        }
    }

    // Reset counters
    time_regex_split = 0;
    time_cache_lookup = 0;
    time_encoder_init = 0;
    time_aho_corasick = 0;
    time_bitfield = 0;
    time_token_merge = 0;
    time_arena_alloc = 0;
    time_total_encode = 0;

    // Benchmark with profiling
    const start_total = std.time.nanoTimestamp();

    var iter: usize = 0;
    while (iter < iterations) : (iter += 1) {
        for (texts_json.items) |text_val| {
            const text = text_val.string;

            const start_encode = std.time.nanoTimestamp();
            _ = try tokenizer.encode(text);
            const end_encode = std.time.nanoTimestamp();

            time_total_encode += @intCast(end_encode - start_encode);
        }
    }

    const end_total = std.time.nanoTimestamp();
    const total_ms = @divFloor(end_total - start_total, 1_000_000);
    const encode_ms = @divFloor(@as(i64, @intCast(time_total_encode)), 1_000_000);

    std.debug.print("Total time: {}ms ({} texts × {} iter)\n\n", .{ total_ms, num_texts, iterations });
    std.debug.print("Time breakdown:\n", .{});
    std.debug.print("------------------------------------------------------------\n", .{});
    std.debug.print("  Total encode(): {}ms\n", .{encode_ms});
    std.debug.print("  Framework overhead: {}ms ({d:.1}%)\n", .{
        total_ms - encode_ms,
        @as(f64, @floatFromInt(total_ms - encode_ms)) / @as(f64, @floatFromInt(total_ms)) * 100.0
    });

    // Compare with rs-bpe
    const rs_bpe_ms: u64 = 425;
    const gap_ms = if (total_ms > rs_bpe_ms) total_ms - rs_bpe_ms else 0;
    const ratio = @as(f64, @floatFromInt(total_ms)) / @as(f64, @floatFromInt(rs_bpe_ms));

    std.debug.print("\n📊 vs rs-bpe:\n", .{});
    std.debug.print("------------------------------------------------------------\n", .{});
    std.debug.print("  PyAOT: {}ms\n", .{total_ms});
    std.debug.print("  rs-bpe: {}ms\n", .{rs_bpe_ms});
    std.debug.print("  Gap: {}ms ({d:.2}% slower)\n", .{ gap_ms, (ratio - 1.0) * 100.0 });
    std.debug.print("  Ratio: {d:.3}x\n", .{ratio});

    std.debug.print("\n🔍 Next step: Instrument encode() internals\n", .{});
    std.debug.print("   to break down the {}ms into:\n", .{encode_ms});
    std.debug.print("   - Regex splitting (cl100k_splitter)\n", .{});
    std.debug.print("   - LRU cache lookups\n", .{});
    std.debug.print("   - AhoCorasick pattern matching\n", .{});
    std.debug.print("   - BitField operations\n", .{});
    std.debug.print("   - Token merging loops\n", .{});
    std.debug.print("   - Arena allocations\n", .{});
}
