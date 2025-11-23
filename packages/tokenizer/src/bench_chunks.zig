const std = @import("std");
const cl100k_splitter = @import("cl100k_splitter.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load benchmark data
    const file = try std.fs.cwd().openFile("benchmark_data.json", .{});
    defer file.close();

    const file_size = (try file.stat()).size;
    const json_data = try allocator.alloc(u8, file_size);
    defer allocator.free(json_data);
    _ = try file.readAll(json_data);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
    defer parsed.deinit();

    const texts_json = parsed.value.object.get("texts").?.array;

    var total_chunks: usize = 0;
    var max_chunks: usize = 0;
    var min_chunks: usize = std.math.maxInt(usize);

    for (texts_json.items, 0..) |text_value, idx| {
        const text = text_value.string;

        var chunks: usize = 0;
        var chunk_iter = cl100k_splitter.chunks(text);
        while (chunk_iter.next()) |_| {
            chunks += 1;
        }

        total_chunks += chunks;
        max_chunks = @max(max_chunks, chunks);
        min_chunks = @min(min_chunks, chunks);

        if (idx < 5) {
            std.debug.print("Text {}: {} bytes → {} chunks\n", .{idx, text.len, chunks});
        }
    }

    const avg_chunks = @as(f64, @floatFromInt(total_chunks)) / @as(f64, @floatFromInt(texts_json.items.len));

    std.debug.print("\nChunk Statistics (583 texts):\n", .{});
    std.debug.print("  Total chunks: {}\n", .{total_chunks});
    std.debug.print("  Min chunks: {}\n", .{min_chunks});
    std.debug.print("  Max chunks: {}\n", .{max_chunks});
    std.debug.print("  Avg chunks: {d:.1}\n", .{avg_chunks});
}
