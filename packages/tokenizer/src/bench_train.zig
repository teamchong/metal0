const std = @import("std");
const build_options = @import("build_options");
const trainer_mod = @import("trainer.zig");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const allocator_helper = @import("allocator_helper.zig");

// Algorithm selection based on build options
const Trainer = if (build_options.runtime_selection)
    // Multiple algorithms included - use runtime selection
    trainer_mod.RuntimeTrainer
else
    // Single algorithm - use comptime selection (smallest binary)
    trainer_mod.TrainerFor(std.meta.stringToEnum(trainer_mod.Algorithm, build_options.default_algorithm) orelse .BPE);

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

    // Train 300 times to match HuggingFace benchmark (amortize startup overhead)
    const start = std.time.nanoTimestamp();

    var last_tokenizer: ?Tokenizer = null;
    var i: usize = 0;
    while (i < 300) : (i += 1) {
        var trainer = try Trainer.init(VOCAB_SIZE, allocator);
        const tokenizer = try trainer.trainFromIterator(texts.items);
        trainer.deinit();

        // Keep last one for saving
        if (last_tokenizer) |*tok| {
            tok.deinit();
        }
        last_tokenizer = tokenizer;
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ms = @divFloor(end - start, 1_000_000);

    // Save last trained model for verification
    if (last_tokenizer) |*tok| {
        defer tok.deinit();
        std.debug.print("Saving to pyaot_trained.json...\n", .{});
        tok.saveToFile("pyaot_trained.json") catch |err| {
            std.debug.print("ERROR saving file: {}\n", .{err});
            return err;
        };
        std.debug.print("✅ Saved successfully!\n", .{});
    }

    std.debug.print("{d}ms\n", .{elapsed_ms});
}
