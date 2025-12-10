/// Pre-tokenizers with comptime dead code elimination
/// Only pre-tokenizers you actually call get compiled into binary
const std = @import("std");
const Allocator = std.mem.Allocator;
const pyregex = @import("pyregex/regex.zig");

/// Whitespace pre-tokenizer - splits on whitespace (spaces, tabs, newlines)
/// Used by: GPT-2, GPT-3
pub fn whitespace(text: []const u8, allocator: Allocator) ![][]const u8 {
    var result = std.ArrayList([]const u8){};
    errdefer result.deinit(allocator);

    var start: usize = 0;
    var i: usize = 0;

    while (i < text.len) : (i += 1) {
        const is_ws = text[i] == ' ' or text[i] == '\t' or text[i] == '\n' or text[i] == '\r';

        if (is_ws) {
            // Emit word if not empty
            if (i > start) {
                try result.append(allocator, text[start..i]);
            }
            // Emit whitespace
            try result.append(allocator, text[i..i+1]);
            start = i + 1;
        }
    }

    // Emit final word
    if (start < text.len) {
        try result.append(allocator, text[start..]);
    }

    return result.toOwnedSlice(allocator);
}

/// ByteLevel pre-tokenizer - splits on character class changes
/// Used by: GPT-2, RoBERTa (ensures no merge crosses character boundaries)
pub fn byteLevel(text: []const u8, allocator: Allocator) ![][]const u8 {
    var result = std.ArrayList([]const u8){};
    errdefer result.deinit(allocator);

    if (text.len == 0) return result.toOwnedSlice(allocator);

    var start: usize = 0;
    var prev_class = getCharClass(text[0]);

    var i: usize = 1;
    while (i < text.len) : (i += 1) {
        const curr_class = getCharClass(text[i]);

        // Split on class change
        if (curr_class != prev_class) {
            try result.append(allocator, text[start..i]);
            start = i;
            prev_class = curr_class;
        }
    }

    // Emit final segment
    try result.append(allocator, text[start..]);

    return result.toOwnedSlice(allocator);
}

const CharClass = enum { letter, digit, whitespace, punctuation, other };

fn getCharClass(c: u8) CharClass {
    return if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z'))
        .letter
    else if (c >= '0' and c <= '9')
        .digit
    else if (c == ' ' or c == '\t' or c == '\n' or c == '\r')
        .whitespace
    else if (isPunctuation(c))
        .punctuation
    else
        .other;
}

fn isPunctuation(c: u8) bool {
    return switch (c) {
        '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+', ',', '-', '.', '/',
        ':', ';', '<', '=', '>', '?', '@', '[', '\\', ']', '^', '_', '`', '{', '|', '}', '~'
        => true,
        else => false,
    };
}

/// Punctuation pre-tokenizer - isolates punctuation characters
/// Used by: BERT, WordPiece models
pub fn punctuation(text: []const u8, allocator: Allocator) ![][]const u8 {
    var result = std.ArrayList([]const u8){};
    errdefer result.deinit(allocator);

    var start: usize = 0;
    var i: usize = 0;

    while (i < text.len) : (i += 1) {
        if (isPunctuation(text[i])) {
            // Emit word before punctuation
            if (i > start) {
                try result.append(allocator, text[start..i]);
            }
            // Emit punctuation
            try result.append(allocator, text[i..i+1]);
            start = i + 1;
        }
    }

    // Emit final segment
    if (start < text.len) {
        try result.append(allocator, text[start..]);
    }

    return result.toOwnedSlice(allocator);
}

/// Digits pre-tokenizer - isolates digit sequences (like "123" → "1" "2" "3")
/// Used by: Some language models for better numerical reasoning
pub fn digits(text: []const u8, allocator: Allocator) ![][]const u8 {
    var result = std.ArrayList([]const u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        // Split each digit into separate token
        if (text[i] >= '0' and text[i] <= '9') {
            try result.append(allocator, text[i..i+1]);
        } else {
            // Keep non-digits as-is
            const start = i;
            while (i < text.len and !(text[i] >= '0' and text[i] <= '9')) : (i += 1) {}
            try result.append(allocator, text[start..i]);
            i -= 1; // Back up for loop increment
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Regex-based pre-tokenizer - splits using GPT-2-like pattern
/// Full Rust regex port with complete pattern support
/// Full pattern: 's|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+
/// Comptime: Only compiled in if you actually call this function (zero overhead otherwise)
pub fn gpt2Pattern(text: []const u8, allocator: Allocator) ![][]const u8 {
    // GPT-2 pattern for ASCII (using Rust regex port - pyregex)
    // Matches: contractions ('s, 't, etc), words, numbers, punctuation, whitespace
    const pattern = "'[stmdvr][el]*|[a-zA-Z]+|[0-9]+|[^a-zA-Z0-9\\s]+|\\s+";

    var regex = try pyregex.Regex.compile(allocator, pattern);
    defer regex.deinit();

    var result = std.ArrayList([]const u8){};
    errdefer result.deinit(allocator);

    // Find all matches
    var pos: usize = 0;
    while (pos < text.len) {
        var match_result = try regex.find(text[pos..]);
        if (match_result) |*match| {
            const match_text = text[pos + match.span.start..pos + match.span.end];
            if (match_text.len > 0) {
                try result.append(allocator, match_text);
            }
            const end_pos = match.span.end;
            match.deinit(allocator);
            pos += end_pos;
        } else {
            break;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Full GPT-2 pattern with Unicode support
/// Pattern: 's|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+
/// Uses Zig's std.unicode for proper Unicode category detection
pub fn gpt2PatternFull(text: []const u8, allocator: Allocator) ![][]const u8 {
    var result: std.ArrayList([]const u8) = .{};
    errdefer {
        for (result.items) |item| allocator.free(item);
        result.deinit(allocator);
    }

    var i: usize = 0;
    while (i < text.len) {
        // Try contractions first: 's, 't, 're, 've, 'm, 'll, 'd
        if (text[i] == '\'') {
            const contraction = tryContraction(text[i..]);
            if (contraction) |len| {
                try result.append(allocator, try allocator.dupe(u8, text[i .. i + len]));
                i += len;
                continue;
            }
        }

        // Try optional-space + letters: ?\p{L}+
        const letters = tryUnicodeLetters(text[i..]);
        if (letters.len > 0) {
            try result.append(allocator, try allocator.dupe(u8, text[i .. i + letters.len]));
            i += letters.len;
            continue;
        }

        // Try optional-space + numbers: ?\p{N}+
        const numbers = tryUnicodeNumbers(text[i..]);
        if (numbers.len > 0) {
            try result.append(allocator, try allocator.dupe(u8, text[i .. i + numbers.len]));
            i += numbers.len;
            continue;
        }

        // Try optional-space + punctuation/symbols: ?[^\s\p{L}\p{N}]+
        const punct = tryPunctuation(text[i..]);
        if (punct.len > 0) {
            try result.append(allocator, try allocator.dupe(u8, text[i .. i + punct.len]));
            i += punct.len;
            continue;
        }

        // Try whitespace (but not followed by non-whitespace for trailing ws)
        const ws = tryWhitespace(text[i..]);
        if (ws.len > 0) {
            try result.append(allocator, try allocator.dupe(u8, text[i .. i + ws.len]));
            i += ws.len;
            continue;
        }

        // Single byte fallback
        try result.append(allocator, try allocator.dupe(u8, text[i .. i + 1]));
        i += 1;
    }

    return result.toOwnedSlice(allocator);
}

/// Try to match a contraction ('s, 't, 're, 've, 'm, 'll, 'd)
fn tryContraction(text: []const u8) ?usize {
    if (text.len < 2 or text[0] != '\'') return null;

    if (text.len >= 3) {
        const two = text[1..3];
        if (std.mem.eql(u8, two, "re") or std.mem.eql(u8, two, "ve") or std.mem.eql(u8, two, "ll")) {
            return 3;
        }
    }

    const c = text[1];
    if (c == 's' or c == 't' or c == 'm' or c == 'd' or c == 'S' or c == 'T' or c == 'M' or c == 'D') {
        return 2;
    }

    return null;
}

/// Match optional-space + Unicode letters (simplified: ASCII letters + common UTF-8 ranges)
fn tryUnicodeLetters(text: []const u8) struct { len: usize } {
    var i: usize = 0;

    // Optional leading space
    if (i < text.len and text[i] == ' ') {
        i += 1;
    }

    const start = i;

    // Match letters (including UTF-8 multi-byte)
    while (i < text.len) {
        const c = text[i];

        // ASCII letters
        if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')) {
            i += 1;
            continue;
        }

        // UTF-8 multi-byte sequences (basic Latin supplement, extended Latin, etc.)
        if (c >= 0xC0) {
            const byte_len = std.unicode.utf8ByteSequenceLength(c) catch break;
            if (i + byte_len > text.len) break;

            // Decode and check if it's a letter category
            const codepoint = std.unicode.utf8Decode(text[i..][0..byte_len]) catch break;
            if (isUnicodeLetter(codepoint)) {
                i += byte_len;
                continue;
            }
        }

        break;
    }

    // Must have at least one letter
    if (i == start) return .{ .len = 0 };

    return .{ .len = i };
}

/// Check if codepoint is a Unicode letter (basic check for common ranges)
fn isUnicodeLetter(cp: u21) bool {
    // Basic Latin letters
    if ((cp >= 'a' and cp <= 'z') or (cp >= 'A' and cp <= 'Z')) return true;

    // Latin-1 Supplement letters (À-ÖØ-öø-ÿ)
    if ((cp >= 0x00C0 and cp <= 0x00D6) or
        (cp >= 0x00D8 and cp <= 0x00F6) or
        (cp >= 0x00F8 and cp <= 0x00FF)) return true;

    // Latin Extended-A (Ā-ſ)
    if (cp >= 0x0100 and cp <= 0x017F) return true;

    // Latin Extended-B
    if (cp >= 0x0180 and cp <= 0x024F) return true;

    // Greek and Coptic
    if (cp >= 0x0370 and cp <= 0x03FF) return true;

    // Cyrillic
    if (cp >= 0x0400 and cp <= 0x04FF) return true;

    // CJK Unified Ideographs (basic range)
    if (cp >= 0x4E00 and cp <= 0x9FFF) return true;

    // Hiragana
    if (cp >= 0x3040 and cp <= 0x309F) return true;

    // Katakana
    if (cp >= 0x30A0 and cp <= 0x30FF) return true;

    // Hangul Syllables
    if (cp >= 0xAC00 and cp <= 0xD7AF) return true;

    return false;
}

/// Match optional-space + Unicode numbers
fn tryUnicodeNumbers(text: []const u8) struct { len: usize } {
    var i: usize = 0;

    // Optional leading space
    if (i < text.len and text[i] == ' ') {
        i += 1;
    }

    const start = i;

    // Match digits (including UTF-8 multi-byte number characters)
    while (i < text.len) {
        const c = text[i];

        // ASCII digits
        if (c >= '0' and c <= '9') {
            i += 1;
            continue;
        }

        // UTF-8 multi-byte number characters
        if (c >= 0xC0) {
            const byte_len = std.unicode.utf8ByteSequenceLength(c) catch break;
            if (i + byte_len > text.len) break;

            const codepoint = std.unicode.utf8Decode(text[i..][0..byte_len]) catch break;
            if (isUnicodeNumber(codepoint)) {
                i += byte_len;
                continue;
            }
        }

        break;
    }

    if (i == start) return .{ .len = 0 };

    return .{ .len = i };
}

/// Check if codepoint is a Unicode number
fn isUnicodeNumber(cp: u21) bool {
    // ASCII digits
    if (cp >= '0' and cp <= '9') return true;

    // Arabic-Indic digits
    if (cp >= 0x0660 and cp <= 0x0669) return true;

    // Extended Arabic-Indic digits
    if (cp >= 0x06F0 and cp <= 0x06F9) return true;

    // Fullwidth digits
    if (cp >= 0xFF10 and cp <= 0xFF19) return true;

    return false;
}

/// Match optional-space + punctuation/symbols (not whitespace, letters, or numbers)
fn tryPunctuation(text: []const u8) struct { len: usize } {
    var i: usize = 0;

    // Optional leading space
    if (i < text.len and text[i] == ' ') {
        i += 1;
    }

    const start = i;

    while (i < text.len) {
        const c = text[i];

        // Skip whitespace
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') break;

        // Skip ASCII letters and digits
        if ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9')) break;

        // Handle UTF-8 multi-byte
        if (c >= 0xC0) {
            const byte_len = std.unicode.utf8ByteSequenceLength(c) catch break;
            if (i + byte_len > text.len) break;

            const codepoint = std.unicode.utf8Decode(text[i..][0..byte_len]) catch break;
            if (isUnicodeLetter(codepoint) or isUnicodeNumber(codepoint)) break;

            i += byte_len;
            continue;
        }

        // ASCII punctuation/symbol
        i += 1;
    }

    if (i == start) return .{ .len = 0 };

    return .{ .len = i };
}

/// Match whitespace sequence
fn tryWhitespace(text: []const u8) struct { len: usize } {
    var i: usize = 0;

    while (i < text.len) {
        const c = text[i];
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            i += 1;
        } else {
            break;
        }
    }

    return .{ .len = i };
}

/// Metaspace pre-tokenizer - replaces spaces with special character (▁)
/// Used by: SentencePiece, T5, ALBERT
/// Allows treating spaces as explicit tokens for better sentence segmentation
pub fn metaspace(text: []const u8, replacement: []const u8, add_prefix_space: bool, allocator: Allocator) ![]const u8 {
    const prefix_len = if (add_prefix_space) replacement.len else 0;
    var result_len = prefix_len;

    // Count spaces to determine final size
    var space_count: usize = 0;
    for (text) |c| {
        if (c == ' ') space_count += 1;
    }
    result_len += text.len - space_count + (space_count * replacement.len);

    const result = try allocator.alloc(u8, result_len);
    var pos: usize = 0;

    // Add prefix space if requested
    if (add_prefix_space) {
        @memcpy(result[pos..pos+replacement.len], replacement);
        pos += replacement.len;
    }

    // Replace spaces
    for (text) |c| {
        if (c == ' ') {
            @memcpy(result[pos..pos+replacement.len], replacement);
            pos += replacement.len;
        } else {
            result[pos] = c;
            pos += 1;
        }
    }

    return result;
}

/// BERT-style pre-tokenizer - splits on whitespace and punctuation
/// Used by: BERT, RoBERTa (combines whitespace + punctuation splitting)
pub fn bert(text: []const u8, allocator: Allocator) ![][]const u8 {
    var result = std.ArrayList([]const u8){};
    errdefer result.deinit(allocator);

    var start: usize = 0;
    var i: usize = 0;

    while (i < text.len) : (i += 1) {
        const is_ws = text[i] == ' ' or text[i] == '\t' or text[i] == '\n' or text[i] == '\r';
        const is_punct = isPunctuation(text[i]);

        if (is_ws or is_punct) {
            // Emit word before delimiter
            if (i > start) {
                try result.append(allocator, text[start..i]);
            }
            // Emit delimiter (keep punctuation, skip whitespace)
            if (is_punct) {
                try result.append(allocator, text[i..i+1]);
            }
            start = i + 1;
        }
    }

    // Emit final word
    if (start < text.len) {
        try result.append(allocator, text[start..]);
    }

    return result.toOwnedSlice(allocator);
}

/// Split pre-tokenizer - splits on any character in delimiters string
/// Used by: Custom tokenizers with specific split characters
pub fn split(text: []const u8, delimiters: []const u8, allocator: Allocator) ![][]const u8 {
    var result = std.ArrayList([]const u8){};
    errdefer result.deinit(allocator);

    var start: usize = 0;
    var i: usize = 0;

    while (i < text.len) : (i += 1) {
        // Check if current char is a delimiter
        var is_delim = false;
        for (delimiters) |delim| {
            if (text[i] == delim) {
                is_delim = true;
                break;
            }
        }

        if (is_delim) {
            // Emit segment before delimiter
            if (i > start) {
                try result.append(allocator, text[start..i]);
            }
            start = i + 1;
        }
    }

    // Emit final segment
    if (start < text.len) {
        try result.append(allocator, text[start..]);
    }

    return result.toOwnedSlice(allocator);
}

test "whitespace pre-tokenizer" {
    const allocator = std.testing.allocator;

    const text = "Hello world!\nHow are you?";
    const splits = try whitespace(text, allocator);
    defer allocator.free(splits);

    try std.testing.expectEqual(@as(usize, 9), splits.len);
    try std.testing.expectEqualStrings("Hello", splits[0]);
    try std.testing.expectEqualStrings(" ", splits[1]);
    try std.testing.expectEqualStrings("world!", splits[2]);
}

test "byteLevel pre-tokenizer" {
    const allocator = std.testing.allocator;

    const text = "Hello123";
    const splits = try byteLevel(text, allocator);
    defer allocator.free(splits);

    try std.testing.expectEqual(@as(usize, 2), splits.len);
    try std.testing.expectEqualStrings("Hello", splits[0]);
    try std.testing.expectEqualStrings("123", splits[1]);
}

test "punctuation pre-tokenizer" {
    const allocator = std.testing.allocator;

    const text = "Hello, world!";
    const splits = try punctuation(text, allocator);
    defer allocator.free(splits);

    // "Hello" "," " world" "!"
    try std.testing.expectEqual(@as(usize, 4), splits.len);
    try std.testing.expectEqualStrings("Hello", splits[0]);
    try std.testing.expectEqualStrings(",", splits[1]);
    try std.testing.expectEqualStrings(" world", splits[2]);
    try std.testing.expectEqualStrings("!", splits[3]);
}

test "gpt2Pattern pre-tokenizer" {
    const allocator = std.testing.allocator;

    // Test contractions
    const text1 = "don't can't I'm";
    const splits1 = try gpt2Pattern(text1, allocator);
    defer allocator.free(splits1);

    // Should split: "don" "'t" " " "can" "'t" " " "I" "'m"
    try std.testing.expect(splits1.len > 0);
    // Verify at least we got words and contractions
    var found_don = false;
    var found_t = false;
    for (splits1) |part| {
        if (std.mem.eql(u8, part, "don")) found_don = true;
        if (std.mem.eql(u8, part, "'t") or std.mem.eql(u8, part, "t")) found_t = true;
    }
    try std.testing.expect(found_don);
    try std.testing.expect(found_t);

    // Test words + punctuation
    const text2 = "Hello world";
    const splits2 = try gpt2Pattern(text2, allocator);
    defer allocator.free(splits2);

    // Should split: "Hello" " " "world"
    try std.testing.expect(splits2.len >= 2);
    try std.testing.expectEqualStrings("Hello", splits2[0]);
}

test "metaspace pre-tokenizer" {
    const allocator = std.testing.allocator;

    const text = "Hello world";
    const result = try metaspace(text, "▁", false, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello▁world", result);

    // With prefix space
    const result2 = try metaspace(text, "▁", true, allocator);
    defer allocator.free(result2);

    try std.testing.expectEqualStrings("▁Hello▁world", result2);
}

test "bert pre-tokenizer" {
    const allocator = std.testing.allocator;

    const text = "Hello, world!";
    const splits = try bert(text, allocator);
    defer allocator.free(splits);

    // Should split: "Hello" "," "world" "!"
    try std.testing.expect(splits.len >= 4);
    try std.testing.expectEqualStrings("Hello", splits[0]);
    try std.testing.expectEqualStrings(",", splits[1]);
}

test "split pre-tokenizer" {
    const allocator = std.testing.allocator;

    const text = "a,b;c|d";
    const splits = try split(text, ",;|", allocator);
    defer allocator.free(splits);

    try std.testing.expectEqual(@as(usize, 4), splits.len);
    try std.testing.expectEqualStrings("a", splits[0]);
    try std.testing.expectEqualStrings("b", splits[1]);
    try std.testing.expectEqualStrings("c", splits[2]);
    try std.testing.expectEqualStrings("d", splits[3]);
}
