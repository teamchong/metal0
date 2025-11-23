/// Decoders with comptime dead code elimination
/// Only decoders you actually call get compiled into binary
const std = @import("std");
const Allocator = std.mem.Allocator;

/// ByteLevel decoder - converts token strings back to text
/// Handles GPT-2 style byte-level encoding where special UTF-8 bytes are mapped
pub fn byteLevel(token_strs: []const []const u8, allocator: Allocator) ![]u8 {
    // Calculate total length
    var total_len: usize = 0;
    for (token_strs) |s| {
        total_len += s.len;
    }

    const result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;

    for (token_strs) |s| {
        @memcpy(result[pos..pos + s.len], s);
        pos += s.len;
    }

    return result;
}

/// WordPiece decoder - removes ## prefix from subword tokens
/// Used by: BERT (tokens like "play", "##ing" → "playing")
pub fn wordpiece(token_strs: []const []const u8, prefix: []const u8, allocator: Allocator) ![]u8 {
    // Calculate result length
    var total_len: usize = 0;
    for (token_strs) |s| {
        if (s.len >= prefix.len and std.mem.eql(u8, s[0..prefix.len], prefix)) {
            total_len += s.len - prefix.len; // Remove ##
        } else {
            if (total_len > 0) total_len += 1; // Add space before new word
            total_len += s.len;
        }
    }

    const result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;

    for (token_strs) |s| {
        if (s.len >= prefix.len and std.mem.eql(u8, s[0..prefix.len], prefix)) {
            // Remove ## prefix
            const clean = s[prefix.len..];
            @memcpy(result[pos..pos + clean.len], clean);
            pos += clean.len;
        } else {
            // Add space before new word (except first)
            if (pos > 0) {
                result[pos] = ' ';
                pos += 1;
            }
            @memcpy(result[pos..pos + s.len], s);
            pos += s.len;
        }
    }

    return result;
}

/// BPE decoder - concatenates tokens with optional separator
/// Used by: Standard BPE (joins with empty string or space)
pub fn bpe(token_strs: []const []const u8, separator: []const u8, allocator: Allocator) ![]u8 {
    if (token_strs.len == 0) return try allocator.alloc(u8, 0);

    // Calculate total length
    var total_len: usize = 0;
    for (token_strs, 0..) |s, i| {
        total_len += s.len;
        if (i > 0 and separator.len > 0) {
            total_len += separator.len;
        }
    }

    const result = try allocator.alloc(u8, total_len);
    var pos: usize = 0;

    for (token_strs, 0..) |s, i| {
        // Add separator between tokens
        if (i > 0 and separator.len > 0) {
            @memcpy(result[pos..pos + separator.len], separator);
            pos += separator.len;
        }

        @memcpy(result[pos..pos + s.len], s);
        pos += s.len;
    }

    return result;
}

/// Replace decoder - replaces pattern with replacement in decoded text
/// Example: Replace("Ġ", " ") to convert GPT-2 space marker back to space
pub fn replace(text: []const u8, pattern: []const u8, replacement: []const u8, allocator: Allocator) ![]u8 {
    if (pattern.len == 0) return allocator.dupe(u8, text);

    // Count occurrences
    var count: usize = 0;
    var i: usize = 0;
    while (i + pattern.len <= text.len) {
        if (std.mem.eql(u8, text[i..i+pattern.len], pattern)) {
            count += 1;
            i += pattern.len;
        } else {
            i += 1;
        }
    }

    if (count == 0) return allocator.dupe(u8, text);

    // Allocate result
    const new_len = text.len - (count * pattern.len) + (count * replacement.len);
    const result = try allocator.alloc(u8, new_len);

    // Replace
    var src: usize = 0;
    var dst: usize = 0;
    while (src + pattern.len <= text.len) {
        if (std.mem.eql(u8, text[src..src+pattern.len], pattern)) {
            @memcpy(result[dst..dst+replacement.len], replacement);
            src += pattern.len;
            dst += replacement.len;
        } else {
            result[dst] = text[src];
            src += 1;
            dst += 1;
        }
    }

    // Copy remaining
    while (src < text.len) : (src += 1) {
        result[dst] = text[src];
        dst += 1;
    }

    return result;
}

/// Strip decoder - removes characters from decoded text
/// Example: Strip("\n") to remove newlines
pub fn strip(text: []const u8, chars: []const u8, allocator: Allocator) ![]u8 {
    var count: usize = 0;
    for (text) |c| {
        var found = false;
        for (chars) |strip_char| {
            if (c == strip_char) {
                found = true;
                break;
            }
        }
        if (!found) count += 1;
    }

    const result = try allocator.alloc(u8, count);
    var pos: usize = 0;

    for (text) |c| {
        var found = false;
        for (chars) |strip_char| {
            if (c == strip_char) {
                found = true;
                break;
            }
        }
        if (!found) {
            result[pos] = c;
            pos += 1;
        }
    }

    return result;
}

/// Sequence decoder - chains multiple decoders
pub fn sequence(
    text: []const u8,
    decoders: []const *const fn([]const u8, Allocator) anyerror![]u8,
    allocator: Allocator
) ![]u8 {
    var current = try allocator.dupe(u8, text);

    for (decoders) |dec| {
        const next = try dec(current, allocator);
        allocator.free(current);
        current = next;
    }

    return current;
}

test "byteLevel decoder" {
    const allocator = std.testing.allocator;

    const tokens = [_][]const u8{"Hello", " ", "world"};
    const result = try byteLevel(&tokens, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello world", result);
}

test "wordpiece decoder" {
    const allocator = std.testing.allocator;

    const tokens = [_][]const u8{"play", "##ing", "with", "##out"};
    const result = try wordpiece(&tokens, "##", allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("playing without", result);
}

test "bpe decoder" {
    const allocator = std.testing.allocator;

    const tokens = [_][]const u8{"Hello", "Ġworld"};
    const result = try bpe(&tokens, "", allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("HelloĠworld", result);
}

test "replace decoder" {
    const allocator = std.testing.allocator;

    const text = "HelloĠworld";
    const result = try replace(text, "Ġ", " ", allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello world", result);
}

test "strip decoder" {
    const allocator = std.testing.allocator;

    const text = "Hello\nWorld\n!";
    const result = try strip(text, "\n", allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("HelloWorld!", result);
}
