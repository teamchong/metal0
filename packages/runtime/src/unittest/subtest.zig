/// PyAOT unittest subtest support
const std = @import("std");

/// SubTest context manager - prints label for grouped assertions
pub fn subTest(label: []const u8) void {
    std.debug.print("  subTest: {s}\n", .{label});
}

/// SubTest with integer key-value - common pattern: with self.subTest(i=0)
pub fn subTestInt(key: []const u8, value: i64) void {
    std.debug.print("  subTest: {s}={d}\n", .{ key, value });
}
