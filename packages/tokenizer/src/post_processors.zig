/// Post-processors with comptime dead code elimination
/// Only post-processors you actually call get compiled into binary
const std = @import("std");
const Allocator = std.mem.Allocator;

/// Template post-processor - adds special tokens using template
/// Used by: BERT ([CLS] text [SEP]), GPT-2 (<|endoftext|>)
pub fn template(
    tokens: []const u32,
    prefix: []const u32,
    suffix: []const u32,
    allocator: Allocator
) ![]u32 {
    const result = try allocator.alloc(u32, prefix.len + tokens.len + suffix.len);

    @memcpy(result[0..prefix.len], prefix);
    @memcpy(result[prefix.len..prefix.len + tokens.len], tokens);
    @memcpy(result[prefix.len + tokens.len..], suffix);

    return result;
}

/// BERT post-processor - adds [CLS] at start, [SEP] at end
/// Format: [CLS] token1 token2 ... [SEP]
pub fn bert(tokens: []const u32, cls_token: u32, sep_token: u32, allocator: Allocator) ![]u32 {
    const prefix = [_]u32{cls_token};
    const suffix = [_]u32{sep_token};
    return template(tokens, &prefix, &suffix, allocator);
}

/// BERT pair post-processor - for sentence pairs
/// Format: [CLS] text_a [SEP] text_b [SEP]
pub fn bertPair(
    tokens_a: []const u32,
    tokens_b: []const u32,
    cls_token: u32,
    sep_token: u32,
    allocator: Allocator
) ![]u32 {
    const total_len = 1 + tokens_a.len + 1 + tokens_b.len + 1;
    const result = try allocator.alloc(u32, total_len);

    var i: usize = 0;
    result[i] = cls_token;
    i += 1;

    @memcpy(result[i..i + tokens_a.len], tokens_a);
    i += tokens_a.len;

    result[i] = sep_token;
    i += 1;

    @memcpy(result[i..i + tokens_b.len], tokens_b);
    i += tokens_b.len;

    result[i] = sep_token;

    return result;
}

/// RoBERTa post-processor - similar to BERT but different tokens
/// Format: <s> text </s>
pub fn roberta(tokens: []const u32, bos_token: u32, eos_token: u32, allocator: Allocator) ![]u32 {
    const prefix = [_]u32{bos_token};
    const suffix = [_]u32{eos_token};
    return template(tokens, &prefix, &suffix, allocator);
}

/// ByteLevel post-processor - handles GPT-2 style byte-level encoding
/// Options:
/// - add_prefix_space: Prepend space token if first token doesn't start with space
/// - trim_offsets: Adjust token offsets (not implemented in this simple version)
pub fn byteLevel(
    tokens: []const u32,
    add_prefix_space: bool,
    trim_offsets: bool,
    allocator: Allocator
) ![]u32 {
    _ = trim_offsets; // Not needed for token-only processing

    // If not adding prefix space, just return copy
    if (!add_prefix_space) {
        return allocator.dupe(u32, tokens);
    }

    // Add space token (typically token ID 220 in GPT-2)
    // For now, we'll prepend a marker token (0) to indicate space
    const result = try allocator.alloc(u32, tokens.len + 1);
    result[0] = 220; // GPT-2 space token (Ġ)
    @memcpy(result[1..], tokens);
    return result;
}

/// ByteLevel post-processor with custom space token
/// Allows specifying the exact token ID for the prefix space
pub fn byteLevelWithSpaceToken(
    tokens: []const u32,
    space_token: u32,
    add_prefix_space: bool,
    allocator: Allocator
) ![]u32 {
    if (!add_prefix_space) {
        return allocator.dupe(u32, tokens);
    }

    const result = try allocator.alloc(u32, tokens.len + 1);
    result[0] = space_token;
    @memcpy(result[1..], tokens);
    return result;
}

/// Sequence post-processor - chains multiple post-processors
pub fn sequence(
    tokens: []const u32,
    processors: []const *const fn([]const u32, Allocator) anyerror![]u32,
    allocator: Allocator
) ![]u32 {
    var current = try allocator.dupe(u32, tokens);

    for (processors) |proc| {
        const next = try proc(current, allocator);
        allocator.free(current);
        current = next;
    }

    return current;
}

test "template post-processor" {
    const allocator = std.testing.allocator;

    const tokens = [_]u32{10, 20, 30};
    const prefix = [_]u32{1}; // [CLS]
    const suffix = [_]u32{2}; // [SEP]

    const result = try template(&tokens, &prefix, &suffix, allocator);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 5), result.len);
    try std.testing.expectEqual(@as(u32, 1), result[0]);
    try std.testing.expectEqual(@as(u32, 10), result[1]);
    try std.testing.expectEqual(@as(u32, 2), result[4]);
}

test "bert post-processor" {
    const allocator = std.testing.allocator;

    const tokens = [_]u32{100, 200};
    const result = try bert(&tokens, 101, 102, allocator); // 101=[CLS], 102=[SEP]
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 4), result.len);
    try std.testing.expectEqual(@as(u32, 101), result[0]);
    try std.testing.expectEqual(@as(u32, 102), result[3]);
}

test "bert pair post-processor" {
    const allocator = std.testing.allocator;

    const tokens_a = [_]u32{10, 20};
    const tokens_b = [_]u32{30, 40};
    const result = try bertPair(&tokens_a, &tokens_b, 101, 102, allocator);
    defer allocator.free(result);

    // [CLS] 10 20 [SEP] 30 40 [SEP]
    try std.testing.expectEqual(@as(usize, 7), result.len);
    try std.testing.expectEqual(@as(u32, 101), result[0]);
    try std.testing.expectEqual(@as(u32, 102), result[3]);
    try std.testing.expectEqual(@as(u32, 102), result[6]);
}

test "byteLevel post-processor" {
    const allocator = std.testing.allocator;

    const tokens = [_]u32{10, 20, 30};

    // Without prefix space
    const result1 = try byteLevel(&tokens, false, false, allocator);
    defer allocator.free(result1);
    try std.testing.expectEqual(@as(usize, 3), result1.len);

    // With prefix space
    const result2 = try byteLevel(&tokens, true, false, allocator);
    defer allocator.free(result2);
    try std.testing.expectEqual(@as(usize, 4), result2.len);
    try std.testing.expectEqual(@as(u32, 220), result2[0]); // Space token
}

test "byteLevelWithSpaceToken post-processor" {
    const allocator = std.testing.allocator;

    const tokens = [_]u32{10, 20};
    const result = try byteLevelWithSpaceToken(&tokens, 999, true, allocator);
    defer allocator.free(result);

    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqual(@as(u32, 999), result[0]); // Custom space token
    try std.testing.expectEqual(@as(u32, 10), result[1]);
}
