//! IMAP utility functions
//!
//! Mirrors: CPython Lib/imaplib.py (utility functions)

const std = @import("std");

/// Parse FLAGS response - extracts flags from parenthesized list
/// Input: "* FLAGS (\\Seen \\Answered \\Flagged)"
/// Output: array of flag strings
pub fn parseFlags(allocator: std.mem.Allocator, data: []const u8) ![][]const u8 {
    var flags = std.ArrayList([]const u8).init(allocator);
    errdefer flags.deinit();

    // Find the parenthesized list
    const start = std.mem.indexOf(u8, data, "(") orelse return flags.toOwnedSlice();
    const end = std.mem.indexOf(u8, data[start..], ")") orelse return flags.toOwnedSlice();

    const flags_str = data[start + 1 .. start + end];

    // Split by whitespace
    var iter = std.mem.tokenizeAny(u8, flags_str, " \t");
    while (iter.next()) |flag| {
        try flags.append(flag);
    }

    return flags.toOwnedSlice();
}

/// Parse FETCH response to extract message flags
pub fn parseFetchFlags(allocator: std.mem.Allocator, data: []const u8) ![][]const u8 {
    // Look for "FLAGS (...)" in FETCH response
    const flags_pos = std.mem.indexOf(u8, data, "FLAGS") orelse return &[_][]const u8{};
    return parseFlags(allocator, data[flags_pos..]);
}

/// Check if a flag is set (case-insensitive)
pub fn hasFlag(flags: []const []const u8, flag: []const u8) bool {
    for (flags) |f| {
        if (std.ascii.eqlIgnoreCase(f, flag)) return true;
    }
    return false;
}

/// Encode modified UTF-7 (IMAP mailbox encoding per RFC 3501)
/// Modified UTF-7 uses & instead of + and , instead of /
pub fn encodeModifiedUtf7(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        if (c == '&') {
            // Literal & becomes &-
            try result.appendSlice("&-");
            i += 1;
        } else if (c >= 0x20 and c <= 0x7e) {
            // Printable ASCII (except &)
            try result.append(c);
            i += 1;
        } else {
            // Non-ASCII: collect UTF-8 sequence and encode as modified base64
            var utf8_buf: [64]u8 = undefined;
            var utf8_len: usize = 0;

            while (i < s.len and (s[i] < 0x20 or s[i] > 0x7e)) {
                utf8_buf[utf8_len] = s[i];
                utf8_len += 1;
                i += 1;
            }

            // Encode as modified base64 (+ becomes &, / becomes ,)
            try result.append('&');
            var base64_buf: [128]u8 = undefined;
            const encoded = std.base64.standard.Encoder.encode(&base64_buf, utf8_buf[0..utf8_len]);
            for (encoded) |b| {
                if (b == '/') {
                    try result.append(',');
                } else if (b == '=') {
                    // Skip padding
                } else {
                    try result.append(b);
                }
            }
            try result.append('-');
        }
    }

    return result.toOwnedSlice();
}

/// Decode modified UTF-7 (IMAP mailbox encoding per RFC 3501)
pub fn decodeModifiedUtf7(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '&') {
            if (i + 1 < s.len and s[i + 1] == '-') {
                // &- is literal &
                try result.append('&');
                i += 2;
            } else {
                // Find end of base64 sequence (marked by -)
                const start = i + 1;
                var end = start;
                while (end < s.len and s[end] != '-') {
                    end += 1;
                }

                // Convert modified base64 back to standard
                var base64_buf: [128]u8 = undefined;
                var base64_len: usize = 0;
                for (s[start..end]) |b| {
                    if (b == ',') {
                        base64_buf[base64_len] = '/';
                    } else {
                        base64_buf[base64_len] = b;
                    }
                    base64_len += 1;
                }

                // Add padding if needed
                while (base64_len % 4 != 0) {
                    base64_buf[base64_len] = '=';
                    base64_len += 1;
                }

                // Decode base64
                var decoded_buf: [64]u8 = undefined;
                const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(base64_buf[0..base64_len]) catch 0;
                if (decoded_len > 0) {
                    std.base64.standard.Decoder.decode(&decoded_buf, base64_buf[0..base64_len]) catch {};
                    try result.appendSlice(decoded_buf[0..decoded_len]);
                }

                i = end + 1; // Skip closing -
            }
        } else {
            try result.append(s[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice();
}
