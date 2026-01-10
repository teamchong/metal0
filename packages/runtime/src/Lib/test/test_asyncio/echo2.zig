//! test.test_asyncio.echo2 - Echo with OUT:/ERR: prefixes
//! Reference: cpython/Lib/test/test_asyncio/echo2.py
//!
//! Reads from stdin, writes to stdout with "OUT:" prefix and
//! to stderr with "ERR:" prefix. Used for testing subprocess
//! stdout/stderr handling in asyncio.

const std = @import("std");
const posix = std.posix;

/// Main entry point
pub fn main() !void {
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    const stderr = std.io.getStdErr();

    var buf: [1024]u8 = undefined;
    const n = stdin.read(&buf) catch return;
    if (n == 0) return;

    // Write to stdout with OUT: prefix
    try stdout.writeAll("OUT:");
    try stdout.writeAll(buf[0..n]);

    // Write to stderr with ERR: prefix
    try stderr.writeAll("ERR:");
    try stderr.writeAll(buf[0..n]);
}

/// Echo with prefixes for direct use in tests
pub fn echo_with_prefix(allocator: std.mem.Allocator, input: []const u8) !struct {
    stdout: []const u8,
    stderr: []const u8,
} {
    const stdout_data = try std.fmt.allocPrint(allocator, "OUT:{s}", .{input});
    const stderr_data = try std.fmt.allocPrint(allocator, "ERR:{s}", .{input});
    return .{
        .stdout = stdout_data,
        .stderr = stderr_data,
    };
}

test "echo2 with prefix" {
    const allocator = std.testing.allocator;
    const result = try echo_with_prefix(allocator, "hello");
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqualStrings("OUT:hello", result.stdout);
    try std.testing.expectEqualStrings("ERR:hello", result.stderr);
}
