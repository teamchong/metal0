/// stdio - Standard IO Streams
/// Handles stdin, stdout, stderr access

const std = @import("std");

// ============================================================================
// Standard IO Streams
// ============================================================================

/// Standard input (as file descriptor for now)
pub const stdin_fd: std.fs.File = std.io.getStdIn();

/// Standard output
pub const stdout_fd: std.fs.File = std.io.getStdOut();

/// Standard error
pub const stderr_fd: std.fs.File = std.io.getStdErr();

// ============================================================================
// IO Operations
// ============================================================================

/// Write to stdout
pub fn stdout_write(data: []const u8) !void {
    try stdout_fd.writeAll(data);
}

/// Write to stderr
pub fn stderr_write(data: []const u8) !void {
    try stderr_fd.writeAll(data);
}

// ============================================================================
// Display and Exception Hooks
// ============================================================================

/// Displayhook for interactive output
pub fn displayhook(value: anytype) void {
    if (@TypeOf(value) == void) return;
    const stdout = std.io.getStdOut().writer();
    stdout.print("{any}\n", .{value}) catch {};
}

/// Excepthook for unhandled exceptions
pub fn excepthook(exc_type: []const u8, exc_value: []const u8, exc_tb: ?[]const u8) void {
    const stderr = std.io.getStdErr().writer();
    if (exc_tb) |tb| {
        stderr.print("Traceback (most recent call last):\n{s}\n", .{tb}) catch {};
    }
    stderr.print("{s}: {s}\n", .{ exc_type, exc_value }) catch {};
}
