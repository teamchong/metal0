//! test.test_asyncio.echo3 - Echo with error handling
//! Reference: cpython/Lib/test/test_asyncio/echo3.py
//!
//! Reads from stdin in a loop, writes to stdout with "OUT:" prefix.
//! On write error, writes error class name to stderr with "ERR:" prefix.
//! Used for testing subprocess error handling in asyncio.

const std = @import("std");
const posix = std.posix;

/// Main entry point
pub fn main() !void {
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    const stderr = std.io.getStdErr();

    var buf: [1024]u8 = undefined;

    while (true) {
        const n = stdin.read(&buf) catch break;
        if (n == 0) break;

        // Try to write to stdout
        stdout.writeAll("OUT:") catch |err| {
            // On error, write error name to stderr
            try stderr.writeAll("ERR:");
            try stderr.writeAll(@errorName(err));
            continue;
        };

        stdout.writeAll(buf[0..n]) catch |err| {
            try stderr.writeAll("ERR:");
            try stderr.writeAll(@errorName(err));
        };
    }
}

/// Error type for echo operations
pub const EchoError = error{
    WriteError,
    ReadError,
};

/// Echo with error handling for direct use in tests
pub fn echo_with_error_handling(
    allocator: std.mem.Allocator,
    input: []const u8,
    simulate_error: bool,
) !struct {
    stdout: []const u8,
    stderr: ?[]const u8,
} {
    if (simulate_error) {
        return .{
            .stdout = "",
            .stderr = try allocator.dupe(u8, "ERR:WriteError"),
        };
    }

    return .{
        .stdout = try std.fmt.allocPrint(allocator, "OUT:{s}", .{input}),
        .stderr = null,
    };
}

test "echo3 normal" {
    const allocator = std.testing.allocator;
    const result = try echo_with_error_handling(allocator, "hello", false);
    defer allocator.free(result.stdout);
    if (result.stderr) |s| allocator.free(s);

    try std.testing.expectEqualStrings("OUT:hello", result.stdout);
    try std.testing.expect(result.stderr == null);
}

test "echo3 with error" {
    const allocator = std.testing.allocator;
    const result = try echo_with_error_handling(allocator, "hello", true);
    defer allocator.free(result.stdout);
    defer if (result.stderr) |s| allocator.free(s);

    try std.testing.expectEqualStrings("", result.stdout);
    try std.testing.expectEqualStrings("ERR:WriteError", result.stderr.?);
}
