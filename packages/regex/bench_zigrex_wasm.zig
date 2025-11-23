const std = @import("std");
const regex_mod = @import("src/zig-regex/root.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

export fn matchPattern(pattern_ptr: [*]const u8, pattern_len: usize, text_ptr: [*]const u8, text_len: usize) bool {
    const allocator = gpa.allocator();
    const pattern = pattern_ptr[0..pattern_len];
    const text = text_ptr[0..text_len];
    
    var regex = regex_mod.Regex.compile(allocator, pattern) catch return false;
    defer regex.deinit();
    
    const result = regex.find(text) catch return false;
    return result != null;
}

export fn findPattern(pattern_ptr: [*]const u8, pattern_len: usize, text_ptr: [*]const u8, text_len: usize, out_start: *usize, out_end: *usize) bool {
    const allocator = gpa.allocator();
    const pattern = pattern_ptr[0..pattern_len];
    const text = text_ptr[0..text_len];
    
    var regex = regex_mod.Regex.compile(allocator, pattern) catch return false;
    defer regex.deinit();
    
    if (regex.find(text) catch null) |m| {
        out_start.* = m.start;
        out_end.* = m.end;
        return true;
    }
    return false;
}
