// JSON string encoding utilities
// Extracted from Bun's js_printer.zig (src/js_printer.zig)
// Source: https://github.com/oven-sh/bun

const std = @import("std");

const hex_chars = "0123456789ABCDEF";

// ASCII printable range
const first_ascii = 0x20;
const last_ascii = 0x7E;

// UTF-16 surrogate pair range
const first_high_surrogate = 0xD800;
const first_low_surrogate = 0xDC00;
const last_low_surrogate = 0xDFFF;

/// Check if a character can be printed without escaping
fn canPrintWithoutEscape(c: i32) bool {
    if (c <= last_ascii) {
        return c >= first_ascii and c != '\\' and c != '"';
    } else {
        // JSON doesn't allow unescaped control characters, BOM, line/paragraph separators
        return c != 0xFEFF and c != 0x2028 and c != 0x2029 and (c < first_high_surrogate or c > last_low_surrogate);
    }
}

/// Find the next character that needs escaping
fn indexOfNeedsEscape(text: []const u8) ?usize {
    for (text, 0..) |char, i| {
        if (char >= 127 or char < 0x20 or char == '\\' or char == '"') {
            return i;
        }
    }
    return null;
}

/// Write a JSON-escaped string (with surrounding quotes)
pub fn writeJSONString(text: []const u8, writer: anytype) !void {
    try writer.writeAll("\"");
    try writeEscapedString(text, writer);
    try writer.writeAll("\"");
}

/// Write an escaped string without quotes
pub fn writeEscapedString(text: []const u8, writer: anytype) !void {
    var i: usize = 0;
    const n = text.len;

    while (i < n) {
        const c = text[i];

        // Fast path: printable ASCII characters
        if (c >= first_ascii and c <= last_ascii and c != '\\' and c != '"') {
            const remain = text[i..];
            if (indexOfNeedsEscape(remain)) |j| {
                // Write chunk up to next escape
                try writer.writeAll(remain[0..j]);
                i += j;
            } else {
                // No more escapes, write rest and done
                try writer.writeAll(remain);
                break;
            }
            continue;
        }

        // Escape sequences
        switch (c) {
            0x08 => try writer.writeAll("\\b"), // backspace
            0x0C => try writer.writeAll("\\f"), // form feed
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            else => {
                // Control characters: use \uXXXX
                if (c < 0x20) {
                    try writer.writeAll(&[_]u8{
                        '\\',
                        'u',
                        '0',
                        '0',
                        hex_chars[(c >> 4) & 0xF],
                        hex_chars[c & 0xF],
                    });
                } else {
                    // Non-ASCII: also use \uXXXX (simplified - no full UTF-8 decoding)
                    try writer.writeAll(&[_]u8{
                        '\\',
                        'u',
                        '0',
                        '0',
                        hex_chars[(c >> 4) & 0xF],
                        hex_chars[c & 0xF],
                    });
                }
            },
        }
        i += 1;
    }
}

test "json string escape - basic" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);

    try writeJSONString("hello world", buf.writer(std.testing.allocator));
    try std.testing.expectEqualStrings("\"hello world\"", buf.items);
}

test "json string escape - newline" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);

    try writeJSONString("hello\nworld", buf.writer(std.testing.allocator));
    try std.testing.expectEqualStrings("\"hello\\nworld\"", buf.items);
}

test "json string escape - quote" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);

    try writeJSONString("quote\"here", buf.writer(std.testing.allocator));
    try std.testing.expectEqualStrings("\"quote\\\"here\"", buf.items);
}

test "json string escape - backslash" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);

    try writeJSONString("path\\to\\file", buf.writer(std.testing.allocator));
    try std.testing.expectEqualStrings("\"path\\\\to\\\\file\"", buf.items);
}

test "json string escape - tab" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);

    try writeJSONString("col1\tcol2", buf.writer(std.testing.allocator));
    try std.testing.expectEqualStrings("\"col1\\tcol2\"", buf.items);
}

test "json string escape - control chars" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);

    try writeJSONString("test\x08back", buf.writer(std.testing.allocator));
    try std.testing.expectEqualStrings("\"test\\bback\"", buf.items);
}

test "json string escape - mixed" {
    var buf = std.ArrayList(u8){};
    defer buf.deinit(std.testing.allocator);

    try writeJSONString("\"hello\"\n\tworld\\", buf.writer(std.testing.allocator));
    try std.testing.expectEqualStrings("\"\\\"hello\\\"\\n\\tworld\\\\\"", buf.items);
}
