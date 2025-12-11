/// Float string parsing with Unicode support
const std = @import("std");
const exceptions = @import("../exceptions.zig");

/// Python error types
pub const PythonError = error{
    ZeroDivisionError,
    IndexError,
    ValueError,
    TypeError,
    KeyError,
    OverflowError,
    OutOfMemory,
    Exception,
};

/// Parse float string with error message (for use in except handlers)
pub fn parseFloatStr(str: []const u8) !f64 {
    return parseFloatWithUnicode(str) catch {
        exceptions.setFloatConversionErrorStr(str);
        return error.ValueError;
    };
}

/// Parse float from bytes (ASCII only - no Unicode digit conversion)
pub fn parseFloatBytes(data: []const u8) !f64 {
    var start: usize = 0;
    var end: usize = data.len;
    while (start < end and (data[start] == ' ' or data[start] == '\t' or
        data[start] == '\n' or data[start] == '\r' or
        data[start] == 0x0B or data[start] == 0x0C))
    {
        start += 1;
    }
    while (end > start and (data[end - 1] == ' ' or data[end - 1] == '\t' or
        data[end - 1] == '\n' or data[end - 1] == '\r' or
        data[end - 1] == 0x0B or data[end - 1] == 0x0C))
    {
        end -= 1;
    }
    if (start >= end) return error.InvalidFloat;

    const trimmed = data[start..end];

    for (trimmed) |byte| {
        if (byte >= 0x80) {
            return error.InvalidFloat;
        }
    }

    return std.fmt.parseFloat(f64, trimmed) catch error.InvalidFloat;
}

/// Parse float string with Unicode digit support (Python-compatible)
pub fn parseFloatWithUnicode(str: []const u8) !f64 {
    var trimmed = trimUnicodeWhitespace(str);
    if (trimmed.len == 0) return error.InvalidFloat;

    // Reject hex literals
    if (trimmed.len >= 2) {
        const start = if (trimmed[0] == '-' or trimmed[0] == '+') trimmed[1..] else trimmed;
        if (start.len >= 2 and start[0] == '0' and (start[1] == 'x' or start[1] == 'X')) {
            return error.InvalidFloat;
        }
        if ((trimmed[0] == '+' or trimmed[0] == '-') and (trimmed[1] == '+' or trimmed[1] == '-')) {
            return error.InvalidFloat;
        }
        if (trimmed[0] == '.' and trimmed.len > 1) {
            const next = trimmed[1];
            if (next == 'n' or next == 'N' or next == 'i' or next == 'I') {
                return error.InvalidFloat;
            }
        }
        if ((trimmed[0] == '+' or trimmed[0] == '-') and trimmed.len > 1 and trimmed[1] == '.') {
            if (trimmed.len == 2) return error.InvalidFloat;
            const next = trimmed[2];
            if (next == 'n' or next == 'N' or next == 'i' or next == 'I') {
                return error.InvalidFloat;
            }
        }
    }
    if (trimmed.len == 1 and trimmed[0] == '.') {
        return error.InvalidFloat;
    }

    // Fast path for ASCII
    if (std.fmt.parseFloat(f64, trimmed)) |val| {
        return val;
    } else |_| {}

    // Normalize Unicode digits to ASCII
    var buf: [256]u8 = undefined;
    var buf_len: usize = 0;
    var i: usize = 0;

    while (i < trimmed.len) {
        if (buf_len >= buf.len - 1) return error.InvalidFloat;

        const byte = trimmed[i];

        if (byte < 0x80) {
            buf[buf_len] = byte;
            buf_len += 1;
            i += 1;
            continue;
        }

        const codepoint = decodeUtf8Codepoint(trimmed[i..]) catch {
            i += 1;
            continue;
        };
        const cp_len = utf8CodepointLen(byte);

        if (unicodeDigitToAscii(codepoint)) |ascii_digit| {
            buf[buf_len] = ascii_digit;
            buf_len += 1;
        } else if (codepoint == 0x066B or codepoint == 0x066C) {
            buf[buf_len] = '.';
            buf_len += 1;
        } else {
            return error.InvalidFloat;
        }

        i += cp_len;
    }

    if (buf_len == 0) return error.InvalidFloat;

    return std.fmt.parseFloat(f64, buf[0..buf_len]) catch error.InvalidFloat;
}

/// Decode a UTF-8 codepoint from bytes
pub fn decodeUtf8Codepoint(bytes: []const u8) !u21 {
    if (bytes.len == 0) return error.InvalidUtf8;

    const first = bytes[0];
    if (first < 0x80) {
        return first;
    } else if (first < 0xC0) {
        return error.InvalidUtf8;
    } else if (first < 0xE0) {
        if (bytes.len < 2) return error.InvalidUtf8;
        return (@as(u21, first & 0x1F) << 6) | (bytes[1] & 0x3F);
    } else if (first < 0xF0) {
        if (bytes.len < 3) return error.InvalidUtf8;
        return (@as(u21, first & 0x0F) << 12) | (@as(u21, bytes[1] & 0x3F) << 6) | (bytes[2] & 0x3F);
    } else {
        if (bytes.len < 4) return error.InvalidUtf8;
        return (@as(u21, first & 0x07) << 18) | (@as(u21, bytes[1] & 0x3F) << 12) | (@as(u21, bytes[2] & 0x3F) << 6) | (bytes[3] & 0x3F);
    }
}

/// Get UTF-8 byte length from first byte
pub fn utf8CodepointLen(first_byte: u8) usize {
    if (first_byte < 0x80) return 1;
    if (first_byte < 0xE0) return 2;
    if (first_byte < 0xF0) return 3;
    return 4;
}

/// Convert Unicode digit codepoint to ASCII digit character
pub fn unicodeDigitToAscii(codepoint: u21) ?u8 {
    // Arabic-Indic digits U+0660-U+0669
    if (codepoint >= 0x0660 and codepoint <= 0x0669) {
        return @intCast('0' + (codepoint - 0x0660));
    }
    // Extended Arabic-Indic digits U+06F0-U+06F9
    if (codepoint >= 0x06F0 and codepoint <= 0x06F9) {
        return @intCast('0' + (codepoint - 0x06F0));
    }
    // Devanagari digits U+0966-U+096F
    if (codepoint >= 0x0966 and codepoint <= 0x096F) {
        return @intCast('0' + (codepoint - 0x0966));
    }
    // Bengali digits U+09E6-U+09EF
    if (codepoint >= 0x09E6 and codepoint <= 0x09EF) {
        return @intCast('0' + (codepoint - 0x09E6));
    }
    // Gurmukhi digits U+0A66-U+0A6F
    if (codepoint >= 0x0A66 and codepoint <= 0x0A6F) {
        return @intCast('0' + (codepoint - 0x0A66));
    }
    // Gujarati digits U+0AE6-U+0AEF
    if (codepoint >= 0x0AE6 and codepoint <= 0x0AEF) {
        return @intCast('0' + (codepoint - 0x0AE6));
    }
    // Tamil digits U+0BE6-U+0BEF
    if (codepoint >= 0x0BE6 and codepoint <= 0x0BEF) {
        return @intCast('0' + (codepoint - 0x0BE6));
    }
    // Thai digits U+0E50-U+0E59
    if (codepoint >= 0x0E50 and codepoint <= 0x0E59) {
        return @intCast('0' + (codepoint - 0x0E50));
    }
    // Fullwidth digits U+FF10-U+FF19
    if (codepoint >= 0xFF10 and codepoint <= 0xFF19) {
        return @intCast('0' + (codepoint - 0xFF10));
    }
    return null;
}

/// Trim Unicode whitespace from both ends
pub fn trimUnicodeWhitespace(str: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = str.len;

    while (start < end) {
        const byte = str[start];
        if (byte < 0x80) {
            if (byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r' or byte == 0x0B or byte == 0x0C) {
                start += 1;
                continue;
            }
            break;
        }
        const codepoint = decodeUtf8Codepoint(str[start..]) catch break;
        if (isUnicodeWhitespace(codepoint)) {
            start += utf8CodepointLen(byte);
            continue;
        }
        break;
    }

    while (end > start) {
        var char_start = end - 1;
        while (char_start > start and (str[char_start] & 0xC0) == 0x80) {
            char_start -= 1;
        }

        const byte = str[char_start];
        if (byte < 0x80) {
            if (byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r' or byte == 0x0B or byte == 0x0C) {
                end = char_start;
                continue;
            }
            break;
        }
        const codepoint = decodeUtf8Codepoint(str[char_start..end]) catch break;
        if (isUnicodeWhitespace(codepoint)) {
            end = char_start;
            continue;
        }
        break;
    }

    return str[start..end];
}

/// Check if codepoint is Unicode whitespace
pub fn isUnicodeWhitespace(codepoint: u21) bool {
    return switch (codepoint) {
        0x0009...0x000D,
        0x0020,
        0x0085,
        0x00A0,
        0x1680,
        0x2000...0x200A,
        0x2028,
        0x2029,
        0x202F,
        0x205F,
        0x3000,
        => true,
        else => false,
    };
}
