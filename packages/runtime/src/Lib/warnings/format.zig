//! Warning formatting and display functions
//!
//! Functions for formatting and displaying warning messages.

const std = @import("std");
const types = @import("types.zig");

/// Print a warning to stderr
pub fn printWarning(
    message: []const u8,
    category: types.WarningCategory,
    filename: []const u8,
    lineno: usize,
) !void {
    const stderr = std.io.getStdErr().writer();
    if (lineno > 0) {
        try stderr.print("{s}:{d}: {s}: {s}\n", .{ filename, lineno, category.name(), message });
    } else {
        try stderr.print("{s}: {s}\n", .{ category.name(), message });
    }
}

/// Format a warning message (like formatwarning in Python)
pub fn formatWarning(
    allocator: std.mem.Allocator,
    message: []const u8,
    category: types.WarningCategory,
    filename: []const u8,
    lineno: usize,
    line: ?[]const u8,
) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    const writer = result.writer(allocator);

    try writer.print("{s}:{d}: {s}: {s}\n", .{ filename, lineno, category.name(), message });

    if (line) |l| {
        try writer.print("  {s}\n", .{l});
    }

    return result.toOwnedSlice(allocator);
}

/// Default show warning function (customizable hook)
pub fn showWarning(
    message: []const u8,
    category: types.WarningCategory,
    filename: []const u8,
    lineno: usize,
    _: ?std.fs.File,
    _: ?[]const u8,
) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print("{s}:{d}: {s}: {s}\n", .{ filename, lineno, category.name(), message }) catch {};
}
