const std = @import("std");
const api_types = @import("src/api_types.zig");

// ============================================================================
// Role Tests
// ============================================================================

test "Role.fromString parses valid roles" {
    try std.testing.expectEqual(api_types.Role.user, api_types.Role.fromString("user").?);
    try std.testing.expectEqual(api_types.Role.assistant, api_types.Role.fromString("assistant").?);
    try std.testing.expectEqual(api_types.Role.system, api_types.Role.fromString("system").?);
}

test "Role.fromString returns null for invalid roles" {
    try std.testing.expectEqual(@as(?api_types.Role, null), api_types.Role.fromString("invalid"));
    try std.testing.expectEqual(@as(?api_types.Role, null), api_types.Role.fromString(""));
    try std.testing.expectEqual(@as(?api_types.Role, null), api_types.Role.fromString("USER")); // case sensitive
}

test "Role.toString returns correct strings" {
    try std.testing.expectEqualStrings("user", api_types.Role.user.toString());
    try std.testing.expectEqualStrings("assistant", api_types.Role.assistant.toString());
    try std.testing.expectEqualStrings("system", api_types.Role.system.toString());
    try std.testing.expectEqualStrings("tool_use", api_types.Role.tool_use.toString());
    try std.testing.expectEqualStrings("tool_result", api_types.Role.tool_result.toString());
}

// ============================================================================
// MessageParser Basic Tests
// ============================================================================

test "parseRequest extracts model name" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude-3-opus-20240229","max_tokens":100,"messages":[{"role":"user","content":"Hi"}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    var request = try parser.parseRequest(json_data);
    defer request.deinit();

    try std.testing.expectEqualStrings("claude-3-opus-20240229", request.model);
}

test "parseRequest extracts max_tokens" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","max_tokens":4096,"messages":[{"role":"user","content":"Hi"}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    var request = try parser.parseRequest(json_data);
    defer request.deinit();

    try std.testing.expectEqual(@as(?u32, 4096), request.max_tokens);
}

test "parseRequest handles missing max_tokens" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","messages":[{"role":"user","content":"Hi"}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    var request = try parser.parseRequest(json_data);
    defer request.deinit();

    try std.testing.expectEqual(@as(?u32, null), request.max_tokens);
}

test "parseRequest extracts system prompt" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","system":"You are helpful","messages":[{"role":"user","content":"Hi"}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    var request = try parser.parseRequest(json_data);
    defer request.deinit();

    try std.testing.expect(request.system_prompt != null);
    try std.testing.expectEqualStrings("You are helpful", request.system_prompt.?);
}

// ============================================================================
// Message Parsing Tests
// ============================================================================

test "parseRequest parses string content" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","max_tokens":100,"messages":[{"role":"user","content":"Hello world"}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    var request = try parser.parseRequest(json_data);
    defer request.deinit();

    try std.testing.expectEqual(@as(usize, 1), request.messages.len);
    try std.testing.expectEqual(api_types.Role.user, request.messages[0].role);
    try std.testing.expectEqual(@as(usize, 1), request.messages[0].content.len);
    try std.testing.expectEqualStrings("Hello world", request.messages[0].content[0].text.?);
}

test "parseRequest parses array content with text block" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","max_tokens":100,"messages":[{"role":"user","content":[{"type":"text","text":"Array content"}]}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    var request = try parser.parseRequest(json_data);
    defer request.deinit();

    try std.testing.expectEqual(@as(usize, 1), request.messages.len);
    try std.testing.expectEqual(@as(usize, 1), request.messages[0].content.len);
    try std.testing.expectEqual(api_types.ContentType.text, request.messages[0].content[0].content_type);
    try std.testing.expectEqualStrings("Array content", request.messages[0].content[0].text.?);
}

test "parseRequest parses image content block" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","max_tokens":100,"messages":[{"role":"user","content":[{"type":"image","source":{"type":"base64","media_type":"image/png","data":"iVBORw0KGgo="}}]}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    var request = try parser.parseRequest(json_data);
    defer request.deinit();

    try std.testing.expectEqual(@as(usize, 1), request.messages.len);
    try std.testing.expectEqual(@as(usize, 1), request.messages[0].content.len);
    try std.testing.expectEqual(api_types.ContentType.image, request.messages[0].content[0].content_type);
    try std.testing.expectEqualStrings("image/png", request.messages[0].content[0].media_type.?);
    try std.testing.expectEqualStrings("iVBORw0KGgo=", request.messages[0].content[0].image_data.?);
}

test "parseRequest parses tool_use content block" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","max_tokens":100,"messages":[{"role":"assistant","content":[{"type":"tool_use","id":"toolu_123","name":"get_weather","input":{"city":"NYC"}}]}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    var request = try parser.parseRequest(json_data);
    defer request.deinit();

    try std.testing.expectEqual(@as(usize, 1), request.messages.len);
    try std.testing.expectEqual(@as(usize, 1), request.messages[0].content.len);

    const block = request.messages[0].content[0];
    try std.testing.expectEqual(api_types.ContentType.tool_use, block.content_type);
    try std.testing.expectEqualStrings("toolu_123", block.tool_use_id.?);
    try std.testing.expectEqualStrings("get_weather", block.tool_name.?);
    try std.testing.expect(block.tool_input != null);
}

test "parseRequest parses tool_result content block" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","max_tokens":100,"messages":[{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_123","content":"72F and sunny"}]}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    var request = try parser.parseRequest(json_data);
    defer request.deinit();

    try std.testing.expectEqual(@as(usize, 1), request.messages.len);
    try std.testing.expectEqual(@as(usize, 1), request.messages[0].content.len);

    const block = request.messages[0].content[0];
    try std.testing.expectEqual(api_types.ContentType.tool_result, block.content_type);
    try std.testing.expectEqualStrings("toolu_123", block.tool_use_id.?);
    try std.testing.expectEqualStrings("72F and sunny", block.tool_content.?);
}

test "parseRequest parses thinking content block" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","max_tokens":100,"messages":[{"role":"assistant","content":[{"type":"thinking","thinking":"Let me think..."},{"type":"text","text":"Answer"}]}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    var request = try parser.parseRequest(json_data);
    defer request.deinit();

    try std.testing.expectEqual(@as(usize, 1), request.messages.len);
    try std.testing.expectEqual(@as(usize, 2), request.messages[0].content.len);

    const thinking_block = request.messages[0].content[0];
    try std.testing.expectEqual(api_types.ContentType.thinking, thinking_block.content_type);
    try std.testing.expectEqualStrings("Let me think...", thinking_block.text.?);

    const text_block = request.messages[0].content[1];
    try std.testing.expectEqual(api_types.ContentType.text, text_block.content_type);
    try std.testing.expectEqualStrings("Answer", text_block.text.?);
}

// ============================================================================
// Multiple Messages Tests
// ============================================================================

test "parseRequest handles multiple messages" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","max_tokens":100,"messages":[{"role":"user","content":"Hello"},{"role":"assistant","content":"Hi there"},{"role":"user","content":"How are you?"}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    var request = try parser.parseRequest(json_data);
    defer request.deinit();

    try std.testing.expectEqual(@as(usize, 3), request.messages.len);
    try std.testing.expectEqual(api_types.Role.user, request.messages[0].role);
    try std.testing.expectEqual(api_types.Role.assistant, request.messages[1].role);
    try std.testing.expectEqual(api_types.Role.user, request.messages[2].role);
}

// ============================================================================
// extractText Tests
// ============================================================================

test "extractText extracts from string content" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","messages":[{"role":"user","content":"Simple text"}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    const text = try parser.extractText(json_data);
    defer allocator.free(text);

    try std.testing.expectEqualStrings("Simple text", text);
}

test "extractText extracts from array content" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","messages":[{"role":"user","content":[{"type":"text","text":"From array"}]}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    const text = try parser.extractText(json_data);
    defer allocator.free(text);

    try std.testing.expectEqualStrings("From array", text);
}

test "extractText handles escape sequences" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","messages":[{"role":"user","content":"Line1\nLine2\tTabbed"}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    const text = try parser.extractText(json_data);
    defer allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\t") != null);
}

test "extractText handles escaped quotes" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","messages":[{"role":"user","content":"He said \"hello\""}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    const text = try parser.extractText(json_data);
    defer allocator.free(text);

    try std.testing.expectEqualStrings("He said \"hello\"", text);
}

test "extractText handles escaped backslash" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","messages":[{"role":"user","content":"path\\to\\file"}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    const text = try parser.extractText(json_data);
    defer allocator.free(text);

    try std.testing.expectEqualStrings("path\\to\\file", text);
}

// ============================================================================
// rebuildRequest Tests
// ============================================================================

test "rebuildRequest reconstructs valid JSON" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","max_tokens":100,"messages":[{"role":"user","content":"Original"}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    var request = try parser.parseRequest(json_data);
    defer request.deinit();

    const new_messages =
        \\[{"role":"user","content":"Modified"}]
    ;

    const rebuilt = try parser.rebuildRequest(request, new_messages);
    defer allocator.free(rebuilt);

    // Should contain the new messages
    try std.testing.expect(std.mem.indexOf(u8, rebuilt, "Modified") != null);
    // Should still have model
    try std.testing.expect(std.mem.indexOf(u8, rebuilt, "claude") != null);
}

// ============================================================================
// Edge Cases and Error Handling
// ============================================================================

test "parseRequest handles empty messages array" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","max_tokens":100,"messages":[]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    var request = try parser.parseRequest(json_data);
    defer request.deinit();

    try std.testing.expectEqual(@as(usize, 0), request.messages.len);
}

test "parseRequest handles mixed content blocks" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"model":"claude","max_tokens":100,"messages":[{"role":"user","content":[{"type":"text","text":"Look at this:"},{"type":"image","source":{"type":"base64","media_type":"image/png","data":"abc123"}}]}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    var request = try parser.parseRequest(json_data);
    defer request.deinit();

    try std.testing.expectEqual(@as(usize, 1), request.messages.len);
    try std.testing.expectEqual(@as(usize, 2), request.messages[0].content.len);
    try std.testing.expectEqual(api_types.ContentType.text, request.messages[0].content[0].content_type);
    try std.testing.expectEqual(api_types.ContentType.image, request.messages[0].content[1].content_type);
}

test "parseRequest handles unknown model gracefully" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{"max_tokens":100,"messages":[{"role":"user","content":"Hi"}]}
    ;

    var parser = api_types.MessageParser.init(allocator);
    var request = try parser.parseRequest(json_data);
    defer request.deinit();

    // Should default to "unknown" when model is missing
    try std.testing.expectEqualStrings("unknown", request.model);
}
