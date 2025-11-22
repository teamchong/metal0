/// Custom text splitter for cl100k_base pattern - OPTIMIZED
/// Pure Zig, no regex - implements the specific rules manually
/// Pattern: (?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}{1,3}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+
const std = @import("std");
const Allocator = std.mem.Allocator;
const unicode = std.unicode;

/// Zero-allocation iterator for splitting text into chunks
pub const ChunkIterator = struct {
    text: []const u8,
    pos: usize,

    pub fn init(text: []const u8) ChunkIterator {
        return .{ .text = text, .pos = 0 };
    }

    pub fn next(self: *ChunkIterator) ?[]const u8 {
        @setRuntimeSafety(false);

        if (self.pos >= self.text.len) return null;

        const start = self.pos;

        // Try each pattern in order (MUST match regex pattern order!)
        if (tryContraction(self.text, &self.pos)) {
            return self.text[start..self.pos];
        } else if (tryLetterSequence(self.text, &self.pos)) {
            return self.text[start..self.pos];
        } else if (tryNumberSequence(self.text, &self.pos)) {
            return self.text[start..self.pos];
        } else if (tryNonAlphanumeric(self.text, &self.pos)) {
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

/// DEPRECATED: Allocates an array of chunks (kept for backwards compatibility)
pub fn split(allocator: Allocator, text: []const u8) ![][]const u8 {
    @setRuntimeSafety(false); // UNSAFE: Max speed!

    var chunk_list = std.ArrayList([]const u8){};
    errdefer chunk_list.deinit(allocator);

    var iter = chunks(text);
    while (iter.next()) |chunk| {
        try chunk_list.append(allocator, chunk);
    }

    return try chunk_list.toOwnedSlice(allocator);
}

/// Contractions - comptime array for fast lookup
const CONTRACTIONS = [_][]const u8{ "'s", "'t", "'re", "'ve", "'m", "'ll", "'d" };

/// Check for contractions: 's 't 're 've 'm 'll 'd (case-insensitive)
inline fn tryContraction(text: []const u8, pos: *usize) bool {
    @setRuntimeSafety(false);

    if (pos.* >= text.len) return false;
    const c = text[pos.*];
    if (c != '\'' and c != 0xE2) return false; // ' or first byte of '

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

/// [^\r\n\p{L}\p{N}]?\p{L}+ - Optional non-letter/digit/newline, then letters
fn tryLetterSequence(text: []const u8, pos: *usize) bool {
    @setRuntimeSafety(false);

    const start = pos.*;
    var found_letter = false;

    // Fast path: ASCII only (>95% of text)
    if (pos.* < text.len and text[pos.*] < 128) {
        // Optional non-letter/digit ASCII
        if (!isLetterASCII(text[pos.*]) and !isDigit(text[pos.*]) and
            text[pos.*] != '\r' and text[pos.*] != '\n') {
            pos.* += 1;
        }

        // One or more ASCII letters
        while (pos.* < text.len and isLetterASCII(text[pos.*])) {
            found_letter = true;
            pos.* += 1;
        }

        if (found_letter) return true;
        pos.* = start; // Reset for UTF-8 path
    }

    // Slow path: UTF-8
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

    // One or more letters (UTF-8)
    while (pos.* < text.len) {
        // Fast check: ASCII letter
        if (text[pos.*] < 128) {
            if (isLetterASCII(text[pos.*])) {
                found_letter = true;
                pos.* += 1;
            } else {
                break;
            }
        } else {
            // UTF-8 letter
            const cp_len = unicode.utf8ByteSequenceLength(text[pos.*]) catch {
                pos.* = start;
                return false;
            };
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
    }

    if (!found_letter) {
        pos.* = start;
        return false;
    }
    return true;
}

/// \p{N}{1,3} - Numbers in groups of 1-3
inline fn tryNumberSequence(text: []const u8, pos: *usize) bool {
    @setRuntimeSafety(false);

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
    @setRuntimeSafety(false);

    const start = pos.*;

    // Optional leading space
    if (pos.* < text.len and text[pos.*] == ' ') {
        pos.* += 1;
    }

    // One or more non-whitespace, non-letter, non-digit
    var found = false;

    // Fast path: ASCII
    while (pos.* < text.len and text[pos.*] < 128) {
        const c = text[pos.*];
        if (isWhitespace(c) or isLetterASCII(c) or isDigit(c)) break;
        pos.* += 1;
        found = true;
    }

    // Slow path: UTF-8
    while (pos.* < text.len and text[pos.*] >= 128) {
        const cp_len = unicode.utf8ByteSequenceLength(text[pos.*]) catch 1;
        if (pos.* + cp_len > text.len) break;

        const codepoint = unicode.utf8Decode(text[pos.*..pos.* + cp_len]) catch text[pos.*];
        if (isLetterCodepoint(codepoint) or isDigitCodepoint(codepoint)) break;

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
    @setRuntimeSafety(false);

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

// ============================================================================
// Fast character classification using lookup tables
// ============================================================================

/// ASCII letter check - optimized with comptime
inline fn isLetterASCII(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

/// Unicode letter check using codepoint
inline fn isLetterCodepoint(cp: u21) bool {
    // ASCII letters (fast path)
    if (cp < 128) return isLetterASCII(@as(u8, @intCast(cp)));

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

/// Digit check (byte-level)
inline fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

/// Whitespace check (byte-level)
inline fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == '\x0b' or c == '\x0c';
}
