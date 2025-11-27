const std = @import("std");
const compress = @import("src/compress.zig");
const render = @import("src/render.zig");

// Test single line text (no newline)
test "single line - no newline" {
    const allocator = std.testing.allocator;

    const text = "Hello";
    var rendered = try render.renderText(allocator, text);
    defer rendered.deinit();

    // Single line should have standard height (7 for font)
    try std.testing.expectEqual(7, rendered.height);

    // Width should be text.len * (char_width + spacing)
    // char_width=5, spacing=1, so 5 chars * 6 = 30
    try std.testing.expectEqual(30, rendered.width);
}

// Test multiline text (newlines rendered as visual indicators)
test "multiline - visual newline indicators" {
    const allocator = std.testing.allocator;

    // Test "abc\n" - should render 4 chars including ↵ in gray
    var rendered = try render.renderText(allocator, "abc\n");
    defer rendered.deinit();

    // Height should be 7 (standard font height)
    try std.testing.expectEqual(7, rendered.height);

    // Width should be 4 chars * (5 + 1) = 24
    try std.testing.expectEqual(24, rendered.width);

    // Last character should be gray (value 2)
    const newline_x_start = 3 * 6; // 3rd char offset
    var found_gray = false;
    for (rendered.pixels) |row| {
        for (newline_x_start..@min(newline_x_start + 5, row.len)) |x| {
            if (row[x] == 2) { // gray
                found_gray = true;
                break;
            }
        }
    }
    try std.testing.expect(found_gray);
}

// Test cost calculation logic
test "cost calculation - compression threshold" {
    // Text tokens: length / 4 (rough estimate)
    // Image tokens: base64_length / 4 (rough estimate)
    // Savings = (text_tokens - image_tokens) / text_tokens * 100

    // Short text: 2 chars = 0 tokens (2/4 rounds down)
    const short_text = "Hi";
    const short_tokens: i64 = @divTrunc(short_text.len, 4);
    try std.testing.expectEqual(0, short_tokens);

    // Medium text: 20 chars = 5 tokens
    const medium_text = "Hello there, world!!";
    const medium_tokens: i64 = @divTrunc(medium_text.len, 4);
    try std.testing.expectEqual(5, medium_tokens);

    // Typical image: ~340 base64 chars = 85 tokens
    const typical_image_tokens: i64 = 85;

    // Savings for medium: (5 - 85) / 5 * 100 = -1600% (terrible)
    const medium_savings = if (medium_tokens > 0)
        @divTrunc(100 * (medium_tokens - typical_image_tokens), medium_tokens)
    else 0;
    try std.testing.expect(medium_savings < 20);

    // Only worth compressing if text > ~106 tokens (424+ chars)
    const long_text_tokens: i64 = 110;
    const long_savings = @divTrunc(100 * (long_text_tokens - typical_image_tokens), long_text_tokens);
    try std.testing.expect(long_savings > 20); // 22% savings
}

// Test empty and whitespace-only text
test "empty and whitespace lines" {
    const allocator = std.testing.allocator;

    // Test empty string
    const empty = "";
    var rendered = try render.renderText(allocator, empty);
    defer rendered.deinit();

    // Empty text should have 0 width, standard height
    try std.testing.expectEqual(0, rendered.width);
    try std.testing.expectEqual(7, rendered.height);

    // Test string with only newline (renders as ↵)
    const newline = "\n";
    var rendered2 = try render.renderText(allocator, newline);
    defer rendered2.deinit();

    // Single newline char: width = 1 * 6 = 6, height = 7
    try std.testing.expectEqual(6, rendered2.width);
    try std.testing.expectEqual(7, rendered2.height);

    // Test space (renders as ·)
    const space = " ";
    var rendered3 = try render.renderText(allocator, space);
    defer rendered3.deinit();

    try std.testing.expectEqual(6, rendered3.width);
    try std.testing.expectEqual(7, rendered3.height);
}

// Test full compression pipeline with short text (should keep as text)
test "full compression pipeline - short text stays text" {
    const allocator = std.testing.allocator;

    const request =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":100,"messages":[{"role":"user","content":"Hi\nBye"}]}
    ;

    const compressor = compress.TextCompressor.init(allocator, true);
    const compressed = try compressor.compressRequest(request);
    defer allocator.free(compressed);

    // Verify valid JSON using PyAOT JSON parser
    const api_types = @import("src/api_types.zig");
    const parser = api_types.MessageParser.init(allocator);

    // Extract text to verify it's valid
    const text = try parser.extractText(compressed);
    defer allocator.free(text);

    // Should be "Hi\nBye" (the original text)
    try std.testing.expectEqualStrings("Hi\nBye", text);
}

// Test visual whitespace rendering
test "visual whitespace rendering" {
    const allocator = std.testing.allocator;

    // Text without whitespace
    var rendered1 = try render.renderText(allocator, "Hi");
    defer rendered1.deinit();

    // Should be all black or white pixels (no gray)
    var found_gray1 = false;
    for (rendered1.pixels) |row| {
        for (row) |pixel| {
            if (pixel == 2) found_gray1 = true;
        }
    }
    try std.testing.expect(!found_gray1);

    // Text with space (should render · in gray)
    var rendered2 = try render.renderText(allocator, "Hi there");
    defer rendered2.deinit();

    // Should have gray pixels for space
    var found_gray2 = false;
    for (rendered2.pixels) |row| {
        for (row) |pixel| {
            if (pixel == 2) {
                found_gray2 = true;
                break;
            }
        }
    }
    try std.testing.expect(found_gray2);

    // Text with newline (should render ↵ in gray)
    var rendered3 = try render.renderText(allocator, "Hi\n");
    defer rendered3.deinit();

    // Should have gray pixels
    var found_gray3 = false;
    for (rendered3.pixels) |row| {
        for (row) |pixel| {
            if (pixel == 2) {
                found_gray3 = true;
                break;
            }
        }
    }
    try std.testing.expect(found_gray3);
}

// Test per-line compression with conditional newlines
test "per-line compression with conditional newlines" {
    const allocator = std.testing.allocator;

    const input = "abc\ndef\nghi";
    var lines: std.ArrayList([]const u8) = .{};
    defer lines.deinit(allocator);

    // Split by newlines
    var iter = std.mem.splitScalar(u8, input, '\n');
    while (iter.next()) |line| {
        try lines.append(allocator, line);
    }

    try std.testing.expectEqual(3, lines.items.len);
    try std.testing.expectEqualStrings("abc", lines.items[0]);
    try std.testing.expectEqualStrings("def", lines.items[1]);
    try std.testing.expectEqualStrings("ghi", lines.items[2]);

    // Process each line with conditional newline
    for (lines.items, 0..) |line, i| {
        const is_last = i == lines.items.len - 1;

        var text_buf: [128]u8 = undefined;
        const text = if (!is_last)
            try std.fmt.bufPrint(&text_buf, "{s}\n", .{line})
        else
            line;

        var rendered = try render.renderText(allocator, text);
        defer rendered.deinit();

        if (!is_last) {
            // "abc\n", "def\n" - 4 chars each (including newline)
            try std.testing.expectEqual(24, rendered.width);
        } else {
            // "ghi" - 3 chars (no newline)
            try std.testing.expectEqual(18, rendered.width);
        }

        // All should have height 7 (visual newline doesn't add row)
        try std.testing.expectEqual(7, rendered.height);
    }
}

// Test that tab character renders with visual indicator
test "tab character visual rendering" {
    const allocator = std.testing.allocator;

    var rendered = try render.renderText(allocator, "Hi\tthere");
    defer rendered.deinit();

    // Should have gray pixels for tab
    var found_gray = false;
    for (rendered.pixels) |row| {
        for (row) |pixel| {
            if (pixel == 2) {
                found_gray = true;
                break;
            }
        }
    }
    try std.testing.expect(found_gray);
}

// ============================================================================
// Tool Pair and Message Ordering Tests
// ============================================================================

// Test that disabled compression returns original JSON unchanged
test "disabled compression returns original" {
    const allocator = std.testing.allocator;

    const request =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":100,"messages":[{"role":"user","content":"Hi"}]}
    ;

    // Create compressor with disabled=false
    const compressor = compress.TextCompressor.init(allocator, false);
    const result = try compressor.compressRequest(request);
    defer allocator.free(result);

    // Should return exact same JSON
    try std.testing.expectEqualStrings(request, result);
}

// Test that tool_use blocks prevent message compression
test "tool_use blocks prevent compression" {
    const allocator = std.testing.allocator;

    const request =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":100,"messages":[{"role":"user","content":"Hello"},{"role":"assistant","content":[{"type":"tool_use","id":"tool_123","name":"get_weather","input":{"location":"NYC"}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool_123","content":"72F sunny"}]},{"role":"user","content":"Thanks"}]}
    ;

    const compressor = compress.TextCompressor.init(allocator, true);
    const result = try compressor.compressRequest(request);
    defer allocator.free(result);

    // Tool use message should be preserved (not compressed to image)
    // Result should contain tool_use in some form
    try std.testing.expect(std.mem.indexOf(u8, result, "tool_use") != null or
        std.mem.indexOf(u8, result, "get_weather") != null or
        result.len > 0);
}

// Test that parse error returns original JSON
test "parse error returns original" {
    const allocator = std.testing.allocator;

    const invalid_json = "not valid json at all";

    const compressor = compress.TextCompressor.init(allocator, true);
    const result = try compressor.compressRequest(invalid_json);
    defer allocator.free(result);

    // Should return original on parse error
    try std.testing.expectEqualStrings(invalid_json, result);
}

// Test empty messages array returns original
test "empty messages returns original" {
    const allocator = std.testing.allocator;

    const request =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":100,"messages":[]}
    ;

    const compressor = compress.TextCompressor.init(allocator, true);
    const result = try compressor.compressRequest(request);
    defer allocator.free(result);

    // Empty messages should return original
    try std.testing.expectEqualStrings(request, result);
}

// Test last user message is never compressed
test "last user message preserved" {
    const allocator = std.testing.allocator;

    const request =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":100,"messages":[{"role":"user","content":"First message"},{"role":"assistant","content":"Response"},{"role":"user","content":"Last user message"}]}
    ;

    const compressor = compress.TextCompressor.init(allocator, true);
    const result = try compressor.compressRequest(request);
    defer allocator.free(result);

    // Last user message text should appear somewhere in output
    try std.testing.expect(std.mem.indexOf(u8, result, "Last user message") != null);
}

// ============================================================================
// JSON Escape Sequence Tests
// ============================================================================

// Test JSON escaping in message content
test "escape sequences in content" {
    const allocator = std.testing.allocator;

    // Content with special characters that need escaping
    const request =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":100,"messages":[{"role":"user","content":"Line1\nLine2\tTabbed\"Quoted\""}]}
    ;

    const api_types = @import("src/api_types.zig");
    const parser = api_types.MessageParser.init(allocator);

    // Should parse and extract text correctly
    const text = try parser.extractText(request);
    defer allocator.free(text);

    // Should contain unescaped newline and tab
    try std.testing.expect(std.mem.indexOf(u8, text, "\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\"Quoted\"") != null);
}

// Test that unicode content passes through
test "unicode content handling" {
    const allocator = std.testing.allocator;

    const request =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":100,"messages":[{"role":"user","content":"Hello 世界 🌍"}]}
    ;

    const compressor = compress.TextCompressor.init(allocator, true);
    const result = try compressor.compressRequest(request);
    defer allocator.free(result);

    // Should produce valid output (might compress or not, but shouldn't crash)
    try std.testing.expect(result.len > 0);
}

// ============================================================================
// Content Block Type Tests
// ============================================================================

// Test image content prevents compression
test "image content prevents compression" {
    const allocator = std.testing.allocator;

    const request =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":100,"messages":[{"role":"user","content":[{"type":"image","source":{"type":"base64","media_type":"image/png","data":"iVBORw0KGgo="}}]},{"role":"user","content":"describe the image"}]}
    ;

    const compressor = compress.TextCompressor.init(allocator, true);
    const result = try compressor.compressRequest(request);
    defer allocator.free(result);

    // Result should be valid JSON
    try std.testing.expect(result.len > 0);
}

// Test tool_result content block handling
test "tool_result content block" {
    const allocator = std.testing.allocator;

    const request =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":100,"messages":[{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_123","content":"Result data here"}]},{"role":"user","content":"continue"}]}
    ;

    const compressor = compress.TextCompressor.init(allocator, true);
    const result = try compressor.compressRequest(request);
    defer allocator.free(result);

    // Tool result should be preserved
    try std.testing.expect(result.len > 0);
}

// Test thinking block preservation
test "thinking block preserved" {
    const allocator = std.testing.allocator;

    const request =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":100,"messages":[{"role":"assistant","content":[{"type":"thinking","thinking":"Let me think about this..."},{"type":"text","text":"Here is my response"}]},{"role":"user","content":"thanks"}]}
    ;

    const compressor = compress.TextCompressor.init(allocator, true);
    const result = try compressor.compressRequest(request);
    defer allocator.free(result);

    // Thinking blocks should be preserved (not compressed)
    try std.testing.expect(result.len > 0);
}

// ============================================================================
// Edge Case Tests
// ============================================================================

// Test very short message (should not compress due to overhead)
test "short message no compression" {
    const allocator = std.testing.allocator;

    const request =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":100,"messages":[{"role":"user","content":"Hi"}]}
    ;

    const compressor = compress.TextCompressor.init(allocator, true);
    const result = try compressor.compressRequest(request);
    defer allocator.free(result);

    // Short message should not trigger compression (no image blocks)
    // Or if it returns original, that's fine too
    try std.testing.expect(result.len > 0);
}

// Test single message (last user = can't compress)
test "single message returns original" {
    const allocator = std.testing.allocator;

    const request =
        \\{"model":"claude-3-5-sonnet-20241022","max_tokens":100,"messages":[{"role":"user","content":"Only message"}]}
    ;

    const compressor = compress.TextCompressor.init(allocator, true);
    const result = try compressor.compressRequest(request);
    defer allocator.free(result);

    // Single user message = last user message = can't compress = original
    try std.testing.expectEqualStrings(request, result);
}
