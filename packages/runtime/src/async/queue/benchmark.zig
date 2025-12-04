// Benchmark temporarily disabled for Zig 0.15 compatibility
// TODO: Migrate from std.io.getStdOut() to std.posix.write()

const std = @import("std");
const lockfree = @import("lockfree.zig");
const Task = @import("task.zig").Task;

/// Benchmark queue performance (disabled for Zig 0.15)
pub fn main() !void {
    _ = std.posix.write(std.posix.STDOUT_FILENO, "Benchmark temporarily disabled\n") catch {};
}
