// Minimal usage - ONLY compile and find
const std = @import("std");
const Regex = @import("src/zig-regex/regex.zig").Regex;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

export fn matchSimple(pattern_ptr: [*]const u8, pattern_len: usize, text_ptr: [*]const u8, text_len: usize) bool {
    const allocator = gpa.allocator();
    const pattern = pattern_ptr[0..pattern_len];
    const text = text_ptr[0..text_len];
    
    var regex = Regex.compile(allocator, pattern) catch return false;
    defer regex.deinit();
    
    const result = regex.find(text) catch return false;
    return result != null;
}
