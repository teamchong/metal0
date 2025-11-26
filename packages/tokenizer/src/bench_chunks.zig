const std = @import("std");
const cl100k_splitter = @import("cl100k_splitter.zig");
const allocator_helper = @import("allocator_helper");
const json = @import("runtime/src/json/parse.zig");
const JsonValue = @import("runtime/src/json/value.zig").JsonValue;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = allocator_helper.getAllocator(gpa);

    // Load benchmark data
    const file = try std.fs.cwd().openFile("benchmark_data.json", .{});
    defer file.close();

    const file_size = (try file.stat()).size;
    const json_data = try allocator.alloc(u8, file_size);
    defer allocator.free(json_data);
    _ = try file.readAll(json_data);

    var parsed = try json_parser.parse(json_data, allocator);
    defer parsed.deinit(allocator);

    const texts_json = switch (parsed) {
        .object => |obj| blk: {
            const texts_value = obj.get("texts") orelse return error.MissingTextsField;
            break :blk switch (texts_value.*) {
                .array => |arr| arr,
                else => return error.InvalidTextsField,
            };
        },
        else => return error.InvalidJsonRoot,
    };

    var total_chunks: usize = 0;
    var max_chunks: usize = 0;
    var min_chunks: usize = std.math.maxInt(usize);

    for (texts_json.items, 0..) |*text_value, idx| {
        const text = switch (text_value.*) {
            .string => |s| s,
            else => return error.InvalidTextItem,
        };

        var chunks: usize = 0;
        var chunk_iter = cl100k_splitter.chunks(text);
        while (chunk_iter.next()) |_| {
            chunks += 1;
        }

        total_chunks += chunks;
        max_chunks = @max(max_chunks, chunks);
        min_chunks = @min(min_chunks, chunks);

        if (idx < 5) {
            std.debug.print("Text {}: {} bytes → {} chunks\n", .{ idx, text.len, chunks });
        }
    }

    const avg_chunks = @as(f64, @floatFromInt(total_chunks)) / @as(f64, @floatFromInt(texts_json.items.len));

    std.debug.print("\nChunk Statistics (583 texts):\n", .{});
    std.debug.print("  Total chunks: {}\n", .{total_chunks});
    std.debug.print("  Min chunks: {}\n", .{min_chunks});
    std.debug.print("  Max chunks: {}\n", .{max_chunks});
    std.debug.print("  Avg chunks: {d:.1}\n", .{avg_chunks});
}
