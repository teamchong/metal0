const std = @import("std");
const json = @import("json.zig");
const render = @import("render.zig");
const gif = @import("gif.zig");

/// Text compression via image encoding
pub const TextCompressor = struct {
    allocator: std.mem.Allocator,
    parser: json.MessageParser,

    pub fn init(allocator: std.mem.Allocator) TextCompressor {
        return .{
            .allocator = allocator,
            .parser = json.MessageParser.init(allocator),
        };
    }

    /// Convert text to GIF image and encode as base64
    pub fn textToBase64Gif(self: TextCompressor, text: []const u8) ![]const u8 {
        // Step 1: Render text to pixel buffer (u8: 0=white, 1=black, 2=gray)
        var rendered = try render.renderText(self.allocator, text);
        defer rendered.deinit();

        // Step 2: Encode pixels as GIF (now supports 3 colors)
        const gif_bytes = try gif.encodeGif(self.allocator, rendered.pixels);
        defer self.allocator.free(gif_bytes);

        // Step 3: Base64 encode
        return try self.base64Encode(gif_bytes);
    }

    /// Process request: extract text, convert to images (Option 3: per-line with conditional newlines), rebuild JSON
    pub fn compressRequest(self: TextCompressor, request_json: []const u8) ![]const u8 {
        // Extract text from request
        const text = try self.parser.extractText(request_json);
        defer self.allocator.free(text);

        std.debug.print("Extracted text: {s}\n", .{text});

        // Split text by lines
        var lines: std.ArrayList([]const u8) = .{};
        defer lines.deinit(self.allocator);

        var iter = std.mem.splitScalar(u8, text, '\n');
        while (iter.next()) |line| {
            try lines.append(self.allocator, line);
        }

        // Build content array with mixed text/image blocks
        var content_array = std.json.Array.init(self.allocator);
        errdefer content_array.deinit();

        for (lines.items, 0..) |line, i| {
            const is_last_line = i == lines.items.len - 1;

            // Prepare text for rendering: add \n if not last line
            const render_text = if (!is_last_line) blk: {
                const with_newline = try self.allocator.alloc(u8, line.len + 1);
                @memcpy(with_newline[0..line.len], line);
                with_newline[line.len] = '\n';
                break :blk with_newline;
            } else blk: {
                break :blk line;
            };
            defer if (!is_last_line) self.allocator.free(render_text);

            // Cost calculation: estimate tokens (1 token ≈ 4 chars for text, 85 tokens/image for vision)
            const text_bytes = render_text.len;
            const text_tokens: i64 = @intCast(@max(1, text_bytes / 4));

            // Try compression
            const base64_gif = try self.textToBase64Gif(render_text);
            defer self.allocator.free(base64_gif);

            // Decode GIF to get actual pixel dimensions
            const decoder = std.base64.standard.Decoder;
            const gif_bytes_size = try decoder.calcSizeForSlice(base64_gif);
            const gif_bytes = try self.allocator.alloc(u8, gif_bytes_size);
            defer self.allocator.free(gif_bytes);
            try decoder.decode(gif_bytes, base64_gif);

            // Extract dimensions from GIF header (bytes 6-9: width/height as u16 little-endian)
            const gif_width = @as(u16, gif_bytes[6]) | (@as(u16, gif_bytes[7]) << 8);
            const gif_height = @as(u16, gif_bytes[8]) | (@as(u16, gif_bytes[9]) << 8);
            const pixels = @as(i64, gif_width) * @as(i64, gif_height);

            // Image cost: base64 bytes + 85 tokens per 1024×1024 block (scaled)
            const image_bytes = base64_gif.len;
            const blocks = @max(1, @divFloor(pixels, 1024 * 1024));
            const image_tokens: i64 = @intCast(@divFloor(image_bytes, 4) + (blocks * 85));

            // Only compress if saves >20% tokens
            const savings = if (text_tokens > 0) @divTrunc(100 * (text_tokens - image_tokens), text_tokens) else 0;

            // Comprehensive metrics logging
            std.debug.print("Line {d}: text={d}B/{d}tok → image={d}B/{d}tok ({d}×{d}px={d}px) | ", .{
                i,
                text_bytes,
                text_tokens,
                image_bytes,
                image_tokens,
                gif_width,
                gif_height,
                pixels,
            });

            if (savings > 20 and image_tokens < text_tokens) {
                // Use image block
                std.debug.print("COMPRESS {d}% savings\n", .{savings});

                var image_block = std.json.ObjectMap.init(self.allocator);
                errdefer image_block.deinit();

                const type_key = try self.allocator.dupe(u8, "type");
                errdefer self.allocator.free(type_key);
                const type_value = try self.allocator.dupe(u8, "image");
                errdefer self.allocator.free(type_value);
                try image_block.put(type_key, .{ .string = type_value });

                var source_obj = std.json.ObjectMap.init(self.allocator);
                errdefer source_obj.deinit();

                const source_type_key = try self.allocator.dupe(u8, "type");
                errdefer self.allocator.free(source_type_key);
                const source_type_value = try self.allocator.dupe(u8, "base64");
                errdefer self.allocator.free(source_type_value);
                try source_obj.put(source_type_key, .{ .string = source_type_value });

                const media_key = try self.allocator.dupe(u8, "media_type");
                errdefer self.allocator.free(media_key);
                const media_value = try self.allocator.dupe(u8, "image/gif");
                errdefer self.allocator.free(media_value);
                try source_obj.put(media_key, .{ .string = media_value });

                const data_key = try self.allocator.dupe(u8, "data");
                errdefer self.allocator.free(data_key);
                const data_copy = try self.allocator.dupe(u8, base64_gif);
                errdefer self.allocator.free(data_copy);
                try source_obj.put(data_key, .{ .string = data_copy });

                const source_key = try self.allocator.dupe(u8, "source");
                errdefer self.allocator.free(source_key);
                try image_block.put(source_key, .{ .object = source_obj });

                try content_array.append(.{ .object = image_block });
            } else {
                // Keep as text
                std.debug.print("KEEP {d}% not worth it\n", .{savings});

                var text_block = std.json.ObjectMap.init(self.allocator);
                errdefer text_block.deinit();

                const type_key = try self.allocator.dupe(u8, "type");
                errdefer self.allocator.free(type_key);
                const type_value = try self.allocator.dupe(u8, "text");
                errdefer self.allocator.free(type_value);
                try text_block.put(type_key, .{ .string = type_value });

                const text_key = try self.allocator.dupe(u8, "text");
                errdefer self.allocator.free(text_key);
                const text_copy = try self.allocator.dupe(u8, render_text);
                errdefer self.allocator.free(text_copy);
                try text_block.put(text_key, .{ .string = text_copy });

                try content_array.append(.{ .object = text_block });
            }
        }

        const new_content = std.json.Value{ .array = content_array };

        // Rebuild JSON with new content
        return try self.parser.rebuildWithContent(request_json, new_content);
    }

    fn base64Encode(self: TextCompressor, data: []const u8) ![]const u8 {
        const encoder = std.base64.standard.Encoder;
        const encoded_len = encoder.calcSize(data.len);

        const result = try self.allocator.alloc(u8, encoded_len);
        const written = encoder.encode(result, data);

        return result[0..written.len];
    }
};

test "compress simple request" {
    const allocator = std.testing.allocator;
    const request =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"Hi"}]}
    ;

    const compressor = TextCompressor.init(allocator);
    const compressed = try compressor.compressRequest(request);
    defer allocator.free(compressed);

    // Verify it's valid JSON
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        compressed,
        .{},
    );
    defer parsed.deinit();

    // Verify structure
    const root = parsed.value.object;
    const messages = root.get("messages").?.array;
    const content = messages.items[0].object.get("content").?.array;

    try std.testing.expect(content.items.len == 1);
    const block = content.items[0].object;
    try std.testing.expectEqualStrings("image", block.get("type").?.string);

    const source = block.get("source").?.object;
    try std.testing.expectEqualStrings("base64", source.get("type").?.string);
    try std.testing.expectEqualStrings("image/gif", source.get("media_type").?.string);

    // Verify data is base64 encoded GIF
    const data = source.get("data").?.string;
    try std.testing.expect(data.len > 0);
}

test "text to base64 gif pipeline" {
    const allocator = std.testing.allocator;
    const compressor = TextCompressor.init(allocator);

    const result = try compressor.textToBase64Gif("Hello");
    defer allocator.free(result);

    // Should produce valid base64
    try std.testing.expect(result.len > 0);

    // Decode to verify it's valid
    const decoder = std.base64.standard.Decoder;
    const decoded_size = try decoder.calcSizeForSlice(result);
    const decoded = try allocator.alloc(u8, decoded_size);
    defer allocator.free(decoded);

    try decoder.decode(decoded, result);

    // Should start with GIF header
    try std.testing.expect(decoded.len >= 6);
    try std.testing.expectEqualStrings("GIF89a", decoded[0..6]);
}
