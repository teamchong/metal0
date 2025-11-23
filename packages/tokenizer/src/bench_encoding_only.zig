const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const allocator_helper = @import("allocator_helper.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = allocator_helper.getBenchmarkAllocator(gpa);

    // Load benchmark data (583 texts)
    const file = try std.fs.cwd().openFile("benchmark_data.json", .{});
    defer file.close();

    const file_size = (try file.stat()).size;
    const json_data = try allocator.alloc(u8, file_size);
    defer allocator.free(json_data);
    _ = try file.readAll(json_data);

    // Parse JSON
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
    defer parsed.deinit();

    const texts_json = parsed.value.object.get("texts").?.array;
    var texts = std.ArrayList([]const u8){};
    defer {
        for (texts.items) |text| allocator.free(text);
        texts.deinit(allocator);
    }

    for (texts_json.items) |text_value| {
        const text = text_value.string;
        const owned_text = try allocator.dupe(u8, text);
        try texts.append(allocator, owned_text);
    }

    // Load tokenizer
    var tokenizer = try Tokenizer.init("dist/cl100k_base_full.json", allocator);
    defer tokenizer.deinit();

    // Get iterations from args (default 100)
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const iterations: usize = if (args.len > 1)
        try std.fmt.parseInt(usize, args[1], 10)
    else
        100;

    // Benchmark encoding only (like Python scripts)
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        for (texts.items) |text| {
            _ = try tokenizer.encode(text);
        }
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ms = @divFloor(end - start, 1_000_000);

    std.debug.print("Encoded {} texts × {} iterations in {}ms\n", .{texts.items.len, iterations, elapsed_ms});
}
