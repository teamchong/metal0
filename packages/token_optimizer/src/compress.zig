const std = @import("std");
const json = @import("json.zig");
const render = @import("render.zig");
const gif = @import("gif_zigimg.zig");

/// Replace long base64 strings with compact summaries for logging
fn compactifyBase64(allocator: std.mem.Allocator, json_str: []const u8) ![]const u8 {
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < json_str.len) {
        // Find "data":"
        const data_start = std.mem.indexOfPos(u8, json_str, i, "\"data\":\"");
        if (data_start == null) {
            try result.appendSlice(allocator, json_str[i..]);
            break;
        }

        // Append everything before "data":"
        try result.appendSlice(allocator, json_str[i .. data_start.? + 8]);

        // Find end quote
        const data_value_start = data_start.? + 8;
        const end_quote = std.mem.indexOfPos(u8, json_str, data_value_start, "\"");
        if (end_quote == null) {
            try result.appendSlice(allocator, json_str[data_value_start..]);
            break;
        }

        // Calculate base64 length
        const b64_len = end_quote.? - data_value_start;

        // Add summary: <widthxheight,len=X,bytes=Y>
        const summary = try std.fmt.allocPrint(allocator, "<base64 {d} chars>", .{b64_len});
        defer allocator.free(summary);
        try result.appendSlice(allocator, summary);

        i = end_quote.?;
    }

    return try result.toOwnedSlice(allocator);
}

/// Cost analysis for a single line (with cached GIF)
const LineCost = struct {
    text_tokens: i64,
    image_tokens: i64,
    text_bytes: usize,
    image_bytes: usize,
    pixels: i64,
    gif_base64: []const u8, // Cached for reuse
};

/// Text compression via image encoding
pub const TextCompressor = struct {
    allocator: std.mem.Allocator,
    parser: json.MessageParser,
    enabled: bool,

    pub fn init(allocator: std.mem.Allocator, enabled: bool) TextCompressor {
        return .{
            .allocator = allocator,
            .parser = json.MessageParser.init(allocator),
            .enabled = enabled,
        };
    }

    /// Convert text to GIF image and encode as base64
    pub fn textToBase64Gif(self: TextCompressor, text: []const u8) ![]const u8 {
        // Step 1: Render text to pixel buffer (u8: 0=white, 1=black, 2=gray)
        var rendered = try render.renderText(self.allocator, text);
        defer rendered.deinit();

        if (rendered.pixels.len == 0) {
            std.debug.print("ERROR: Rendered pixels is empty for text (len={d}): {s}\n", .{text.len, text[0..@min(100, text.len)]});
            return error.EmptyRender;
        }

        // Step 2: Encode pixels as GIF (now supports 3 colors)
        const gif_bytes = try gif.encodeGif(self.allocator, rendered.pixels);
        defer self.allocator.free(gif_bytes);

        if (gif_bytes.len == 0) {
            std.debug.print("ERROR: GIF encoder returned 0 bytes for text (len={d}, pixels={}x{}): {s}\n", .{
                text.len,
                rendered.width,
                rendered.height,
                text[0..@min(100, text.len)]
            });
            return error.EmptyGif;
        }

        // Step 3: Base64 encode
        return try self.base64Encode(gif_bytes);
    }

    /// Process request: extract text, calculate totals, decide compression for whole message
    pub fn compressRequest(self: TextCompressor, request_json: []const u8) ![]const u8 {
        // If compression disabled, return original unchanged
        if (!self.enabled) {
            std.debug.print("Text-to-image compression DISABLED - forwarding original request\n", .{});
            return try self.allocator.dupe(u8, request_json);
        }

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

        // Step 1: Group lines into batches (Anthropic limit: 100 images per request)
        const MAX_IMAGES = 100;
        const lines_per_batch: usize = if (lines.items.len > MAX_IMAGES)
            (lines.items.len + MAX_IMAGES - 1) / MAX_IMAGES // ceil(lines / MAX_IMAGES)
        else
            1;

        const num_batches = (lines.items.len + lines_per_batch - 1) / lines_per_batch;

        std.debug.print("Lines: {d}, Batches: {d} ({d} lines/batch)\n", .{
            lines.items.len,
            num_batches,
            lines_per_batch,
        });

        // Step 2: Calculate token costs for ALL batches
        var batch_costs = try self.allocator.alloc(LineCost, num_batches);
        defer self.allocator.free(batch_costs);

        var total_text_tokens: i64 = 0;
        var total_image_tokens: i64 = 0;

        for (0..num_batches) |batch_idx| {
            const start_line = batch_idx * lines_per_batch;
            const end_line = @min(start_line + lines_per_batch, lines.items.len);

            // Combine all lines in this batch into one text block
            var batch_text = std.ArrayList(u8){};
            defer batch_text.deinit(self.allocator);

            for (start_line..end_line) |line_idx| {
                try batch_text.appendSlice(self.allocator, lines.items[line_idx]);
                if (line_idx < end_line - 1 or end_line < lines.items.len) {
                    try batch_text.append(self.allocator, '\n');
                }
            }

            const render_text = batch_text.items;

            // Calculate text tokens (approximate formula: 1 token ≈ 4 chars)
            // Good enough for image vs text comparison (10x+ difference)
            const text_tokens: i64 = @intCast(@max(1, render_text.len / 4));

            // Calculate image tokens: render and get dimensions
            const base64_gif = self.textToBase64Gif(render_text) catch |err| {
                std.debug.print("ERROR: Failed to encode batch {d}/{d} (text len={d}): {any}\n", .{
                    batch_idx + 1,
                    num_batches,
                    render_text.len,
                    err,
                });
                std.debug.print("Batch text preview: {s}\n", .{render_text[0..@min(100, render_text.len)]});
                return err;
            };
            errdefer self.allocator.free(base64_gif); // Free on error

            // Decode GIF to get actual pixel dimensions
            const decoder = std.base64.standard.Decoder;
            // Decode base64 to get GIF bytes
            if (base64_gif.len == 0) {
                std.debug.print("ERROR: Empty GIF for batch {d}\n", .{batch_idx});
                return error.EmptyGif;
            }

            const gif_bytes_size = try decoder.calcSizeForSlice(base64_gif);
            const gif_bytes = try self.allocator.alloc(u8, gif_bytes_size);
            defer self.allocator.free(gif_bytes);
            try decoder.decode(gif_bytes, base64_gif);

            // Extract dimensions from GIF header (GIF header is at least 10 bytes)
            if (gif_bytes.len < 10) {
                std.debug.print("ERROR: GIF too small ({d} bytes) for batch {d}\n", .{gif_bytes.len, batch_idx});
                return error.InvalidGif;
            }

            const gif_width = @as(u16, gif_bytes[6]) | (@as(u16, gif_bytes[7]) << 8);
            const gif_height = @as(u16, gif_bytes[8]) | (@as(u16, gif_bytes[9]) << 8);
            const pixels = @as(i64, gif_width) * @as(i64, gif_height);

            // Image cost: Anthropic formula is pixels / 750
            const image_tokens: i64 = @intCast(@max(1, @divFloor(pixels, 750)));

            // Store costs (cache GIF for reuse)
            batch_costs[batch_idx] = .{
                .text_tokens = text_tokens,
                .image_tokens = image_tokens,
                .text_bytes = render_text.len,
                .image_bytes = base64_gif.len,
                .pixels = pixels,
                .gif_base64 = base64_gif, // Don't defer! We'll free later
            };

            total_text_tokens += text_tokens;
            total_image_tokens += image_tokens;

            std.debug.print("Batch {d}: text={d}B/{d}tok → image={d}B/{d}tok ({d}px)\n", .{
                batch_idx,
                render_text.len,
                text_tokens,
                base64_gif.len,
                image_tokens,
                pixels,
            });
        }

        // Step 3: Compare totals and decide for ENTIRE message
        const savings = if (total_text_tokens > 0)
            @divTrunc(100 * (total_text_tokens - total_image_tokens), total_text_tokens)
        else
            0;

        const use_compression = savings > 20 and total_image_tokens < total_text_tokens;

        std.debug.print("\n=== DECISION ===\n", .{});
        std.debug.print("Total: text={d}tok vs image={d}tok | {d}% savings\n", .{
            total_text_tokens,
            total_image_tokens,
            savings,
        });
        std.debug.print("Decision: {s}\n\n", .{if (use_compression) "COMPRESS ALL" else "KEEP ALL AS TEXT"});

        // Step 4: Build content array based on decision
        var content_json: std.ArrayList(u8) = .{};
        errdefer content_json.deinit(self.allocator);

        try content_json.append(self.allocator, '[');

        if (use_compression) {
            // Use batched images (one image per batch)
            for (batch_costs, 0..) |cost, batch_idx| {
                if (batch_idx > 0) {
                    try content_json.append(self.allocator, ',');
                }

                try content_json.appendSlice(self.allocator, "{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":\"image/gif\",\"data\":\"");
                try content_json.appendSlice(self.allocator, cost.gif_base64);
                try content_json.appendSlice(self.allocator, "\"}}");
            }
        } else {
            // Keep as text (single text block with all lines)
            try content_json.appendSlice(self.allocator, "{\"type\":\"text\",\"text\":\"");
            try self.appendEscapedJson(text, &content_json);
            try content_json.appendSlice(self.allocator, "\"}");
        }

        try content_json.append(self.allocator, ']');

        // Free cached GIFs
        for (batch_costs) |cost| {
            self.allocator.free(cost.gif_base64);
        }

        const content_json_slice = try content_json.toOwnedSlice(self.allocator);
        defer self.allocator.free(content_json_slice);

        std.debug.print("\n=== JSON DEBUG ===\n", .{});
        std.debug.print("ORIGINAL REQUEST ({d} bytes):\n{s}\n", .{ request_json.len, request_json });

        // Compact log: replace long base64 with summary
        const compact = compactifyBase64(self.allocator, content_json_slice) catch content_json_slice;
        defer if (compact.ptr != content_json_slice.ptr) self.allocator.free(compact);
        std.debug.print("\nNEW CONTENT ARRAY ({d} bytes):\n{s}\n", .{ content_json_slice.len, compact });

        // Rebuild JSON with new content
        const rebuilt = try self.parser.rebuildWithContent(request_json, content_json_slice);

        // Compact log: replace long base64 with summary
        const compact_rebuilt = compactifyBase64(self.allocator, rebuilt) catch rebuilt;
        defer if (compact_rebuilt.ptr != rebuilt.ptr) self.allocator.free(compact_rebuilt);
        std.debug.print("\nREBUILT REQUEST ({d} bytes):\n{s}\n", .{ rebuilt.len, compact_rebuilt });
        std.debug.print("=== END JSON DEBUG ===\n\n", .{});

        // Validate rebuilt JSON
        const parsed = std.json.parseFromSlice(
            std.json.Value,
            self.allocator,
            rebuilt,
            .{},
        ) catch |err| {
            std.debug.print("ERROR: Rebuilt JSON is INVALID: {any}\n", .{err});
            return err;
        };
        parsed.deinit();
        std.debug.print("Validation: Rebuilt JSON is VALID\n", .{});

        return rebuilt;
    }

    /// Helper to escape JSON string values
    fn appendEscapedJson(self: TextCompressor, text: []const u8, buffer: *std.ArrayList(u8)) !void {
        for (text) |c| {
            switch (c) {
                '"' => try buffer.appendSlice(self.allocator, "\\\""),
                '\\' => try buffer.appendSlice(self.allocator, "\\\\"),
                '\n' => try buffer.appendSlice(self.allocator, "\\n"),
                '\r' => try buffer.appendSlice(self.allocator, "\\r"),
                '\t' => try buffer.appendSlice(self.allocator, "\\t"),
                else => try buffer.append(self.allocator, c),
            }
        }
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

    // Verify it's valid JSON - short text like "Hi" stays as text (not worth compressing)
    const parser = json.MessageParser.init(allocator);
    const text = try parser.extractText(compressed);
    defer allocator.free(text);

    try std.testing.expectEqualStrings("Hi", text);
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
