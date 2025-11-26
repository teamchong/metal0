const std = @import("std");

/// Parse Anthropic API message format and extract text content
/// This is a simple string-based parser - no intermediate representation needed
pub const MessageParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MessageParser {
        return .{ .allocator = allocator };
    }

    /// Extract text from messages array
    /// Handles both string content and array of content blocks
    pub fn extractText(self: MessageParser, json_bytes: []const u8) ![]const u8 {
        // Find "messages":[{"content":
        const content_start = std.mem.indexOf(u8, json_bytes, "\"content\":") orelse return error.MissingContent;
        const after_content = json_bytes[content_start + 10 ..];

        // Skip whitespace
        var i: usize = 0;
        while (i < after_content.len and std.ascii.isWhitespace(after_content[i])) : (i += 1) {}

        if (i >= after_content.len) return error.MissingContent;

        // Check if string or array
        if (after_content[i] == '"') {
            // Simple string content
            return try self.parseStringValue(after_content[i..]);
        } else if (after_content[i] == '[') {
            // Array of content blocks - extract all text blocks
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
                // End of string
                return try result.toOwnedSlice(self.allocator);
            } else if (c == '\\' and i + 1 < data.len) {
                // Escape sequence
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

        var i: usize = 1; // Skip opening '['
        var found_text = false;

        while (i < data.len) {
            // Skip whitespace
            while (i < data.len and std.ascii.isWhitespace(data[i])) : (i += 1) {}
            if (i >= data.len) break;

            if (data[i] == ']') break;
            if (data[i] == ',') {
                i += 1;
                continue;
            }

            // Look for "type":"text"
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

            // Skip whitespace
            while (i < data.len and std.ascii.isWhitespace(data[i])) : (i += 1) {}

            if (i < data.len and data[i] == '"') {
                const type_value = try self.parseStringValue(data[i..]);
                defer self.allocator.free(type_value);

                if (std.mem.eql(u8, type_value, "text")) {
                    // Find "text": field
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

                    // Skip whitespace
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

    /// Rebuild JSON with modified content
    /// This constructs the JSON manually without std.json
    pub fn rebuildWithContent(
        self: MessageParser,
        json_bytes: []const u8,
        new_content_json: []const u8,
    ) ![]const u8 {
        // Find the content field and replace it
        const content_start = std.mem.indexOf(u8, json_bytes, "\"content\":") orelse return error.MissingContent;

        // Find the end of the content value
        // We need to handle both string and array values
        var i = content_start + 10; // Skip "content":

        // Skip whitespace
        while (i < json_bytes.len and std.ascii.isWhitespace(json_bytes[i])) : (i += 1) {}

        if (i >= json_bytes.len) return error.InvalidFormat;

        var content_end: usize = undefined;
        if (json_bytes[i] == '"') {
            // String value
            content_end = try self.findStringEnd(json_bytes, i);
        } else if (json_bytes[i] == '[') {
            // Array value
            content_end = try self.findArrayEnd(json_bytes, i);
        } else {
            return error.InvalidFormat;
        }

        // Build new JSON: before + new_content + after
        var result: std.ArrayList(u8) = .{};
        errdefer result.deinit(self.allocator);

        try result.appendSlice(self.allocator, json_bytes[0 .. content_start + 10]);
        try result.appendSlice(self.allocator, new_content_json);
        try result.appendSlice(self.allocator, json_bytes[content_end..]);

        return try result.toOwnedSlice(self.allocator);
    }

    fn findStringEnd(self: MessageParser, data: []const u8, start: usize) !usize {
        _ = self;
        var i = start + 1; // Skip opening quote
        while (i < data.len) : (i += 1) {
            if (data[i] == '"' and (i == start + 1 or data[i - 1] != '\\')) {
                return i + 1; // Include closing quote
            }
        }
        return error.UnterminatedString;
    }

    fn findArrayEnd(self: MessageParser, data: []const u8, start: usize) !usize {
        _ = self;
        var i = start + 1; // Skip opening bracket
        var depth: i32 = 1;

        while (i < data.len) : (i += 1) {
            const c = data[i];
            if (c == '"') {
                // Skip string contents
                i += 1;
                while (i < data.len) : (i += 1) {
                    if (data[i] == '"' and data[i - 1] != '\\') break;
                }
            } else if (c == '[') {
                depth += 1;
            } else if (c == ']') {
                depth -= 1;
                if (depth == 0) {
                    return i + 1; // Include closing bracket
                }
            }
        }

        return error.UnterminatedArray;
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

test "extract text from multiple text blocks in array" {
    const allocator = std.testing.allocator;
    const json =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":[{"type":"text","text":"First block. "},{"type":"text","text":"Second block. "},{"type":"text","text":"Third block."}]}]}
    ;

    const parser = MessageParser.init(allocator);
    const text = try parser.extractText(json);
    defer allocator.free(text);

    try std.testing.expectEqualStrings("First block. Second block. Third block.", text);
}

test "round-trip rebuild with modified content" {
    const allocator = std.testing.allocator;
    const json =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"Hello"}]}
    ;

    const parser = MessageParser.init(allocator);

    const new_content = "\"Modified\"";
    const rebuilt = try parser.rebuildWithContent(json, new_content);
    defer allocator.free(rebuilt);

    // Verify by extracting again
    const text = try parser.extractText(rebuilt);
    defer allocator.free(text);

    try std.testing.expectEqualStrings("Modified", text);
}

test "rebuild with array content" {
    const allocator = std.testing.allocator;
    const json =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"Hello"}]}
    ;

    const parser = MessageParser.init(allocator);

    const new_content = "[{\"type\":\"text\",\"text\":\"Modified\"}]";
    const rebuilt = try parser.rebuildWithContent(json, new_content);
    defer allocator.free(rebuilt);

    // Verify by extracting again
    const text = try parser.extractText(rebuilt);
    defer allocator.free(text);

    try std.testing.expectEqualStrings("Modified", text);
}
