const std = @import("std");
const api_types = @import("api_types.zig");
const render = @import("render.zig");
const png = @import("png_zigimg.zig");

/// Max chars per image chunk (fits in ~1024x1024 at scale 2)
/// 1024 / 2 / 6 (char width) ≈ 85 chars per line
/// 1024 / 2 / 7 (char height) ≈ 73 lines
/// 85 * 73 ≈ 6200 chars per image
const MAX_CHARS_PER_IMAGE: usize = 6000;

/// Image info struct
const ImageInfo = struct {
    data: []const u8,
    width: usize,
    height: usize,
};

/// Text compression via image encoding
pub const TextCompressor = struct {
    allocator: std.mem.Allocator,
    parser: api_types.MessageParser,
    enabled: bool,

    pub fn init(allocator: std.mem.Allocator, enabled: bool) TextCompressor {
        return .{
            .allocator = allocator,
            .parser = api_types.MessageParser.init(allocator),
            .enabled = enabled,
        };
    }

    /// Convert text to PNG image and encode as base64
    /// Each character is colored according to its role
    fn textToBase64Png(self: TextCompressor, text: []const u8, roles: []const api_types.Role) !ImageInfo {
        var rendered = try render.renderTextWithRoles(self.allocator, text, roles);
        defer rendered.deinit();

        if (rendered.pixels.len == 0) {
            return error.EmptyRender;
        }

        const png_bytes = try png.encodePng(self.allocator, rendered.pixels);
        defer self.allocator.free(png_bytes);

        if (png_bytes.len == 0) {
            return error.EmptyPng;
        }

        return ImageInfo{
            .data = try self.base64Encode(png_bytes),
            .width = rendered.width,
            .height = rendered.height,
        };
    }

    /// Estimate token count (chars/4 approximation)
    /// TODO: Integrate BPE tokenizer for accurate counts
    fn countTextTokens(self: TextCompressor, text: []const u8) usize {
        _ = self;
        return @max(1, text.len / 4);
    }

    /// Calculate image tokens from dimensions (Anthropic formula: pixels/750)
    fn calculateImageTokens(width: usize, height: usize) usize {
        const pixels = width * height;
        return @max(1, pixels / 750);
    }

    /// Chunk of text with corresponding roles
    const TextChunk = struct {
        text: []const u8,
        roles: []const api_types.Role,
    };

    /// Split text into chunks that fit in MAX_CHARS_PER_IMAGE
    fn splitIntoChunks(self: TextCompressor, text: []const u8, roles: []const api_types.Role) ![]TextChunk {
        var chunks = std.ArrayList(TextChunk){};
        errdefer chunks.deinit(self.allocator);

        var pos: usize = 0;
        while (pos < text.len) {
            const chunk_len = @min(text.len - pos, MAX_CHARS_PER_IMAGE);
            try chunks.append(self.allocator, .{
                .text = text[pos .. pos + chunk_len],
                .roles = roles[pos .. pos + chunk_len],
            });
            pos += chunk_len;
        }

        return chunks.toOwnedSlice(self.allocator);
    }

    /// Process request: compress old messages into images
    pub fn compressRequest(self: TextCompressor, request_json: []const u8) ![]const u8 {
        if (!self.enabled) {
            std.debug.print("[COMPRESS] Disabled\n", .{});
            return try self.allocator.dupe(u8, request_json);
        }

        // Parse request
        var request = self.parser.parseRequest(request_json) catch |err| {
            std.debug.print("[COMPRESS] Parse error: {any}\n", .{err});
            return try self.allocator.dupe(u8, request_json);
        };
        defer request.deinit();

        const msg_count = request.messages.len;
        if (msg_count == 0) {
            return try self.allocator.dupe(u8, request_json);
        }

        std.debug.print("[COMPRESS] Messages: {d}\n", .{msg_count});

        // New compression logic:
        // 1. Tool pairs (tool_use + matching tool_result) are atomic - keep as-is
        // 2. User messages with images - keep as-is (can't compress images)
        // 3. Last user message + anything after - keep as-is
        // 4. Everything else (regular user/assistant text) - compress into images
        //
        // This allows compressing chat between tool calls while preserving tool structure.

        var can_compress = try self.allocator.alloc(bool, msg_count);
        defer self.allocator.free(can_compress);
        @memset(can_compress, true); // Default: compress everything

        // Step 1: Find last user message - never compress it or anything after
        var last_user_idx: ?usize = null;
        var i = msg_count;
        while (i > 0) {
            i -= 1;
            if (request.messages[i].role == .user) {
                last_user_idx = i;
                break;
            }
        }
        if (last_user_idx) |idx| {
            can_compress[idx] = false;
            for (idx + 1..msg_count) |j| {
                can_compress[j] = false;
            }
        }

        // Step 2: Mark tool_use and tool_result messages as non-compressible
        // Tool pairs must stay intact for API validity
        var tool_msg_count: usize = 0;
        for (request.messages, 0..) |msg, idx| {
            for (msg.content) |block| {
                if (block.content_type == .tool_use or block.content_type == .tool_result or block.content_type == .thinking) {
                    can_compress[idx] = false;
                    tool_msg_count += 1;
                    break;
                }
            }
        }

        // Step 3: Mark user messages with images as non-compressible
        var image_msg_count: usize = 0;
        for (request.messages, 0..) |msg, idx| {
            if (msg.role != .user) continue;
            for (msg.content) |block| {
                if (block.content_type == .image) {
                    can_compress[idx] = false;
                    image_msg_count += 1;
                    break;
                }
            }
        }

        // Count compressible messages
        var compress_count: usize = 0;
        for (can_compress) |c| {
            if (c) compress_count += 1;
        }

        std.debug.print("[COMPRESS] Analysis: {d} total, {d} tool, {d} image, {d} compressible\n", .{
            msg_count,
            tool_msg_count,
            image_msg_count,
            compress_count,
        });

        // Log which messages are compressed vs preserved
        std.debug.print("[COMPRESS] Message breakdown:\n", .{});
        for (request.messages, 0..) |msg, idx| {
            var has_tool_use = false;
            var has_tool_result = false;
            var has_image = false;
            var has_thinking = false;
            for (msg.content) |block| {
                if (block.content_type == .tool_use) has_tool_use = true;
                if (block.content_type == .tool_result) has_tool_result = true;
                if (block.content_type == .image) has_image = true;
                if (block.content_type == .thinking) has_thinking = true;
            }
            const tag: []const u8 = if (has_thinking) " [thinking]" else if (has_tool_use) " [tool_use]" else if (has_tool_result) " [tool_result]" else if (has_image) " [image]" else "";
            std.debug.print("  [{d}] {s}: {s}{s}\n", .{
                idx,
                if (can_compress[idx]) "COMPRESS" else "KEEP    ",
                msg.role.toString(),
                tag,
            });
        }

        // Collect text from compressible messages with per-character role tracking
        var text_to_compress = std.ArrayList(u8){};
        defer text_to_compress.deinit(self.allocator);

        var char_roles = std.ArrayList(api_types.Role){};
        defer char_roles.deinit(self.allocator);

        for (request.messages, 0..) |msg, idx| {
            if (!can_compress[idx]) continue;

            const role_prefix = switch (msg.role) {
                .user => "[USER] ",
                .assistant => "[ASST] ",
                .system => "[SYS] ",
                .tool_use => "[TOOL] ",
                .tool_result => "[RESULT] ",
            };

            // Add prefix with message role color
            for (role_prefix) |_| {
                try char_roles.append(self.allocator, msg.role);
            }
            try text_to_compress.appendSlice(self.allocator, role_prefix);

            // Add message content with message role color
            for (msg.content) |block| {
                if (block.text) |text| {
                    for (text) |_| {
                        try char_roles.append(self.allocator, msg.role);
                    }
                    try text_to_compress.appendSlice(self.allocator, text);
                }
            }

            // Add separator (use same role for continuity)
            try text_to_compress.appendSlice(self.allocator, " ");
            try char_roles.append(self.allocator, msg.role);
        }

        // If nothing to compress, return original
        if (text_to_compress.items.len == 0 or compress_count == 0) {
            std.debug.print("[COMPRESS] Nothing to compress (tool pairs preserved)\n", .{});
            return try self.allocator.dupe(u8, request_json);
        }

        std.debug.print("[COMPRESS] Compressible: {d}/{d} messages\n", .{ compress_count, msg_count });

        const total_text_tokens = countTextTokens(self, text_to_compress.items);

        // Split into chunks that fit in 1024x1024 images
        const chunks = try self.splitIntoChunks(text_to_compress.items, char_roles.items);
        defer self.allocator.free(chunks);

        std.debug.print("[COMPRESS] Text: {d}B ({d}tok) → {d} images\n", .{
            text_to_compress.items.len,
            total_text_tokens,
            chunks.len,
        });

        // Generate images for each chunk
        var images = std.ArrayList(ImageInfo){};
        defer {
            for (images.items) |img| {
                self.allocator.free(img.data);
            }
            images.deinit(self.allocator);
        }

        var total_image_tokens: usize = 0;

        for (chunks, 0..) |chunk, chunk_idx| {
            const img = self.textToBase64Png(chunk.text, chunk.roles) catch |err| {
                std.debug.print("[COMPRESS] PNG error on chunk {d}: {any}\n", .{ chunk_idx, err });
                return try self.allocator.dupe(u8, request_json);
            };

            const img_tokens = calculateImageTokens(img.width, img.height);
            total_image_tokens += img_tokens;

            std.debug.print("[COMPRESS]   Image {d}: {d}x{d} ({d}tok)\n", .{
                chunk_idx + 1,
                img.width,
                img.height,
                img_tokens,
            });

            // Save to /tmp for debugging
            var path_buf: [64]u8 = undefined;
            const path = std.fmt.bufPrint(&path_buf, "/tmp/compress_img_{d}.png", .{chunk_idx + 1}) catch "/tmp/compress_img.png";
            const decoder = std.base64.standard.Decoder;
            const png_size = decoder.calcSizeForSlice(img.data) catch 0;
            if (png_size > 0) {
                const png_bytes = self.allocator.alloc(u8, png_size) catch null;
                if (png_bytes) |bytes| {
                    defer self.allocator.free(bytes);
                    decoder.decode(bytes, img.data) catch {};
                    const file = std.fs.createFileAbsolute(path, .{}) catch null;
                    if (file) |f| {
                        defer f.close();
                        f.writeAll(bytes) catch {};
                        std.debug.print("[COMPRESS]   Saved: {s}\n", .{path});
                    }
                }
            }

            try images.append(self.allocator, img);
        }

        // Decision: only compress if we save tokens
        // Account for instruction text overhead (~50 tokens for before+after instructions)
        const instruction_overhead: usize = 50;
        const total_compressed_tokens = total_image_tokens + instruction_overhead;
        const savings = @as(i64, @intCast(total_text_tokens)) - @as(i64, @intCast(total_compressed_tokens));
        const savings_pct = if (total_text_tokens > 0)
            @as(f64, @floatFromInt(savings)) / @as(f64, @floatFromInt(total_text_tokens)) * 100.0
        else
            0.0;

        std.debug.print("[COMPRESS] Total: {d}tok text → {d}tok compressed ({d:.1}% {s})\n", .{
            total_text_tokens,
            total_compressed_tokens,
            @abs(savings_pct),
            if (savings > 0) "saved" else "added",
        });

        if (savings <= 0) {
            std.debug.print("[COMPRESS] No savings - keeping original\n", .{});
            return try self.allocator.dupe(u8, request_json);
        }

        // Build new messages array
        var new_messages = std.ArrayList(u8){};
        defer new_messages.deinit(self.allocator);

        try new_messages.append(self.allocator, '[');

        // 1. Single user message with: images first, then instruction text
        try new_messages.appendSlice(self.allocator, "{\"role\":\"user\",\"content\":[");

        // Sandwich pattern: instruction BEFORE + images + instruction AFTER
        // This helps LLM understand context before and after processing images

        // BEFORE instruction
        var before_buf: [256]u8 = undefined;
        const before_instruction = try std.fmt.bufPrint(&before_buf,
            \\Read {d} images below. Format: | = newline, > = tab. Colors: blue=[USER], green=[ASST], yellow=[SYS], red=[TOOL], purple=[RESULT]
        , .{images.items.len});

        try new_messages.appendSlice(self.allocator, "{\"type\":\"text\",\"text\":\"");
        try self.appendEscapedJson(before_instruction, &new_messages);
        try new_messages.appendSlice(self.allocator, "\"}");

        // Add all images
        for (images.items) |img| {
            try new_messages.append(self.allocator, ',');
            try new_messages.appendSlice(self.allocator, "{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":\"image/png\",\"data\":\"");
            try new_messages.appendSlice(self.allocator, img.data);
            try new_messages.appendSlice(self.allocator, "\"}}");
        }

        // AFTER instruction
        try new_messages.append(self.allocator, ',');
        try new_messages.appendSlice(self.allocator, "{\"type\":\"text\",\"text\":\"Above images contain conversation history. Continue from where we left off.\"}");

        try new_messages.appendSlice(self.allocator, "]}");

        // 2. Check if first non-compressed message is user (need assistant bridge)
        var first_kept_is_user = false;
        for (request.messages, 0..) |msg, msg_idx| {
            if (!can_compress[msg_idx]) {
                first_kept_is_user = (msg.role == .user);
                break;
            }
        }

        // If first kept is user, add assistant bridge to maintain alternation
        if (first_kept_is_user) {
            try new_messages.appendSlice(self.allocator, ",{\"role\":\"assistant\",\"content\":\"I understand the conversation history from the images above.\"}");
        }

        // 3. Add non-compressed messages (tool pairs, last user message, etc.)
        std.debug.print("[COMPRESS] Final message order:\n", .{});
        std.debug.print("  [0] NEW user (images + instruction)\n", .{});
        var final_msg_idx: usize = 1;
        if (first_kept_is_user) {
            std.debug.print("  [1] assistant (bridge - first kept was user)\n", .{});
            final_msg_idx = 2;
        }
        for (request.messages, 0..) |msg, msg_idx| {
            if (can_compress[msg_idx]) continue; // Skip compressed messages

            var has_tool_use = false;
            var has_tool_result = false;
            for (msg.content) |block| {
                if (block.content_type == .tool_use) has_tool_use = true;
                if (block.content_type == .tool_result) has_tool_result = true;
            }
            const tool_info: []const u8 = if (has_tool_use) " [tool_use]" else if (has_tool_result) " [tool_result]" else "";
            std.debug.print("  [{d}] {s}{s} (was idx {d})\n", .{ final_msg_idx, msg.role.toString(), tool_info, msg_idx });
            final_msg_idx += 1;

            try new_messages.append(self.allocator, ',');
            try self.appendMessageJson(msg, &new_messages);
        }

        try new_messages.append(self.allocator, ']');

        // Rebuild request
        const rebuilt = try self.parser.rebuildRequest(request, new_messages.items);

        // Validate JSON
        const validation = std.json.parseFromSlice(std.json.Value, self.allocator, rebuilt, .{}) catch |err| {
            std.debug.print("[COMPRESS] Invalid JSON: {any}\n", .{err});
            self.allocator.free(rebuilt);
            return try self.allocator.dupe(u8, request_json);
        };
        validation.deinit();

        std.debug.print("[COMPRESS] Done: {d}tok→{d}tok ({d:.1}% saved)\n", .{
            total_text_tokens,
            total_compressed_tokens,
            savings_pct,
        });

        return rebuilt;
    }

    fn appendMessageJson(self: TextCompressor, msg: api_types.Message, buffer: *std.ArrayList(u8)) !void {
        try buffer.appendSlice(self.allocator, "{\"role\":\"");
        try buffer.appendSlice(self.allocator, msg.role.toString());
        try buffer.appendSlice(self.allocator, "\",\"content\":");

        if (msg.content.len == 1 and msg.content[0].content_type == .text) {
            try buffer.append(self.allocator, '"');
            if (msg.content[0].text) |text| {
                try self.appendEscapedJson(text, buffer);
            }
            try buffer.append(self.allocator, '"');
        } else {
            try buffer.append(self.allocator, '[');
            for (msg.content, 0..) |block, idx| {
                if (idx > 0) try buffer.append(self.allocator, ',');
                try self.appendContentBlock(block, buffer);
            }
            try buffer.append(self.allocator, ']');
        }

        try buffer.append(self.allocator, '}');
    }

    fn appendContentBlock(self: TextCompressor, block: api_types.ContentBlock, buffer: *std.ArrayList(u8)) !void {
        switch (block.content_type) {
            .text => {
                try buffer.appendSlice(self.allocator, "{\"type\":\"text\",\"text\":\"");
                if (block.text) |text| {
                    try self.appendEscapedJson(text, buffer);
                }
                try buffer.appendSlice(self.allocator, "\"}");
            },
            .image => {
                try buffer.appendSlice(self.allocator, "{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":\"");
                if (block.media_type) |mt| {
                    try buffer.appendSlice(self.allocator, mt);
                }
                try buffer.appendSlice(self.allocator, "\",\"data\":\"");
                if (block.image_data) |data| {
                    try buffer.appendSlice(self.allocator, data);
                }
                try buffer.appendSlice(self.allocator, "\"}}");
            },
            .tool_use => {
                try buffer.appendSlice(self.allocator, "{\"type\":\"tool_use\",\"id\":\"");
                if (block.tool_use_id) |id| {
                    try buffer.appendSlice(self.allocator, id);
                }
                try buffer.appendSlice(self.allocator, "\",\"name\":\"");
                if (block.tool_name) |name| {
                    try buffer.appendSlice(self.allocator, name);
                }
                try buffer.appendSlice(self.allocator, "\",\"input\":");
                if (block.tool_input) |input| {
                    try buffer.appendSlice(self.allocator, input);
                } else {
                    try buffer.appendSlice(self.allocator, "{}");
                }
                try buffer.append(self.allocator, '}');
            },
            .tool_result => {
                try buffer.appendSlice(self.allocator, "{\"type\":\"tool_result\",\"tool_use_id\":\"");
                if (block.tool_use_id) |id| {
                    try buffer.appendSlice(self.allocator, id);
                }
                try buffer.appendSlice(self.allocator, "\",\"content\":\"");
                if (block.tool_content) |content| {
                    try self.appendEscapedJson(content, buffer);
                }
                try buffer.appendSlice(self.allocator, "\"}");
            },
            .thinking => {
                // Thinking blocks must be preserved exactly for API compliance
                try buffer.appendSlice(self.allocator, "{\"type\":\"thinking\",\"thinking\":\"");
                if (block.text) |text| {
                    try self.appendEscapedJson(text, buffer);
                }
                try buffer.appendSlice(self.allocator, "\"}");
            },
        }
    }

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
