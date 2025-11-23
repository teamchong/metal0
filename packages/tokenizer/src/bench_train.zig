const std = @import("std");
const Trainer = @import("trainer.zig").Trainer;
const allocator_helper = @import("allocator_helper.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = allocator_helper.getBenchmarkAllocator(gpa);

    const VOCAB_SIZE = 32000;

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

    // Save trained model for verification
    std.debug.print("Saving to pyaot_trained.json...\n", .{});
    tokenizer.saveToFile("pyaot_trained.json") catch |err| {
        std.debug.print("ERROR saving file: {}\n", .{err});
        return err;
    };
    std.debug.print("✅ Saved successfully!\n", .{});

    std.debug.print("{d}ms\n", .{elapsed_ms});
}
