const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const allocator_helper = @import("allocator_helper");
const json = @import("runtime/src/json/parse.zig");
const JsonValue = @import("runtime/src/json/value.zig").JsonValue;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = allocator_helper.getAllocator(gpa);

    // Load cl100k_base with full BPE vocab
    var tokenizer = try Tokenizer.init("dist/cl100k_base_full.json", allocator);
    defer tokenizer.deinit();

    // Load benchmark data (583 texts matching Python benchmarks)
    const benchmark_json = try std.fs.cwd().readFileAlloc(allocator, "benchmark_data.json", 10 * 1024 * 1024);
    defer allocator.free(benchmark_json);

    var parsed_value = try json_parser.parse(benchmark_json, allocator);
    defer parsed_value.deinit(allocator);

    // Extract texts array from {"texts": [...]}
    const texts_arr = switch (parsed_value) {
        .object => |obj| blk: {
            const texts_value = obj.get("texts") orelse return error.MissingTextsField;
            break :blk switch (texts_value.*) {
                .array => |arr| arr,
                else => return error.InvalidTextsField,
            };
        },
        else => return error.InvalidJsonRoot,
    };

    // Extract string slices from array
    var texts = try std.ArrayList([]const u8).initCapacity(allocator, texts_arr.items.len);
    defer texts.deinit();
    for (texts_arr.items) |*item| {
        switch (item.*) {
            .string => |s| try texts.append(s),
            else => return error.InvalidTextItem,
        }
    }

    const texts_slice = texts.items;

    // Benchmark: 1000 iterations over all texts (matching Python benchmarks)
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        for (texts_slice) |text| {
            _ = try tokenizer.encode(text);
            // Note: encode() uses arena allocation, tokens are freed by tokenizer.deinit()
        }
    }
}
