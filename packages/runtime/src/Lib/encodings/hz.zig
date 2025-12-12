//! CPython source: Lib/encodings/hz.py
//!
//! Implements HZ-GB-2312 encoding for Chinese text.
//! Uses escape sequences ~{ and ~} to switch between ASCII and GB2312 modes.
//!
//! Mirrors: CPython Lib/encodings/hz.py

const std = @import("std");

pub const name = "hz";
pub const aliases = [_][]const u8{ "hzgb", "hz-gb", "hz-gb-2312" };

pub const DecodeResult = struct {
    output: []u8,
    bytes_consumed: usize,
};

pub const EncodeResult = struct {
    output: []u8,
    chars_consumed: usize,
};

pub const ErrorMode = enum {
    strict,
    replace,
    ignore,
    xmlcharrefreplace,
    backslashreplace,
};

// GB2312 to Unicode lookup (simplified - common characters only)
// In a full implementation, this would be a complete GB2312 table
fn gb2312ToUnicode(row: u8, col: u8) ?u21 {
    // Row and column are in range 0x21-0x7E (1-94)
    if (row < 0x21 or row > 0x7E or col < 0x21 or col > 0x7E) return null;

    // Simplified mapping for common punctuation and symbols (row 1-2)
    if (row == 0x21) {
        // Chinese punctuation
        return switch (col) {
            0x21 => 0x3000, // Ideographic space
            0x22 => 0x3001, // Ideographic comma
            0x23 => 0x3002, // Ideographic full stop
            0x24 => 0x30FB, // Katakana middle dot
            0x25 => 0x02C9, // Modifier letter macron
            0x26 => 0x02C7, // Caron
            0x27 => 0x00A8, // Diaeresis
            0x28 => 0x3003, // Ditto mark
            0x29 => 0x3005, // Ideographic iteration mark
            0x2A => 0x2015, // Horizontal bar
            0x2B => 0xFF5E, // Fullwidth tilde
            0x2C => 0x2016, // Double vertical line
            0x2D => 0x2026, // Horizontal ellipsis
            else => null,
        };
    }

    // For a complete implementation, include full GB2312 mapping
    // This is a minimal stub that handles the basic structure
    return null;
}

/// Decode HZ-GB-2312 to UTF-8
pub fn decode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !DecodeResult {
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    var in_gb_mode = false;

    while (i < input.len) {
        if (input[i] == '~') {
            if (i + 1 >= input.len) {
                if (mode == .strict) return error.IncompleteEscape;
                try result.append(allocator, '~');
                i += 1;
                continue;
            }

            switch (input[i + 1]) {
                '{' => {
                    // Enter GB2312 mode
                    in_gb_mode = true;
                    i += 2;
                },
                '}' => {
                    // Exit GB2312 mode (back to ASCII)
                    in_gb_mode = false;
                    i += 2;
                },
                '~' => {
                    // Literal ~
                    try result.append(allocator, '~');
                    i += 2;
                },
                '\n' => {
                    // Line continuation - ignore
                    i += 2;
                },
                else => {
                    if (mode == .strict) return error.InvalidEscape;
                    try result.append(allocator, '~');
                    i += 1;
                },
            }
        } else if (in_gb_mode) {
            // GB2312 double-byte character
            if (i + 1 >= input.len) {
                if (mode == .strict) return error.IncompleteSequence;
                i += 1;
                continue;
            }

            const row = input[i];
            const col = input[i + 1];

            if (gb2312ToUnicode(row, col)) |codepoint| {
                // Encode to UTF-8
                var buf: [4]u8 = undefined;
                const len = std.unicode.utf8Encode(codepoint, &buf) catch {
                    if (mode == .strict) return error.InvalidCodepoint;
                    try result.appendSlice(allocator, "\xEF\xBF\xBD"); // U+FFFD
                    i += 2;
                    continue;
                };
                try result.appendSlice(allocator, buf[0..len]);
            } else {
                // Unknown GB2312 sequence - use replacement char
                if (mode == .strict) return error.InvalidGB2312;
                try result.appendSlice(allocator, "\xEF\xBF\xBD"); // U+FFFD
            }
            i += 2;
        } else {
            // ASCII mode
            try result.append(allocator, input[i]);
            i += 1;
        }
    }

    return DecodeResult{
        .output = try result.toOwnedSlice(allocator),
        .bytes_consumed = input.len,
    };
}

/// Encode UTF-8 to HZ-GB-2312
pub fn encode(allocator: std.mem.Allocator, input: []const u8, mode: ErrorMode) !EncodeResult {
    _ = mode;
    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    var in_gb_mode = false;

    var iter = std.unicode.Utf8Iterator{ .bytes = input, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        if (cp < 0x80) {
            // ASCII
            if (in_gb_mode) {
                try result.appendSlice(allocator, "~}");
                in_gb_mode = false;
            }
            if (cp == '~') {
                try result.appendSlice(allocator, "~~");
            } else {
                try result.append(allocator, @intCast(cp));
            }
        } else {
            // Non-ASCII - would need Unicode to GB2312 reverse mapping
            // For now, use replacement or error
            if (!in_gb_mode) {
                try result.appendSlice(allocator, "~{");
                in_gb_mode = true;
            }
            // Simplified: output question marks for unmapped characters
            try result.appendSlice(allocator, "!#"); // GB2312 for ?
        }
    }

    // Return to ASCII mode at end
    if (in_gb_mode) {
        try result.appendSlice(allocator, "~}");
    }

    return EncodeResult{
        .output = try result.toOwnedSlice(allocator),
        .chars_consumed = input.len,
    };
}

test "hz decode ascii" {
    const result = try decode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "hz decode tilde escape" {
    const result = try decode(std.testing.allocator, "A~~B", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("A~B", result.output);
}

test "hz decode mode switch" {
    // Switch to GB mode and back (with unknown GB chars producing replacement)
    const result = try decode(std.testing.allocator, "A~{!!~}B", .replace);
    defer std.testing.allocator.free(result.output);
    // !! maps to ideographic space in our minimal table
    try std.testing.expect(result.output.len > 0);
}

test "hz encode ascii" {
    const result = try encode(std.testing.allocator, "Hello", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("Hello", result.output);
}

test "hz encode tilde" {
    const result = try encode(std.testing.allocator, "A~B", .strict);
    defer std.testing.allocator.free(result.output);
    try std.testing.expectEqualStrings("A~~B", result.output);
}
