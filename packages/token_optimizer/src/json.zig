const std = @import("std");

/// Parse Anthropic API message format and extract text content
pub const MessageParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MessageParser {
        return .{ .allocator = allocator };
    }

    /// Extract text from messages array
    pub fn extractText(self: MessageParser, json_bytes: []const u8) ![]const u8 {
        var parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            json_bytes,
            .{},
        );
        defer parsed.deinit();

        const root = parsed.value.object;

        // Navigate: messages[0].content (string or array)
        const messages = root.get("messages") orelse return error.MissingMessages;
        const messages_array = messages.array;
        if (messages_array.items.len == 0) return error.EmptyMessages;

        const first_message = messages_array.items[0].object;
        const content = first_message.get("content") orelse return error.MissingContent;

        // Content can be string or array of content blocks
        switch (content) {
            .string => |s| {
                return try self.allocator.dupe(u8, s);
            },
            .array => |arr| {
                // Extract text from first text block
                for (arr.items) |item| {
                    const block = item.object;
                    const block_type = block.get("type") orelse continue;
                    if (std.mem.eql(u8, block_type.string, "text")) {
                        const text = block.get("text") orelse continue;
                        return try self.allocator.dupe(u8, text.string);
                    }
                }
                return error.NoTextContent;
            },
            else => return error.InvalidContentFormat,
        }
    }

    /// Rebuild JSON with modified content
    pub fn rebuildWithContent(
        self: MessageParser,
        json_bytes: []const u8,
        new_content: std.json.Value,
    ) ![]const u8 {
        var parsed = try std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            json_bytes,
            .{},
        );
        defer parsed.deinit();

        // Clone the root object
        const root = try self.cloneValue(parsed.value);
        errdefer self.freeValue(root);

        var root_obj = root.object;

        // Modify messages[0].content
        var messages = root_obj.getPtr("messages") orelse return error.MissingMessages;
        var messages_array = &messages.array;
        if (messages_array.items.len == 0) return error.EmptyMessages;

        var first_message_obj = &messages_array.items[0].object;

        // Replace content
        const old_content = if (first_message_obj.getPtr("content")) |content_ptr| blk: {
            const old = content_ptr.*;
            content_ptr.* = new_content;
            break :blk old;
        } else null_blk: {
            try first_message_obj.put("content", new_content);
            break :null_blk null;
        };

        // Serialize back to JSON
        var output = std.ArrayList(u8){};
        errdefer output.deinit(self.allocator);

        try std.fmt.format(output.writer(self.allocator), "{f}", .{std.json.fmt(root, .{})});

        // Free the old content that was replaced
        if (old_content) |old| {
            self.freeValue(old);
        }

        // Free the cloned tree (but not the inserted new_content)
        self.freeValueShallow(root);

        return try output.toOwnedSlice(self.allocator);
    }

    fn cloneValue(self: MessageParser, value: std.json.Value) !std.json.Value {
        return switch (value) {
            .null => .null,
            .bool => |b| .{ .bool = b },
            .integer => |i| .{ .integer = i },
            .float => |f| .{ .float = f },
            .number_string => |s| .{ .number_string = try self.allocator.dupe(u8, s) },
            .string => |s| .{ .string = try self.allocator.dupe(u8, s) },
            .array => |arr| {
                var new_arr = std.json.Array.init(self.allocator);
                errdefer new_arr.deinit();

                for (arr.items) |item| {
                    try new_arr.append(try self.cloneValue(item));
                }
                return .{ .array = new_arr };
            },
            .object => |obj| {
                var new_obj = std.json.ObjectMap.init(self.allocator);
                errdefer new_obj.deinit();

                var it = obj.iterator();
                while (it.next()) |entry| {
                    const key = try self.allocator.dupe(u8, entry.key_ptr.*);
                    errdefer self.allocator.free(key);
                    try new_obj.put(key, try self.cloneValue(entry.value_ptr.*));
                }
                return .{ .object = new_obj };
            },
        };
    }

    fn freeValue(self: MessageParser, value: std.json.Value) void {
        switch (value) {
            .null, .bool, .integer, .float => {},
            .number_string => |s| self.allocator.free(s),
            .string => |s| self.allocator.free(s),
            .array => |*arr| {
                for (arr.items) |item| {
                    self.freeValue(item);
                }
                arr.deinit();
            },
            .object => |obj| {
                var mutable_obj = obj;
                var it = mutable_obj.iterator();
                while (it.next()) |entry| {
                    self.allocator.free(entry.key_ptr.*);
                    self.freeValue(entry.value_ptr.*);
                }
                mutable_obj.deinit();
            },
        }
    }

    fn freeValueShallow(self: MessageParser, value: std.json.Value) void {
        switch (value) {
            .null, .bool, .integer, .float => {},
            .number_string => |s| self.allocator.free(s),
            .string => |s| self.allocator.free(s),
            .array => |*arr| {
                arr.deinit();
            },
            .object => |obj| {
                var mutable_obj = obj;
                var it = mutable_obj.iterator();
                while (it.next()) |entry| {
                    self.allocator.free(entry.key_ptr.*);
                }
                mutable_obj.deinit();
            },
        }
    }
};

test "extract text from simple string content" {
    const allocator = std.testing.allocator;
    const json =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"Hello"}]}
    ;

    const parser = MessageParser.init(allocator);
    const text = try parser.extractText(json);
    defer allocator.free(text);

    try std.testing.expectEqualStrings("Hello", text);
}

test "extract text from array content" {
    const allocator = std.testing.allocator;
    const json =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":[{"type":"text","text":"Hello world"}]}]}
    ;

    const parser = MessageParser.init(allocator);
    const text = try parser.extractText(json);
    defer allocator.free(text);

    try std.testing.expectEqualStrings("Hello world", text);
}

test "round-trip rebuild with modified content" {
    const allocator = std.testing.allocator;
    const json =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"Hello"}]}
    ;

    const parser = MessageParser.init(allocator);

    // Create new content (simple string - must be allocated)
    const new_string = try allocator.dupe(u8, "Modified");
    const new_content = std.json.Value{ .string = new_string };

    const rebuilt = try parser.rebuildWithContent(json, new_content);
    defer allocator.free(rebuilt);

    // Parse the rebuilt JSON to verify
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        rebuilt,
        .{},
    );
    defer parsed.deinit();

    const root = parsed.value.object;
    const messages = root.get("messages").?.array;
    const content = messages.items[0].object.get("content").?.string;

    try std.testing.expectEqualStrings("Modified", content);
}

test "rebuild with image content block" {
    const allocator = std.testing.allocator;
    const json =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"Hello"}]}
    ;

    const parser = MessageParser.init(allocator);

    // Create new content (array with image block)
    // Note: ownership transferred to rebuildWithContent, no defer needed
    var content_array = std.json.Array.init(allocator);

    var image_block = std.json.ObjectMap.init(allocator);

    try image_block.put("type", .{ .string = try allocator.dupe(u8, "image") });

    var source_obj = std.json.ObjectMap.init(allocator);
    try source_obj.put("type", .{ .string = try allocator.dupe(u8, "base64") });
    try source_obj.put("media_type", .{ .string = try allocator.dupe(u8, "image/gif") });
    try source_obj.put("data", .{ .string = try allocator.dupe(u8, "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7") });

    try image_block.put("source", .{ .object = source_obj });
    try content_array.append(.{ .object = image_block });

    const new_content = std.json.Value{ .array = content_array };

    const rebuilt = try parser.rebuildWithContent(json, new_content);
    defer allocator.free(rebuilt);

    // Verify the structure
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        rebuilt,
        .{},
    );
    defer parsed.deinit();

    const root = parsed.value.object;
    const messages = root.get("messages").?.array;
    const content = messages.items[0].object.get("content").?.array;

    try std.testing.expect(content.items.len == 1);
    const block = content.items[0].object;
    try std.testing.expectEqualStrings("image", block.get("type").?.string);
}
