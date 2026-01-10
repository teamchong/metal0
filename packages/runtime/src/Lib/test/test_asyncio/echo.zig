//! test.test_asyncio.echo - Simple stdin/stdout echo for subprocess tests
//! Reference: cpython/Lib/test/test_asyncio/echo.py
//!
//! Reads from stdin and writes to stdout. Used for testing subprocess
//! communication in asyncio.

const std = @import("std");
const posix = std.posix;

/// Main entry point - echo stdin to stdout
pub fn main() !void {
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    var buf: [1024]u8 = undefined;

    while (true) {
        const n = stdin.read(&buf) catch break;
        if (n == 0) break; // EOF

        stdout.writeAll(buf[0..n]) catch break;
    }
}

/// Echo function for direct use in tests
pub fn echo(input: []const u8) []const u8 {
    return input;
}

/// Read from fd and write to another fd (low-level echo)
pub fn echo_fd(in_fd: posix.fd_t, out_fd: posix.fd_t) !void {
    var buf: [1024]u8 = undefined;

    while (true) {
        const n = try posix.read(in_fd, &buf);
        if (n == 0) break;
        _ = try posix.write(out_fd, buf[0..n]);
    }
}

test "echo function" {
    const input = "hello world";
    const output = echo(input);
    try std.testing.expectEqualStrings(input, output);
}
