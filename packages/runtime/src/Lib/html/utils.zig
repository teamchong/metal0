//! HTML utility functions
//!
//! Provides escape, unescape, and text processing utilities for HTML.

const std = @import("std");
const entities = @import("entities.zig");

// ============================================================================
// Main Functions
// ============================================================================

/// Escape special HTML characters: &, <, >, " and optionally '
pub fn escape(allocator: std.mem.Allocator, s: []const u8, quote: bool) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    for (s) |c| {
        switch (c) {
            '&' => try result.appendSlice(allocator, "&amp;"),
            '<' => try result.appendSlice(allocator, "&lt;"),
            '>' => try result.appendSlice(allocator, "&gt;"),
            '"' => try result.appendSlice(allocator, "&quot;"),
            '\'' => {
                if (quote) {
                    try result.appendSlice(allocator, "&#x27;");
                } else {
                    try result.append(allocator, c);
                }
            },
            else => try result.append(allocator, c),
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Unescape HTML entities to their character equivalents
pub fn unescape(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '&') {
            // Find the end of the entity
            if (std.mem.indexOfScalarPos(u8, s, i + 1, ';')) |end| {
                const entity = s[i + 1 .. end];

                // Check for numeric entity
                if (entity.len > 0 and entity[0] == '#') {
                    const codepoint = parseNumericEntity(entity[1..]);
                    if (codepoint) |cp| {
                        var buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(cp, &buf) catch {
                            // Invalid codepoint, output as-is
                            try result.appendSlice(allocator, s[i .. end + 1]);
                            i = end + 1;
                            continue;
                        };
                        try result.appendSlice(allocator, buf[0..len]);
                        i = end + 1;
                        continue;
                    }
                }

                // Check for named entity
                if (entities.html5_entities.get(entity)) |replacement| {
                    try result.appendSlice(allocator, replacement);
                    i = end + 1;
                    continue;
                }
            }
        }

        try result.append(allocator, s[i]);
        i += 1;
    }

    return result.toOwnedSlice(allocator);
}

fn parseNumericEntity(entity: []const u8) ?u21 {
    if (entity.len == 0) return null;

    if (entity[0] == 'x' or entity[0] == 'X') {
        // Hex entity
        if (entity.len < 2) return null;
        return std.fmt.parseInt(u21, entity[1..], 16) catch null;
    } else {
        // Decimal entity
        return std.fmt.parseInt(u21, entity, 10) catch null;
    }
}

// ============================================================================
// Text Processing Functions
// ============================================================================

/// Check if a character is an HTML space character
pub fn isHtmlSpace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '\x0c';
}

/// Normalize whitespace in HTML text
pub fn normalizeWhitespace(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var in_whitespace = false;
    for (s) |c| {
        if (isHtmlSpace(c)) {
            if (!in_whitespace) {
                try result.append(allocator, ' ');
                in_whitespace = true;
            }
        } else {
            try result.append(allocator, c);
            in_whitespace = false;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Strip HTML tags from text
pub fn stripTags(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var in_tag = false;
    for (html) |c| {
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
        } else if (!in_tag) {
            try result.append(allocator, c);
        }
    }

    return result.toOwnedSlice(allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "escape basic" {
    const allocator = std.testing.allocator;

    const result = try escape(allocator, "Hello <World> & \"Friends\"", true);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello &lt;World&gt; &amp; &quot;Friends&quot;", result);
}

test "escape with quotes" {
    const allocator = std.testing.allocator;

    const result = try escape(allocator, "It's a 'test'", true);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("It&#x27;s a &#x27;test&#x27;", result);
}

test "escape without quotes" {
    const allocator = std.testing.allocator;

    const result = try escape(allocator, "It's a 'test'", false);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("It's a 'test'", result);
}

test "unescape basic entities" {
    const allocator = std.testing.allocator;

    const result = try unescape(allocator, "&lt;div&gt;&amp;&quot;");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("<div>&\"", result);
}

test "unescape numeric decimal" {
    const allocator = std.testing.allocator;

    const result = try unescape(allocator, "&#65;&#66;&#67;");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("ABC", result);
}

test "unescape numeric hex" {
    const allocator = std.testing.allocator;

    const result = try unescape(allocator, "&#x41;&#x42;&#x43;");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("ABC", result);
}

test "unescape named entities" {
    const allocator = std.testing.allocator;

    const result = try unescape(allocator, "&copy; &reg; &trade;");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("\u{00A9} \u{00AE} \u{2122}", result);
}

test "strip tags" {
    const allocator = std.testing.allocator;

    const result = try stripTags(allocator, "<p>Hello <b>World</b>!</p>");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello World!", result);
}

test "normalize whitespace" {
    const allocator = std.testing.allocator;

    const result = try normalizeWhitespace(allocator, "Hello   \n\t  World");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello World", result);
}
