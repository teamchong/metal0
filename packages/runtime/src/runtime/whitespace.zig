/// Unicode whitespace detection for Python string operations
const std = @import("std");

/// Check if a byte is Unicode whitespace
/// Handles ASCII whitespace plus Unicode whitespace characters like \xa0 (NBSP)
pub fn isUnicodeWhitespace(c: u8) bool {
    // ASCII whitespace
    if (std.ascii.isWhitespace(c)) return true;
    // Non-breaking space (Unicode 0xA0)
    if (c == 0xA0) return true;
    // Other common Unicode whitespace in Latin-1 range
    return false;
}

/// Check if a Unicode codepoint is whitespace
pub fn isUnicodeCodepointWhitespace(cp: u21) bool {
    // ASCII whitespace (0x09-0x0D, 0x20)
    if (cp <= 0x20) {
        return cp == 0x20 or (cp >= 0x09 and cp <= 0x0D);
    }
    // Unicode whitespace characters
    return switch (cp) {
        0x00A0, // Non-breaking space
        0x1680, // Ogham space
        0x2000...0x200A, // Various typographic spaces
        0x2028, // Line separator
        0x2029, // Paragraph separator
        0x202F, // Narrow no-break space
        0x205F, // Medium mathematical space
        0x3000, // Ideographic space
        => true,
        else => false,
    };
}

/// Check if a UTF-8 string contains only whitespace characters
pub fn isStringAllWhitespace(text: []const u8) bool {
    if (text.len == 0) return false;
    var i: usize = 0;
    while (i < text.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch return false;
        if (i + cp_len > text.len) return false;
        const cp = std.unicode.utf8Decode(text[i..][0..cp_len]) catch return false;
        if (!isUnicodeCodepointWhitespace(cp)) return false;
        i += cp_len;
    }
    return true;
}
