/// Custom text splitter for cl100k_base pattern
/// Pure Zig, no regex - implements the specific rules manually
/// Pattern: (?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}{1,3}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+
const std = @import("std");
const Allocator = std.mem.Allocator;
const unicode = std.unicode;

pub fn split(allocator: Allocator, text: []const u8) ![][]const u8 {
    var chunks = std.ArrayList([]const u8){};
    errdefer chunks.deinit(allocator);

    var pos: usize = 0;
    while (pos < text.len) {
        const start = pos;

        // Try each pattern in order
        if (tryContraction(text, &pos)) {
            try chunks.append(allocator, text[start..pos]);
        } else if (tryLetterSequence(text, &pos)) {
            try chunks.append(allocator, text[start..pos]);
        } else if (tryNumberSequence(text, &pos)) {
            try chunks.append(allocator, text[start..pos]);
        } else if (tryNonAlphanumeric(text, &pos)) {
            try chunks.append(allocator, text[start..pos]);
        } else if (tryWhitespace(text, &pos)) {
            try chunks.append(allocator, text[start..pos]);
        } else {
            // Fallback: take one byte
            pos += 1;
            if (pos > start) {
                try chunks.append(allocator, text[start..pos]);
            }
        }
    }

    return try chunks.toOwnedSlice(allocator);
}

/// Check for contractions: 's 't 're 've 'm 'll 'd (case-insensitive)
fn tryContraction(text: []const u8, pos: *usize) bool {
    if (pos.* >= text.len) return false;
    if (text[pos.*] != '\'' and text[pos.*] != '\u{2019}') return false; // ' or '

    const remaining = text[pos.*..];
    const contractions = [_][]const u8{ "'s", "'t", "'re", "'ve", "'m", "'ll", "'d" };

    for (contractions) |c| {
        if (remaining.len >= c.len) {
            if (std.ascii.eqlIgnoreCase(remaining[0..c.len], c)) {
                pos.* += c.len;
                return true;
            }
        }
    }
    return false;
}

/// [^\r\n\p{L}\p{N}]?\p{L}+ - Optional non-letter/digit/newline, then letters
fn tryLetterSequence(text: []const u8, pos: *usize) bool {
    const start = pos.*;
    var found_letter = false;

    // Optional: one non-letter/digit/newline character (must check UTF-8)
    if (pos.* < text.len) {
        const cp_len = unicode.utf8ByteSequenceLength(text[pos.*]) catch 1;
        if (pos.* + cp_len <= text.len) {
            const codepoint = unicode.utf8Decode(text[pos.*..pos.* + cp_len]) catch text[pos.*];
            if (!isLetterCodepoint(codepoint) and !isDigitCodepoint(codepoint) and
                codepoint != '\r' and codepoint != '\n') {
                pos.* += cp_len;
            }
        }
    }

    // One or more letters (UTF-8 aware)
    while (pos.* < text.len) {
        const cp_len = unicode.utf8ByteSequenceLength(text[pos.*]) catch 1;
        if (pos.* + cp_len > text.len) break;

        const codepoint = unicode.utf8Decode(text[pos.*..pos.* + cp_len]) catch {
            pos.* = start;
            return false;
        };

        if (isLetterCodepoint(codepoint)) {
            found_letter = true;
            pos.* += cp_len;
        } else {
            break;
        }
    }

    if (!found_letter) {
        pos.* = start;
        return false;
    }
    return true;
}

/// \p{N}{1,3} - Numbers in groups of 1-3
fn tryNumberSequence(text: []const u8, pos: *usize) bool {
    const start = pos.*;
    var count: usize = 0;

    while (pos.* < text.len and count < 3 and isDigit(text[pos.*])) {
        pos.* += 1;
        count += 1;
    }

    if (count == 0) {
        pos.* = start;
        return false;
    }
    return true;
}

///  ?[^\s\p{L}\p{N}]+[\r\n]* - Optional space, non-alphanumeric, optional newlines
fn tryNonAlphanumeric(text: []const u8, pos: *usize) bool {
    const start = pos.*;

    // Optional leading space
    if (pos.* < text.len and text[pos.*] == ' ') {
        pos.* += 1;
    }

    // One or more non-whitespace, non-letter, non-digit (UTF-8 aware)
    var found = false;
    while (pos.* < text.len) {
        const cp_len = unicode.utf8ByteSequenceLength(text[pos.*]) catch 1;
        if (pos.* + cp_len > text.len) break;

        const codepoint = unicode.utf8Decode(text[pos.*..pos.* + cp_len]) catch text[pos.*];

        if (isWhitespace(text[pos.*]) or isLetterCodepoint(codepoint) or isDigitCodepoint(codepoint)) break;

        pos.* += cp_len;
        found = true;
    }

    if (!found) {
        pos.* = start;
        return false;
    }

    // Zero or more \r\n
    while (pos.* < text.len and (text[pos.*] == '\r' or text[pos.*] == '\n')) {
        pos.* += 1;
    }

    return true;
}

/// \s*[\r\n]+|\s+(?!\S)|\s+ - Whitespace sequences
fn tryWhitespace(text: []const u8, pos: *usize) bool {
    // \s*[\r\n]+ - Optional whitespace then newlines
    if (pos.* < text.len) {
        const ws_start = pos.*;
        while (pos.* < text.len and isWhitespace(text[pos.*]) and
            text[pos.*] != '\r' and text[pos.*] != '\n')
        {
            pos.* += 1;
        }
        if (pos.* < text.len and (text[pos.*] == '\r' or text[pos.*] == '\n')) {
            while (pos.* < text.len and (text[pos.*] == '\r' or text[pos.*] == '\n')) {
                pos.* += 1;
            }
            return true;
        }
        pos.* = ws_start;
    }

    // \s+(?!\S) - Spaces followed by space or end (leaves one space before non-space)
    if (pos.* < text.len and isWhitespace(text[pos.*])) {
        var count: usize = 0;
        while (pos.* + count < text.len and isWhitespace(text[pos.* + count])) {
            count += 1;
        }

        // If followed by non-whitespace, leave one space for next pattern
        if (pos.* + count < text.len and !isWhitespace(text[pos.* + count])) {
            if (count > 1) {
                pos.* += count - 1;
                return true;
            }
        } else {
            // At end or followed by whitespace - take all
            pos.* += count;
            if (count > 0) return true;
        }
    }

    // \s - Single whitespace (fallback)
    if (pos.* < text.len and isWhitespace(text[pos.*])) {
        pos.* += 1;
        return true;
    }

    return false;
}

/// Unicode letter check using codepoint
inline fn isLetterCodepoint(cp: u21) bool {
    // ASCII letters
    if ((cp >= 'a' and cp <= 'z') or (cp >= 'A' and cp <= 'Z')) return true;

    // Latin-1 Supplement letters (À-ÿ excluding ×÷)
    if (cp >= 0xC0 and cp <= 0xFF and cp != 0xD7 and cp != 0xF7) return true;

    // All other Unicode letters (simplified: most non-ASCII codepoints >= 0x100)
    // This covers CJK, Greek, Cyrillic, Arabic, etc.
    if (cp >= 0x100) {
        // Exclude some known non-letter ranges
        if (cp >= 0x2000 and cp <= 0x206F) return false; // General punctuation
        if (cp >= 0x3000 and cp <= 0x303F) return false; // CJK punctuation
        if (cp >= 0xFE30 and cp <= 0xFE4F) return false; // CJK compat forms
        return true; // Assume letter
    }

    return false;
}

/// Unicode digit check using codepoint
inline fn isDigitCodepoint(cp: u21) bool {
    return cp >= '0' and cp <= '9';
}

/// Simple Unicode letter check (byte-level, for non-UTF-8 paths)
inline fn isLetter(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
        (c >= 'A' and c <= 'Z') or
        (c >= 0xC0 and c <= 0xFF and c != 0xD7 and c != 0xF7);
}

/// Simple digit check (byte-level)
inline fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

/// Whitespace check (byte-level)
inline fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == '\x0b' or c == '\x0c';
}
