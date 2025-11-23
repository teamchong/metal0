const std = @import("std");
const mvzr = @import("src/mvzr.zig");

export fn matchPattern(pattern_ptr: [*]const u8, pattern_len: usize, text_ptr: [*]const u8, text_len: usize) bool {
    const pattern = pattern_ptr[0..pattern_len];
    const text = text_ptr[0..text_len];
    const regex = mvzr.compile(pattern) orelse return false;
    return regex.isMatch(text);
}

export fn findPattern(pattern_ptr: [*]const u8, pattern_len: usize, text_ptr: [*]const u8, text_len: usize, out_start: *usize, out_end: *usize) bool {
    const pattern = pattern_ptr[0..pattern_len];
    const text = text_ptr[0..text_len];
    const regex = mvzr.compile(pattern) orelse return false;
    if (regex.match(text)) |m| {
        out_start.* = m.start;
        out_end.* = m.end;
        return true;
    }
    return false;
}
