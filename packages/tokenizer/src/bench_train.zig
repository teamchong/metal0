const std = @import("std");
const build_options = @import("build_options");
const trainer_mod = @import("trainer.zig");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const UnigramTokenizer = @import("unigram_tokenizer.zig").UnigramTokenizer;
const allocator_helper = @import("allocator_helper.zig");
// Removed ThreadPool - using std.Thread directly

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
    const allocator = allocator_helper.getBenchmarkAllocator(&gpa);

    // Allow runtime vocab size via VOCAB_SIZE env var (default: 32000)
    const VOCAB_SIZE = if (std.posix.getenv("VOCAB_SIZE")) |size_str|
        std.fmt.parseInt(usize, size_str, 10) catch 32000
    else
        32000;

    // Allow runtime algorithm selection via ALGORITHM env var
    // Example: ALGORITHM=Unigram ./bench_train
    const selected_algorithm = if (std.posix.getenv("ALGORITHM")) |algo_str|
        std.meta.stringToEnum(trainer_mod.Algorithm, algo_str) orelse .BPE
    else
        std.meta.stringToEnum(trainer_mod.Algorithm, build_options.default_algorithm) orelse .BPE;

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
    defer {
        for (texts.items) |text| {
            allocator.free(text);
        }
        texts.deinit(allocator);
    }

    for (texts_json.items) |text_value| {
        const text = text_value.string;
        const owned_text = try allocator.dupe(u8, text);
        try texts.append(allocator, owned_text);
    }

    // Train 300 times to match HuggingFace benchmark (amortize startup overhead)
    const start = std.time.nanoTimestamp();

    // Check if we're training Unigram (different tokenizer type)
    const is_unigram = selected_algorithm == .Unigram;

    if (is_unigram) {
        // Unigram returns UnigramTokenizer
        // Use environment variable for iteration count (default: 300)
        const iterations = if (std.posix.getenv("ITERATIONS")) |iter_str|
            std.fmt.parseInt(usize, iter_str, 10) catch 300
        else
            300;

        var last_tokenizer: ?UnigramTokenizer = null;
        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            // Use parallel training (enabled by initWithThreadPool)
            var trainer = if (build_options.runtime_selection) blk: {
                break :blk try Trainer.initWithThreadPool(VOCAB_SIZE, allocator, selected_algorithm, {});
            } else blk: {
                // Comptime selection - Trainer is UnigramTrainer directly
                break :blk try Trainer.initWithThreadPool(VOCAB_SIZE, allocator, {});
            };
            const result = try trainer.trainFromIterator(texts.items);
            trainer.deinit();

            // Extract UnigramTokenizer (handle both runtime and comptime cases)
            const tokenizer = if (build_options.runtime_selection) blk: {
                // Runtime selection returns TokenizerResult union
                break :blk switch (result) {
                    .Unigram => |tok| tok,
                    else => unreachable,
                };
            } else result; // Comptime selection returns UnigramTokenizer directly

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
    } else {
        // BPE/WordPiece return regular Tokenizer
        var last_tokenizer: ?Tokenizer = null;
        var i: usize = 0;
        while (i < 300) : (i += 1) {
            var trainer = if (build_options.runtime_selection)
                try Trainer.init(VOCAB_SIZE, allocator, selected_algorithm)
            else
                try Trainer.init(VOCAB_SIZE, allocator);
            const result = try trainer.trainFromIterator(texts.items);
            trainer.deinit();

            // Extract Tokenizer (handle both runtime and comptime cases)
            const tokenizer = if (build_options.runtime_selection) blk: {
                // Runtime selection returns TokenizerResult union
                break :blk switch (result) {
                    .BPE, .WordPiece => |tok| tok,
                    else => unreachable,
                };
            } else result; // Comptime selection returns Tokenizer directly

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
}
