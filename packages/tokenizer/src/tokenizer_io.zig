const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;
const json_string = @import("json_string.zig");

/// Save tokenizer to JSON file (HuggingFace-compatible format)
pub fn saveToFile(self: *const Tokenizer, path: []const u8) !void {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(self.allocator);

    // JSON structure: {"version":"1.0","model":{"vocab":{...},"merges":[...]}}
    try buf.appendSlice(self.allocator, "{\"version\":\"1.0\",\"model\":{\"vocab\":{");

    // Write vocab mapping
    var vocab_it = self.vocab.iterator();
    var first = true;
    while (vocab_it.next()) |entry| {
        if (!first) try buf.appendSlice(self.allocator, ",");
        first = false;

        // Write JSON-escaped key
        try json_string.writeJSONString(entry.key_ptr.*, buf.writer(self.allocator));
        try std.fmt.format(buf.writer(self.allocator), ":{d}", .{entry.value_ptr.*});
    }

    try buf.appendSlice(self.allocator, "},\"merges\":[");

    // Write merges (convert token IDs back to strings)
    for (self.merges.items, 0..) |merge, i| {
        if (i > 0) try buf.appendSlice(self.allocator, ",");

        const left_str = self.vocab_r.get(merge.left) orelse "";
        const right_str = self.vocab_r.get(merge.right) orelse "";

        try buf.append(self.allocator, '[');
        try json_string.writeJSONString(left_str, buf.writer(self.allocator));
        try buf.append(self.allocator, ',');
        try json_string.writeJSONString(right_str, buf.writer(self.allocator));
        try buf.append(self.allocator, ']');
    }

    try buf.appendSlice(self.allocator, "]}}");


    // Write to file
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(buf.items);
}

/// Decode token IDs back to text
pub fn decode(self: *const Tokenizer, tokens: []const u32) ![]u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(self.allocator);

    for (tokens) |token_id| {
        if (self.vocab_r.get(token_id)) |token_str| {
            try result.appendSlice(self.allocator, token_str);
        } else if (token_id < 256) {
            // Raw byte
            try result.append(self.allocator, @intCast(token_id));
        }
    }

    // Avoid toOwnedSlice overhead - just dupe used portion
    const items = result.items[0..result.items.len];
    const owned = try self.allocator.dupe(u8, items);
    result.clearRetainingCapacity();
    return owned;
}
