/// Optimized HashMap BPE encoder without O(n³) array shifting
/// Uses skip-list approach: mark positions as merged instead of shifting
const std = @import("std");
const hashmap_helper = @import("hashmap_helper.zig");
const Allocator = std.mem.Allocator;

pub fn encodeOptimized(
    allocator: Allocator,
    text: []const u8,
    vocab: *const hashmap_helper.StringHashMap(u32),
    vocab_r: *const std.AutoHashMap(u32, []const u8),
) ![]u32 {
    if (text.len == 0) return &[_]u32{};
    if (text.len == 1) {
        const byte_slice = text[0..1];
        const token = vocab.get(byte_slice) orelse text[0];
        const result = try allocator.alloc(u32, 1);
        result[0] = token;
        return result;
    }

    // Initialize: one token per byte
    var tokens = try allocator.alloc(u32, text.len);
    defer allocator.free(tokens);

    for (text, 0..) |byte, i| {
        const byte_slice = @as(*const [1]u8, &byte)[0..1];
        tokens[i] = vocab.get(byte_slice) orelse byte;
    }

    // Skip array: -1 means active, >=0 means merged (points to next active)
    var skip = try allocator.alloc(i32, text.len);
    defer allocator.free(skip);
    @memset(skip, -1); // All active initially

    var merge_buffer: [512]u8 = undefined;
    var active_count = text.len;

    // Apply merges until no more possible
    while (active_count > 1) {
        var best_rank: u32 = std.math.maxInt(u32);
        var best_pos: usize = 0;
        var best_new_token: u32 = 0;

        // Scan all active adjacent pairs
        var i: usize = 0;
        while (i < tokens.len) {
            if (skip[i] >= 0) {
                // Merged position - skip
                i += 1;
                continue;
            }

            // Find next active position
            var next = i + 1;
            while (next < tokens.len and skip[next] >= 0) : (next += 1) {}

            if (next >= tokens.len) break;

            const left_token = tokens[i];
            const right_token = tokens[next];

            // Try to merge this pair
            const left_bytes = vocab_r.get(left_token) orelse {
                i = next;
                continue;
            };
            const right_bytes = vocab_r.get(right_token) orelse {
                i = next;
                continue;
            };

            const total_len = left_bytes.len + right_bytes.len;
            if (total_len > merge_buffer.len) {
                i = next;
                continue;
            }

            @memcpy(merge_buffer[0..left_bytes.len], left_bytes);
            @memcpy(merge_buffer[left_bytes.len..total_len], right_bytes);

            if (vocab.get(merge_buffer[0..total_len])) |merged_rank| {
                if (merged_rank < best_rank) {
                    best_rank = merged_rank;
                    best_new_token = merged_rank;
                    best_pos = i;
                }
            }

            i = next;
        }

        if (best_rank == std.math.maxInt(u32)) break;

        // Apply best merge
        tokens[best_pos] = best_new_token;

        // Find next active after best_pos to mark as merged
        var next_active = best_pos + 1;
        while (next_active < tokens.len and skip[next_active] >= 0) : (next_active += 1) {}

        if (next_active < tokens.len) {
            skip[next_active] = @intCast(next_active); // Mark as merged
            active_count -= 1;
        }
    }

    // Collect active tokens
    var result = try std.ArrayList(u32).initCapacity(allocator, active_count);
    errdefer result.deinit(allocator);

    for (tokens, 0..) |token, i| {
        if (skip[i] < 0) { // Active position
            result.appendAssumeCapacity(token);
        }
    }

    // Avoid toOwnedSlice overhead - just dupe used portion
    const items = result.items[0..result.items.len];
    const owned = try allocator.dupe(u32, items);
    result.clearRetainingCapacity();
    return owned;
}
