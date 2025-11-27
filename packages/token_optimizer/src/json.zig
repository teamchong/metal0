const std = @import("std");

/// Message role types
pub const Role = enum {
    user,
    assistant,
    system,
    tool_use,
    tool_result,

    pub fn fromString(s: []const u8) ?Role {
        if (std.mem.eql(u8, s, "user")) return .user;
        if (std.mem.eql(u8, s, "assistant")) return .assistant;
        if (std.mem.eql(u8, s, "system")) return .system;
        return null;
    }

    pub fn toString(self: Role) []const u8 {
        return switch (self) {
            .user => "user",
            .assistant => "assistant",
            .system => "system",
            .tool_use => "tool_use",
            .tool_result => "tool_result",
        };
    }
};

/// Content block types
pub const ContentType = enum {
    text,
    image,
    tool_use,
    tool_result,
};

/// A single content block within a message
pub const ContentBlock = struct {
    content_type: ContentType,
    text: ?[]const u8 = null, // For text content
    image_data: ?[]const u8 = null, // For image base64
    media_type: ?[]const u8 = null, // For image media type
    tool_use_id: ?[]const u8 = null, // For tool_use/tool_result
    tool_name: ?[]const u8 = null, // For tool_use
    tool_input: ?[]const u8 = null, // For tool_use (raw JSON)
    tool_content: ?[]const u8 = null, // For tool_result
};

/// A parsed message from the messages array
pub const Message = struct {
    role: Role,
    content: []ContentBlock,
    raw_json: []const u8, // Original JSON for this message (for pass-through)
};

/// Parsed request structure
pub const ParsedRequest = struct {
    model: []const u8,
    max_tokens: ?u32,
    messages: []Message,
    system_prompt: ?[]const u8,
    // Raw parts for reconstruction
    prefix_json: []const u8, // Everything before "messages":
    suffix_json: []const u8, // Everything after messages array
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ParsedRequest) void {
        for (self.messages) |msg| {
            self.allocator.free(msg.content);
        }
        self.allocator.free(self.messages);
    }
};

/// Parse Anthropic API message format
pub const MessageParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MessageParser {
        return .{ .allocator = allocator };
    }

    /// Parse full request JSON into structured format
    pub fn parseRequest(self: MessageParser, json_bytes: []const u8) !ParsedRequest {
        // Use std.json for reliable parsing
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_bytes, .{});
        defer parsed.deinit();

        const root = parsed.value.object;

        // Extract model
        const model = if (root.get("model")) |m| m.string else "unknown";

        // Extract max_tokens
        const max_tokens: ?u32 = if (root.get("max_tokens")) |mt|
            @intCast(mt.integer)
        else
            null;

        // Extract system prompt if present
        const system_prompt: ?[]const u8 = if (root.get("system")) |s|
            switch (s) {
                .string => |str| str,
                else => null,
            }
        else
            null;

        // Find messages array boundaries for reconstruction
        const messages_start = std.mem.indexOf(u8, json_bytes, "\"messages\"") orelse return error.MissingMessages;
        const colon_pos = std.mem.indexOfPos(u8, json_bytes, messages_start, ":") orelse return error.InvalidFormat;
        const array_start = std.mem.indexOfPos(u8, json_bytes, colon_pos, "[") orelse return error.InvalidFormat;
        const array_end = try self.findArrayEnd(json_bytes, array_start);

        const prefix_json = json_bytes[0 .. colon_pos + 1];
        const suffix_json = json_bytes[array_end..];

        // Parse messages
        const messages_value = root.get("messages") orelse return error.MissingMessages;
        const messages_array = messages_value.array;

        var messages = try self.allocator.alloc(Message, messages_array.items.len);
        errdefer self.allocator.free(messages);

        for (messages_array.items, 0..) |msg_value, i| {
            messages[i] = try self.parseMessage(msg_value);
        }

        return ParsedRequest{
            .model = try self.allocator.dupe(u8, model),
            .max_tokens = max_tokens,
            .messages = messages,
            .system_prompt = if (system_prompt) |s| try self.allocator.dupe(u8, s) else null,
            .prefix_json = try self.allocator.dupe(u8, prefix_json),
            .suffix_json = try self.allocator.dupe(u8, suffix_json),
            .allocator = self.allocator,
        };
    }

    fn parseMessage(self: MessageParser, msg_value: std.json.Value) !Message {
        const msg_obj = msg_value.object;

        // Get role
        const role_str = if (msg_obj.get("role")) |r| r.string else "user";
        const role = Role.fromString(role_str) orelse .user;

        // Parse content (can be string or array)
        const content_value = msg_obj.get("content") orelse return error.MissingContent;

        var content_blocks = std.ArrayList(ContentBlock){};
        defer content_blocks.deinit(self.allocator);

        switch (content_value) {
            .string => |text| {
                try content_blocks.append(self.allocator, .{
                    .content_type = .text,
                    .text = try self.allocator.dupe(u8, text),
                });
            },
            .array => |arr| {
                for (arr.items) |block| {
                    const block_obj = block.object;
                    const type_str = if (block_obj.get("type")) |t| t.string else "text";

                    if (std.mem.eql(u8, type_str, "text")) {
                        const text = if (block_obj.get("text")) |t| t.string else "";
                        try content_blocks.append(self.allocator, .{
                            .content_type = .text,
                            .text = try self.allocator.dupe(u8, text),
                        });
                    } else if (std.mem.eql(u8, type_str, "image")) {
                        const source = block_obj.get("source") orelse continue;
                        const source_obj = source.object;
                        const data = if (source_obj.get("data")) |d| d.string else "";
                        const media = if (source_obj.get("media_type")) |m| m.string else "image/png";
                        try content_blocks.append(self.allocator, .{
                            .content_type = .image,
                            .image_data = try self.allocator.dupe(u8, data),
                            .media_type = try self.allocator.dupe(u8, media),
                        });
                    } else if (std.mem.eql(u8, type_str, "tool_use")) {
                        const id = if (block_obj.get("id")) |v| v.string else "";
                        const name = if (block_obj.get("name")) |v| v.string else "";
                        // Serialize the input object back to JSON string
                        const input_json: []const u8 = if (block_obj.get("input")) |input_val|
                            std.json.Stringify.valueAlloc(self.allocator, input_val, .{}) catch "{}"
                        else
                            "{}";
                        try content_blocks.append(self.allocator, .{
                            .content_type = .tool_use,
                            .tool_use_id = try self.allocator.dupe(u8, id),
                            .tool_name = try self.allocator.dupe(u8, name),
                            .tool_input = input_json,
                        });
                    } else if (std.mem.eql(u8, type_str, "tool_result")) {
                        const id = if (block_obj.get("tool_use_id")) |v| v.string else "";
                        const content = if (block_obj.get("content")) |c| switch (c) {
                            .string => |s| s,
                            else => "",
                        } else "";
                        try content_blocks.append(self.allocator, .{
                            .content_type = .tool_result,
                            .tool_use_id = try self.allocator.dupe(u8, id),
                            .tool_content = try self.allocator.dupe(u8, content),
                        });
                    }
                }
            },
            else => {},
        }

        return Message{
            .role = role,
            .content = try content_blocks.toOwnedSlice(self.allocator),
            .raw_json = "", // Not used for now
        };
    }

    /// Rebuild request JSON with new messages content
    pub fn rebuildRequest(
        self: MessageParser,
        original: ParsedRequest,
        new_messages_json: []const u8,
    ) ![]const u8 {
        var result = std.ArrayList(u8){};
        errdefer result.deinit(self.allocator);

        try result.appendSlice(self.allocator, original.prefix_json);
        try result.appendSlice(self.allocator, new_messages_json);
        try result.appendSlice(self.allocator, original.suffix_json);

        return result.toOwnedSlice(self.allocator);
    }

    fn findArrayEnd(self: MessageParser, data: []const u8, start: usize) !usize {
        _ = self;
        var i = start + 1;
        var depth: i32 = 1;
        var in_string = false;

        while (i < data.len) : (i += 1) {
            const c = data[i];
            if (in_string) {
                if (c == '"' and data[i - 1] != '\\') {
                    in_string = false;
                }
            } else {
                if (c == '"') {
                    in_string = true;
                } else if (c == '[') {
                    depth += 1;
                } else if (c == ']') {
                    depth -= 1;
                    if (depth == 0) return i + 1;
                }
            }
        }
        return error.UnterminatedArray;
    }

    // Legacy API for backward compatibility
    pub fn extractText(self: MessageParser, json_bytes: []const u8) ![]const u8 {
        const content_start = std.mem.indexOf(u8, json_bytes, "\"content\":") orelse return error.MissingContent;
        const after_content = json_bytes[content_start + 10 ..];

        var i: usize = 0;
        while (i < after_content.len and std.ascii.isWhitespace(after_content[i])) : (i += 1) {}

        if (i >= after_content.len) return error.MissingContent;

        if (after_content[i] == '"') {
            return try self.parseStringValue(after_content[i..]);
        } else if (after_content[i] == '[') {
            return try self.extractTextFromArray(after_content[i..]);
        } else {
            return error.InvalidContentFormat;
        }
    }

    fn parseStringValue(self: MessageParser, data: []const u8) ![]const u8 {
        if (data[0] != '"') return error.InvalidFormat;

        var i: usize = 1;
        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(self.allocator);

        while (i < data.len) : (i += 1) {
            const c = data[i];
            if (c == '"') {
                return try result.toOwnedSlice(self.allocator);
            } else if (c == '\\' and i + 1 < data.len) {
                i += 1;
                const next = data[i];
                const unescaped: u8 = switch (next) {
                    'n' => '\n',
                    't' => '\t',
                    'r' => '\r',
                    '\\' => '\\',
                    '"' => '"',
                    else => next,
                };
                try result.append(self.allocator, unescaped);
            } else {
                try result.append(self.allocator, c);
            }
        }

        return error.UnterminatedString;
    }

    fn extractTextFromArray(self: MessageParser, data: []const u8) ![]const u8 {
        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(self.allocator);

        var i: usize = 1;
        var found_text = false;

        while (i < data.len) {
            while (i < data.len and std.ascii.isWhitespace(data[i])) : (i += 1) {}
            if (i >= data.len) break;

            if (data[i] == ']') break;
            if (data[i] == ',') {
                i += 1;
                continue;
            }

            const type_pos = std.mem.indexOf(u8, data[i..], "\"type\"") orelse {
                i += 1;
                continue;
            };
            i += type_pos;

            const value_start = std.mem.indexOf(u8, data[i..], ":") orelse {
                i += 1;
                continue;
            };
            i += value_start + 1;

            while (i < data.len and std.ascii.isWhitespace(data[i])) : (i += 1) {}

            if (i < data.len and data[i] == '"') {
                const type_value = try self.parseStringValue(data[i..]);
                defer self.allocator.free(type_value);

                if (std.mem.eql(u8, type_value, "text")) {
                    const text_field = std.mem.indexOf(u8, data[i..], "\"text\"") orelse {
                        i += 1;
                        continue;
                    };
                    i += text_field;

                    const text_value_start = std.mem.indexOf(u8, data[i..], ":") orelse {
                        i += 1;
                        continue;
                    };
                    i += text_value_start + 1;

                    while (i < data.len and std.ascii.isWhitespace(data[i])) : (i += 1) {}

                    if (i < data.len and data[i] == '"') {
                        const text_value = try self.parseStringValue(data[i..]);
                        defer self.allocator.free(text_value);

                        try result.appendSlice(self.allocator, text_value);
                        found_text = true;
                    }
                }
            }

            i += 1;
        }

        if (!found_text) return error.NoTextContent;

        return try result.toOwnedSlice(self.allocator);
    }

    pub fn rebuildWithContent(
        self: MessageParser,
        json_bytes: []const u8,
        new_content_json: []const u8,
    ) ![]const u8 {
        const content_start = std.mem.indexOf(u8, json_bytes, "\"content\":") orelse return error.MissingContent;
        var i = content_start + 10;
        while (i < json_bytes.len and std.ascii.isWhitespace(json_bytes[i])) : (i += 1) {}

        if (i >= json_bytes.len) return error.InvalidFormat;

        var content_end: usize = undefined;
        if (json_bytes[i] == '"') {
            content_end = try self.findStringEnd(json_bytes, i);
        } else if (json_bytes[i] == '[') {
            content_end = try self.findArrayEndLegacy(json_bytes, i);
        } else {
            return error.InvalidFormat;
        }

        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(self.allocator);

        try result.appendSlice(self.allocator, json_bytes[0 .. content_start + 10]);
        try result.appendSlice(self.allocator, new_content_json);
        try result.appendSlice(self.allocator, json_bytes[content_end..]);

        return try result.toOwnedSlice(self.allocator);
    }

    fn findStringEnd(self: MessageParser, data: []const u8, start: usize) !usize {
        _ = self;
        var i = start + 1;
        while (i < data.len) : (i += 1) {
            if (data[i] == '"' and (i == start + 1 or data[i - 1] != '\\')) {
                return i + 1;
            }
        }
        return error.UnterminatedString;
    }

    fn findArrayEndLegacy(self: MessageParser, data: []const u8, start: usize) !usize {
        _ = self;
        var i = start + 1;
        var depth: i32 = 1;

        while (i < data.len) : (i += 1) {
            const c = data[i];
            if (c == '"') {
                i += 1;
                while (i < data.len) : (i += 1) {
                    if (data[i] == '"' and data[i - 1] != '\\') break;
                }
            } else if (c == '[') {
                depth += 1;
            } else if (c == ']') {
                depth -= 1;
                if (depth == 0) {
                    return i + 1;
                }
            }
        }

        return error.UnterminatedArray;
    }
};

test "parse simple request" {
    const allocator = std.testing.allocator;
    const json =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"Hello"}]}
    ;

    var parser = MessageParser.init(allocator);
    var request = try parser.parseRequest(json);
    defer request.deinit();

    try std.testing.expectEqualStrings("claude-3-5-sonnet-20241022", request.model);
    try std.testing.expectEqual(@as(usize, 1), request.messages.len);
    try std.testing.expectEqual(Role.user, request.messages[0].role);
    try std.testing.expectEqual(@as(usize, 1), request.messages[0].content.len);
    try std.testing.expectEqualStrings("Hello", request.messages[0].content[0].text.?);
}
