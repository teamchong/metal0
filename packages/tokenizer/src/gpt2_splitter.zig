/// GPT-2 text splitter - exact match for HuggingFace ByteLevel pre-tokenizer
/// Pattern: 's|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+
const std = @import("std");
const unicode = std.unicode;

/// Zero-allocation iterator for splitting text into chunks
pub const ChunkIterator = struct {
    text: []const u8,
    pos: usize,

    pub fn init(text: []const u8) ChunkIterator {
        return .{ .text = text, .pos = 0 };
    }

    pub fn next(self: *ChunkIterator) ?[]const u8 {
        if (self.pos >= self.text.len) return null;

        const start = self.pos;

        // Try each pattern in order (GPT-2 pattern order!)
        if (tryContraction(self.text, &self.pos)) {
            return self.text[start..self.pos];
        } else if (tryOptionalSpaceLetters(self.text, &self.pos)) {
            return self.text[start..self.pos];
        } else if (tryOptionalSpaceNumbers(self.text, &self.pos)) {
            return self.text[start..self.pos];
        } else if (tryOptionalSpaceNonAlphanumeric(self.text, &self.pos)) {
            return self.text[start..self.pos];
        } else if (tryWhitespaceNotBeforeNonSpace(self.text, &self.pos)) {
            return self.text[start..self.pos];
        } else if (tryWhitespace(self.text, &self.pos)) {
            return self.text[start..self.pos];
        } else {
            // Fallback: take one byte
            self.pos += 1;
            return self.text[start..self.pos];
        }
    }
};

/// Create an iterator for the text (zero allocations)
pub fn chunks(text: []const u8) ChunkIterator {
    return ChunkIterator.init(text);
}

/// Contractions: 's 't 're 've 'm 'll 'd (case-insensitive)
const CONTRACTIONS = [_][]const u8{ "'s", "'t", "'re", "'ve", "'m", "'ll", "'d" };

fn tryContraction(text: []const u8, pos: *usize) bool {
    if (pos.* >= text.len) return false;
    const c = text[pos.*];
    if (c != '\'') return false;

    const remaining = text[pos.*..];

    inline for (CONTRACTIONS) |pattern| {
        if (remaining.len >= pattern.len) {
            if (std.ascii.eqlIgnoreCase(remaining[0..pattern.len], pattern)) {
                pos.* += pattern.len;
                return true;
            }
        }
    }
    return false;
}

/// ` ?\p{L}+` - Optional space, then one or more letters
fn tryOptionalSpaceLetters(text: []const u8, pos: *usize) bool {
    const start = pos.*;

    // Optional leading space
    if (pos.* < text.len and text[pos.*] == ' ') {
        pos.* += 1;
    }

    // One or more letters
    var found_letter = false;
    while (pos.* < text.len) {
        if (text[pos.*] < 128) {
            if (isLetterASCII(text[pos.*])) {
                found_letter = true;
                pos.* += 1;
            } else {
                break;
            }
        } else {
            const cp_len = unicode.utf8ByteSequenceLength(text[pos.*]) catch break;
            if (pos.* + cp_len > text.len) break;
            const codepoint = unicode.utf8Decode(text[pos.*..][0..cp_len]) catch break;
            if (isLetterCodepoint(codepoint)) {
                found_letter = true;
                pos.* += cp_len;
            } else {
                break;
            }
        }
    }

    if (!found_letter) {
        pos.* = start;
        return false;
    }
    return true;
}

/// ` ?\p{N}+` - Optional space, then one or more numbers
fn tryOptionalSpaceNumbers(text: []const u8, pos: *usize) bool {
    const start = pos.*;

    // Optional leading space
    if (pos.* < text.len and text[pos.*] == ' ') {
        pos.* += 1;
    }

    // One or more digits
    var found_digit = false;
    while (pos.* < text.len and isDigit(text[pos.*])) {
        found_digit = true;
        pos.* += 1;
    }

    if (!found_digit) {
        pos.* = start;
        return false;
    }
    return true;
}

/// ` ?[^\s\p{L}\p{N}]+` - Optional space, then one or more non-whitespace/letter/digit
fn tryOptionalSpaceNonAlphanumeric(text: []const u8, pos: *usize) bool {
    const start = pos.*;

    // Optional leading space
    if (pos.* < text.len and text[pos.*] == ' ') {
        pos.* += 1;
    }

    // One or more non-whitespace, non-letter, non-digit
    var found = false;
    while (pos.* < text.len) {
        const c = text[pos.*];
        if (c < 128) {
            if (isWhitespace(c) or isLetterASCII(c) or isDigit(c)) break;
            pos.* += 1;
            found = true;
        } else {
            const cp_len = unicode.utf8ByteSequenceLength(c) catch 1;
            if (pos.* + cp_len > text.len) break;
            const codepoint = unicode.utf8Decode(text[pos.*..][0..cp_len]) catch c;
            if (isLetterCodepoint(codepoint) or isDigitCodepoint(codepoint)) break;
            pos.* += cp_len;
            found = true;
        }
    }

    if (!found) {
        pos.* = start;
        return false;
    }
    return true;
}

/// `\s+(?!\S)` - Whitespace followed by more whitespace or end
fn tryWhitespaceNotBeforeNonSpace(text: []const u8, pos: *usize) bool {
    if (pos.* >= text.len or !isWhitespace(text[pos.*])) return false;

    const start = pos.*;
    var count: usize = 0;

    while (pos.* + count < text.len and isWhitespace(text[pos.* + count])) {
        count += 1;
    }

    // Must NOT be followed by non-whitespace, OR must leave at least one space
    if (pos.* + count < text.len and !isWhitespace(text[pos.* + count])) {
        // Followed by non-whitespace - leave one space for next pattern
        if (count > 1) {
            pos.* += count - 1;
            return true;
        }
        pos.* = start;
        return false;
    }

    // At end or followed by whitespace - take all
    pos.* += count;
    return count > 0;
}

/// `\s+` - One or more whitespace (fallback)
fn tryWhitespace(text: []const u8, pos: *usize) bool {
    if (pos.* >= text.len or !isWhitespace(text[pos.*])) return false;

    while (pos.* < text.len and isWhitespace(text[pos.*])) {
        pos.* += 1;
    }
    return true;
}

// Character classification helpers
inline fn isLetterASCII(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

inline fn isLetterCodepoint(cp: u21) bool {
    if (cp < 128) return isLetterASCII(@intCast(cp));
    if (cp >= 0xC0 and cp <= 0xFF and cp != 0xD7 and cp != 0xF7) return true;
    if (cp >= 0x100) {
        if (cp >= 0x2000 and cp <= 0x206F) return false;
        if (cp >= 0x3000 and cp <= 0x303F) return false;
        if (cp >= 0x1F300 and cp <= 0x1F9FF) return false;
        return true;
    }
    return false;
}

inline fn isDigitCodepoint(cp: u21) bool {
    return cp >= '0' and cp <= '9';
}

inline fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

inline fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == '\x0b' or c == '\x0c';
}

// Tests
test "gpt2 splitter - hello world" {
    var iter = chunks("Hello world");
    const results = [_][]const u8{ "Hello", " world" };
    for (results) |expected| {
        const got = iter.next();
        try std.testing.expectEqualStrings(expected, got.?);
    }
    try std.testing.expectEqual(@as(?[]const u8, null), iter.next());
}

test "gpt2 splitter - with punctuation" {
    var iter = chunks("Hello, world!");
    const results = [_][]const u8{ "Hello", ",", " world", "!" };
    for (results) |expected| {
        const got = iter.next();
        try std.testing.expectEqualStrings(expected, got.?);
    }
}

test "gpt2 splitter - numbers" {
    var iter = chunks("test 123 foo");
    const results = [_][]const u8{ "test", " 123", " foo" };
    for (results) |expected| {
        const got = iter.next();
        try std.testing.expectEqualStrings(expected, got.?);
    }
}
