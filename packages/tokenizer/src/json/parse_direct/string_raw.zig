/// Parse JSON string directly to raw []const u8 (for dict keys - no PyObject wrapper)
const std = @import("std");
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;
const simd = @import("../simd/dispatch.zig");

/// Parse JSON string directly to raw string (no PyObject wrapper, single SIMD pass!)
/// This is used for dict keys where we don't need the PyString overhead
pub fn parseStringRaw(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult([]const u8) {
    if (pos >= data.len or data[pos] != '"') return JsonError.UnexpectedToken;

    const start = pos + 1; // Skip opening quote

    // Single-pass SIMD: find closing quote AND check for escapes simultaneously
    if (simd.findClosingQuoteAndEscapes(data[start..])) |result| {
        const i = start + result.quote_pos;

        const str_data: []const u8 = if (!result.has_escapes)
            // Fast path: No escapes, just copy once
            try allocator.dupe(u8, data[start..i])
        else
            // Slow path: Need to unescape
            try unescapeString(data[start..i], allocator)
        ;

        return ParseResult([]const u8).init(
            str_data,
            i + 1 - pos,
        );
    }

    return JsonError.UnexpectedEndOfInput;
}

/// Unescape a JSON string with escape sequences
fn unescapeString(escaped: []const u8, allocator: std.mem.Allocator) JsonError![]const u8 {
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < escaped.len) : (i += 1) {
        if (escaped[i] == '\\') {
            i += 1;
            if (i >= escaped.len) return JsonError.InvalidEscape;

            const c = escaped[i];
            switch (c) {
                '"' => try result.append(allocator, '"'),
                '\\' => try result.append(allocator, '\\'),
                '/' => try result.append(allocator, '/'),
                'b' => try result.append(allocator, '\x08'),
                'f' => try result.append(allocator, '\x0C'),
                'n' => try result.append(allocator, '\n'),
                'r' => try result.append(allocator, '\r'),
                't' => try result.append(allocator, '\t'),
                'u' => {
                    // Unicode escape: \uXXXX
                    if (i + 4 >= escaped.len) return JsonError.InvalidUnicode;
                    const hex = escaped[i + 1 .. i + 5];
                    const codepoint = std.fmt.parseInt(u16, hex, 16) catch return JsonError.InvalidUnicode;

                    // Convert codepoint to UTF-8
                    var utf8_buf: [4]u8 = undefined;
                    const utf8_len = std.unicode.utf8Encode(@as(u21, codepoint), &utf8_buf) catch return JsonError.InvalidUnicode;
                    try result.appendSlice(allocator, utf8_buf[0..utf8_len]);

                    i += 4; // Skip XXXX
                },
                else => return JsonError.InvalidEscape,
            }
        } else {
            try result.append(allocator, escaped[i]);
        }
    }

    return try result.toOwnedSlice(allocator);
}
