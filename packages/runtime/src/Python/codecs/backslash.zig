/// codecs/backslash - Backslash Encoding Utilities
/// Provides backslash escape encoding for repr() and similar operations

const std = @import("std");
const types = @import("types.zig");

// ============================================================================
// Backslash Encoding (for repr)
// ============================================================================

/// Encode string with backslash escapes
pub fn backslashEncode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (input) |ch| {
        switch (ch) {
            '\\' => try result.appendSlice("\\\\"),
            '\n' => try result.appendSlice("\\n"),
            '\r' => try result.appendSlice("\\r"),
            '\t' => try result.appendSlice("\\t"),
            else => {
                if (ch < 32 or ch >= 127) {
                    try result.appendSlice("\\x");
                    try result.append(types.hexdigits[ch >> 4]);
                    try result.append(types.hexdigits[ch & 0xf]);
                } else {
                    try result.append(ch);
                }
            },
        }
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Tests
// ============================================================================

test "backslash encode" {
    const allocator = std.testing.allocator;

    const result = try backslashEncode(allocator, "hello\nworld");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello\\nworld", result);

    const result2 = try backslashEncode(allocator, "tab\there");
    defer allocator.free(result2);
    try std.testing.expectEqualStrings("tab\\there", result2);
}
