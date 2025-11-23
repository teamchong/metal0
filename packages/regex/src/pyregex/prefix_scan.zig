/// Prefix literal scanner for fast regex matching
/// Scans for literal bytes that must appear in matches
const std = @import("std");

/// Find all positions of a literal byte in text
pub fn findAll(text: []const u8, literal: u8, allocator: std.mem.Allocator) ![]usize {
    var positions = std.ArrayList(usize){};

    var pos: usize = 0;
    while (pos < text.len) {
        if (std.mem.indexOfScalarPos(u8, text, pos, literal)) |found_pos| {
            try positions.append(allocator, found_pos);
            pos = found_pos + 1;
        } else {
            break;
        }
    }

    return positions.toOwnedSlice(allocator);
}

/// Create search windows around literal positions
/// For email pattern, we want to search [pos-50..pos+50] around each '@'
pub fn createWindows(literal_positions: []const usize, window_before: usize, window_after: usize, text_len: usize) ![]struct { start: usize, end: usize } {
    var windows = std.ArrayList(struct { start: usize, end: usize }){};

    for (literal_positions) |pos| {
        const start = if (pos >= window_before) pos - window_before else 0;
        const end = @min(pos + window_after + 1, text_len);

        try windows.append(std.heap.page_allocator, .{ .start = start, .end = end });
    }

    return windows.toOwnedSlice(std.heap.page_allocator);
}
