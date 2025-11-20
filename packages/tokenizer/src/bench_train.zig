const std = @import("std");
const Trainer = @import("trainer.zig").Trainer;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const VOCAB_SIZE = 2048;

    // Load realistic benchmark data
    const file = try std.fs.cwd().openFile("benchmark_data.json", .{});
    defer file.close();

    const file_size = (try file.stat()).size;
    const json_data = try allocator.alloc(u8, file_size);
    defer allocator.free(json_data);
    _ = try file.readAll(json_data);

    // Parse JSON to get texts array
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
    defer parsed.deinit();

    const texts_json = parsed.value.object.get("texts").?.array;
    var texts = std.ArrayList([]const u8){};
    defer texts.deinit(allocator);

    for (texts_json.items) |text_value| {
        const text = text_value.string;
        const owned_text = try allocator.dupe(u8, text);
        try texts.append(allocator, owned_text);
    }

    // Train
    var trainer = try Trainer.init(VOCAB_SIZE, allocator);
    defer trainer.deinit();

    const start = std.time.nanoTimestamp();
    var tokenizer = try trainer.trainFromIterator(texts.items);
    defer tokenizer.deinit();
    const end = std.time.nanoTimestamp();
    const elapsed_ms = @divFloor(end - start, 1_000_000);

    std.debug.print("{d}ms\n", .{elapsed_ms});
}
