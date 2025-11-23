/// Simple greedy longest-match encoder
/// No backtracking - just matches longest token at each position
/// Fast but may not be 100% correct without pair validation
const std = @import("std");
const hashmap_helper = @import("hashmap_helper.zig");
const Allocator = std.mem.Allocator;

pub fn encodeGreedy(
    allocator: Allocator,
    text: []const u8,
    vocab: *const hashmap_helper.StringHashMap(u32),
) ![]u32 {
    var tokens = std.ArrayList(u32){};
    try tokens.ensureTotalCapacity(allocator, text.len / 3);
    defer tokens.deinit(allocator);

    var pos: usize = 0;
    while (pos < text.len) {
        // Find longest match starting at current position
        var best_token: ?u32 = null;
        var best_len: usize = 0;

        // Try all possible lengths from longest to shortest
        var max_len = @min(text.len - pos, 512); // Cap at 512 bytes
        while (max_len > 0) : (max_len -= 1) {
            const slice = text[pos .. pos + max_len];
            if (vocab.get(slice)) |token| {
                best_token = token;
                best_len = max_len;
                break;
            }
        }

        if (best_token) |token| {
            // Found a match - use it
            try tokens.append(allocator, token);
            pos += best_len;
        } else {
            // No match - use raw byte
            const byte = text[pos];
            try tokens.append(allocator, byte);
            pos += 1;
        }
    }

    // Avoid toOwnedSlice overhead - just dupe used portion
    const items = tokens.items[0..tokens.items.len];
    const owned = try allocator.dupe(u32, items);
    tokens.clearRetainingCapacity();
    return owned;
}
