const std = @import("std");
const py_format = @import("py_format.zig");

test "banker's rounding with percent format" {
    const alloc = std.testing.allocator;
    
    // Test "%.0f" % 2.5 -> "2"
    const result1 = try py_format.pyStringFormat(alloc, "%.0f", @as(f64, 2.5));
    defer alloc.free(result1);
    try std.testing.expectEqualStrings("2", result1);
    
    // Test "%.0f" % 1.5 -> "2"
    const result2 = try py_format.pyStringFormat(alloc, "%.0f", @as(f64, 1.5));
    defer alloc.free(result2);
    try std.testing.expectEqualStrings("2", result2);
    
    // Test "%.0f" % 3.5 -> "4"
    const result3 = try py_format.pyStringFormat(alloc, "%.0f", @as(f64, 3.5));
    defer alloc.free(result3);
    try std.testing.expectEqualStrings("4", result3);
}

test "format builtin with banker's rounding" {
    const alloc = std.testing.allocator;
    
    // Test format(2.5, ".0f") -> "2"
    const result1 = try py_format.pyFormat(alloc, @as(f64, 2.5), ".0f");
    defer alloc.free(result1);
    try std.testing.expectEqualStrings("2", result1);
    
    // Test format(1.5, ".0f") -> "2"
    const result2 = try py_format.pyFormat(alloc, @as(f64, 1.5), ".0f");
    defer alloc.free(result2);
    try std.testing.expectEqualStrings("2", result2);
    
    // Test format(3.5, ".0f") -> "4"
    const result3 = try py_format.pyFormat(alloc, @as(f64, 3.5), ".0f");
    defer alloc.free(result3);
    try std.testing.expectEqualStrings("4", result3);
}
