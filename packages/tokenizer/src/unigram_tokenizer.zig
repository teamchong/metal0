/// Unigram Tokenizer - separate from BPE/WordPiece Tokenizer
const std = @import("std");
const Allocator = std.mem.Allocator;
const unigram_model = @import("unigram_model.zig");
const Unigram = unigram_model.Unigram;
const VocabEntry = unigram_model.VocabEntry;

pub const UnigramTokenizer = struct {
    model: Unigram,
    allocator: Allocator,

    pub fn init(model: Unigram, allocator: Allocator) UnigramTokenizer {
        return UnigramTokenizer{
            .model = model,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UnigramTokenizer) void {
        self.model.deinit();
    }

    pub fn encode(self: *UnigramTokenizer, text: []const u8) ![]u32 {
        return self.model.encode(text, self.allocator);
    }

    pub fn decode(self: *UnigramTokenizer, ids: []const u32) ![]const u8 {
        return self.model.decode(ids, self.allocator);
    }

    pub fn saveToFile(self: *UnigramTokenizer, filename: []const u8) !void {
        // Write full JSON file compatible with HuggingFace tokenizers format
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        var buffered = std.io.bufferedWriter(file.writer());
        const writer = buffered.writer();

        // Header
        try writer.writeAll("{\"version\":\"1.0\",\"model\":{\"type\":\"Unigram\"");

        // Unknown token ID
        try writer.writeAll(",\"unk_id\":");
        if (self.model.unk_id) |unk_id| {
            try std.fmt.format(writer, "{d}", .{unk_id});
        } else {
            try writer.writeAll("null");
        }

        // Vocabulary array: [[token, score], ...]
        try writer.writeAll(",\"vocab\":[");

        for (self.model.vocab, 0..) |entry, i| {
            if (i > 0) {
                try writer.writeAll(",");
            }
            try writer.writeAll("[\"");

            // Escape JSON string
            for (entry.token) |c| {
                switch (c) {
                    '"' => try writer.writeAll("\\\""),
                    '\\' => try writer.writeAll("\\\\"),
                    '\n' => try writer.writeAll("\\n"),
                    '\r' => try writer.writeAll("\\r"),
                    '\t' => try writer.writeAll("\\t"),
                    else => {
                        if (c < 0x20) {
                            // Control character - use \u escape
                            try std.fmt.format(writer, "\\u{x:0>4}", .{c});
                        } else {
                            try writer.writeByte(c);
                        }
                    },
                }
            }

            try writer.writeAll("\",");
            // Write score with sufficient precision
            try std.fmt.format(writer, "{d:.10}", .{entry.score});
            try writer.writeAll("]");
        }

        try writer.writeAll("]}}");
        try buffered.flush();
    }

    /// Load from JSON file
    pub fn loadFromFile(allocator: Allocator, filename: []const u8) !UnigramTokenizer {
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 100 * 1024 * 1024); // 100MB max
        defer allocator.free(content);

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
        defer parsed.deinit();

        const root = parsed.value.object;
        const model_obj = root.get("model").?.object;

        // Parse unk_id
        const unk_id: ?usize = if (model_obj.get("unk_id")) |uid| switch (uid) {
            .integer => |i| @intCast(i),
            else => null,
        } else null;

        // Parse vocabulary
        const vocab_arr = model_obj.get("vocab").?.array;
        var vocab_list = try allocator.alloc(VocabEntry, vocab_arr.items.len);
        errdefer allocator.free(vocab_list);

        for (vocab_arr.items, 0..) |item, i| {
            const arr = item.array;
            const token_str = arr.items[0].string;
            const score = switch (arr.items[1]) {
                .float => |f| f,
                .integer => |int| @as(f64, @floatFromInt(int)),
                else => 0.0,
            };

            vocab_list[i] = .{
                .token = try allocator.dupe(u8, token_str),
                .score = score,
            };
        }

        const model = try Unigram.init(allocator, vocab_list, unk_id);

        // Free the temporary vocab_list (model made copies)
        for (vocab_list) |*entry| {
            allocator.free(entry.token);
        }
        allocator.free(vocab_list);

        return UnigramTokenizer{
            .model = model,
            .allocator = allocator,
        };
    }
};
