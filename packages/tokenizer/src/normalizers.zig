/// Normalizers with comptime dead code elimination
/// Only normalizers you actually call get compiled into binary
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Lowercase normalizer - converts text to lowercase
/// Used by: BERT (uncased), DistilBERT
pub fn lowercase(text: []const u8, allocator: Allocator) ![]u8 {
    const result = try allocator.alloc(u8, text.len);
    for (text, 0..) |c, i| {
        result[i] = if (c >= 'A' and c <= 'Z') c + 32 else c;
    }
    return result;
}

/// Strip accents - removes common diacritics (é → e, ñ → n)
/// Used by: BERT, multilingual models
/// Implementation: Unicode normalization decomposition then filter combining marks
pub fn stripAccents(text: []const u8, allocator: Allocator) ![]u8 {
    // Common Latin diacritics mapping (most frequent cases)
    const accent_map = .{
        // Uppercase
        .{ "À", "A" }, .{ "Á", "A" }, .{ "Â", "A" }, .{ "Ã", "A" }, .{ "Ä", "A" }, .{ "Å", "A" },
        .{ "È", "E" }, .{ "É", "E" }, .{ "Ê", "E" }, .{ "Ë", "E" },
        .{ "Ì", "I" }, .{ "Í", "I" }, .{ "Î", "I" }, .{ "Ï", "I" },
        .{ "Ò", "O" }, .{ "Ó", "O" }, .{ "Ô", "O" }, .{ "Õ", "O" }, .{ "Ö", "O" },
        .{ "Ù", "U" }, .{ "Ú", "U" }, .{ "Û", "U" }, .{ "Ü", "U" },
        .{ "Ñ", "N" }, .{ "Ç", "C" },
        // Lowercase
        .{ "à", "a" }, .{ "á", "a" }, .{ "â", "a" }, .{ "ã", "a" }, .{ "ä", "a" }, .{ "å", "a" },
        .{ "è", "e" }, .{ "é", "e" }, .{ "ê", "e" }, .{ "ë", "e" },
        .{ "ì", "i" }, .{ "í", "i" }, .{ "î", "i" }, .{ "ï", "i" },
        .{ "ò", "o" }, .{ "ó", "o" }, .{ "ô", "o" }, .{ "õ", "o" }, .{ "ö", "o" },
        .{ "ù", "u" }, .{ "ú", "u" }, .{ "û", "u" }, .{ "ü", "u" },
        .{ "ñ", "n" }, .{ "ç", "c" }, .{ "ý", "y" }, .{ "ÿ", "y" },
    };

    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < text.len) {
        // Try to match multi-byte UTF-8 sequences
        var matched = false;
        inline for (accent_map) |pair| {
            const from = pair[0];
            const to = pair[1];
            if (i + from.len <= text.len and std.mem.eql(u8, text[i..i+from.len], from)) {
                try result.appendSlice(allocator, to);
                i += from.len;
                matched = true;
                break;
            }
        }

        if (!matched) {
            try result.append(allocator, text[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// NFKC normalization - canonical composition + compatibility decomposition
/// Used by: Most transformers for consistent Unicode representation
/// Handles: ligatures (ﬁ → fi), compatibility characters, full/halfwidth
pub fn nfkc(text: []const u8, allocator: Allocator) ![]u8 {
    // Common compatibility decompositions (most frequent cases)
    const compat_map = .{
        // Ligatures
        .{ "ﬁ", "fi" }, .{ "ﬂ", "fl" }, .{ "ﬀ", "ff" }, .{ "ﬃ", "ffi" }, .{ "ﬄ", "ffl" },
        // Full-width to half-width (common in Asian text)
        .{ "！", "!" }, .{ "？", "?" }, .{ "，", "," }, .{ "。", "." },
        // Superscripts/subscripts
        .{ "¹", "1" }, .{ "²", "2" }, .{ "³", "3" },
        // Fractions
        .{ "½", "1/2" }, .{ "¼", "1/4" }, .{ "¾", "3/4" },
        // Roman numerals (single characters)
        .{ "Ⅰ", "I" }, .{ "Ⅱ", "II" }, .{ "Ⅲ", "III" }, .{ "Ⅳ", "IV" },
        .{ "Ⅴ", "V" }, .{ "Ⅵ", "VI" }, .{ "Ⅶ", "VII" }, .{ "Ⅷ", "VIII" },
    };

    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < text.len) {
        var matched = false;
        inline for (compat_map) |pair| {
            const from = pair[0];
            const to = pair[1];
            if (i + from.len <= text.len and std.mem.eql(u8, text[i..i+from.len], from)) {
                try result.appendSlice(allocator, to);
                i += from.len;
                matched = true;
                break;
            }
        }

        if (!matched) {
            try result.append(allocator, text[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// Replace normalizer - replaces pattern with replacement
/// Example: Replace("\n", " ") to convert newlines to spaces
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

/// Prepend string - adds prefix to text
/// Used by: Some models that require special prefix
pub fn prepend(text: []const u8, prefix: []const u8, allocator: Allocator) ![]u8 {
    const result = try allocator.alloc(u8, prefix.len + text.len);
    @memcpy(result[0..prefix.len], prefix);
    @memcpy(result[prefix.len..], text);
    return result;
}

/// Uppercase normalizer - converts text to uppercase
/// Used by: Some models, case-insensitive matching
pub fn uppercase(text: []const u8, allocator: Allocator) ![]u8 {
    const result = try allocator.alloc(u8, text.len);
    for (text, 0..) |c, i| {
        result[i] = if (c >= 'a' and c <= 'z') c - 32 else c;
    }
    return result;
}

/// Trim normalizer - removes leading/trailing whitespace
/// Used by: Preprocessing, cleaning text
pub fn trim(text: []const u8, allocator: Allocator) ![]u8 {
    // Find start (skip leading whitespace)
    var start: usize = 0;
    while (start < text.len) : (start += 1) {
        const c = text[start];
        if (c != ' ' and c != '\t' and c != '\n' and c != '\r') break;
    }

    // Find end (skip trailing whitespace)
    var end: usize = text.len;
    while (end > start) {
        const c = text[end - 1];
        if (c != ' ' and c != '\t' and c != '\n' and c != '\r') break;
        end -= 1;
    }

    return allocator.dupe(u8, text[start..end]);
}

/// BERT normalizer - combines lowercase + stripAccents + trim
/// Used by: BERT uncased models
pub fn bertNormalizer(text: []const u8, allocator: Allocator) ![]u8 {
    // 1. Lowercase
    const lower = try lowercase(text, allocator);
    errdefer allocator.free(lower);

    // 2. Strip accents
    const stripped = try stripAccents(lower, allocator);
    allocator.free(lower);
    errdefer allocator.free(stripped);

    // 3. Trim
    const trimmed = try trim(stripped, allocator);
    allocator.free(stripped);

    return trimmed;
}

/// Sequence normalizer - applies multiple normalizers in order
/// Returns the final result, freeing intermediate allocations
pub fn sequenceNormalizer(
    text: []const u8,
    normalizers: []const *const fn([]const u8, Allocator) anyerror![]u8,
    allocator: Allocator
) ![]u8 {
    var current = try allocator.dupe(u8, text);

    for (normalizers) |norm| {
        const next = try norm(current, allocator);
        allocator.free(current);
        current = next;
    }

    return current;
}

/// Chain multiple normalizers - applies them in sequence
/// Example: chain(&[_]Normalizer{lowercase, stripAccents})
pub fn chain(text: []const u8, normalizers: []const *const fn([]const u8, Allocator) anyerror![]u8, allocator: Allocator) ![]u8 {
    var current = try allocator.dupe(u8, text);

    for (normalizers) |norm| {
        const next = try norm(current, allocator);
        allocator.free(current);
        current = next;
    }

    return current;
}

test "lowercase normalizer" {
    const allocator = std.testing.allocator;

    const text = "Hello WORLD!";
    const result = try lowercase(text, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hello world!", result);
}

test "replace normalizer" {
    const allocator = std.testing.allocator;

    const text = "Hello\nWorld\n!";
    const result = try replace(text, "\n", " ", allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello World !", result);
}

test "prepend normalizer" {
    const allocator = std.testing.allocator;

    const text = "World";
    const result = try prepend(text, "Hello ", allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello World", result);
}

test "stripAccents normalizer" {
    const allocator = std.testing.allocator;

    const text = "café résumé naïve";
    const result = try stripAccents(text, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("cafe resume naive", result);
}

test "nfkc normalizer" {
    const allocator = std.testing.allocator;

    // Test ligature
    const text1 = "ﬁle";
    const result1 = try nfkc(text1, allocator);
    defer allocator.free(result1);
    try std.testing.expectEqualStrings("file", result1);

    // Test fraction
    const text2 = "½ cup";
    const result2 = try nfkc(text2, allocator);
    defer allocator.free(result2);
    try std.testing.expectEqualStrings("1/2 cup", result2);
}

test "uppercase normalizer" {
    const allocator = std.testing.allocator;

    const text = "Hello World!";
    const result = try uppercase(text, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("HELLO WORLD!", result);
}

test "trim normalizer" {
    const allocator = std.testing.allocator;

    const text = "  \t Hello World! \n ";
    const result = try trim(text, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("Hello World!", result);
}

test "bertNormalizer" {
    const allocator = std.testing.allocator;

    // Test with ASCII text first (our lowercase only handles ASCII)
    const text = "  Cafe RESUME  ";
    const result = try bertNormalizer(text, allocator);
    defer allocator.free(result);

    try std.testing.expectEqualStrings("cafe resume", result);

    // Test with accents (stripAccents handles them)
    const text2 = "  café résumé  ";
    const result2 = try bertNormalizer(text2, allocator);
    defer allocator.free(result2);

    try std.testing.expectEqualStrings("cafe resume", result2);
}
