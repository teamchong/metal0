//! asyncio.__main__ - Entry point for python -m asyncio
//! Reference: cpython/Lib/asyncio/__main__.py

const std = @import("std");
const runners = @import("runners.zig");
const events = @import("events.zig");

/// Interactive asyncio REPL mode
/// CPython: class REPLThread(Thread)
pub const REPLThread = struct {
    allocator: std.mem.Allocator,
    running: bool,

    pub fn init(allocator: std.mem.Allocator) REPLThread {
        return .{
            .allocator = allocator,
            .running = false,
        };
    }

    pub fn start(self: *REPLThread) void {
        self.running = true;
    }

    pub fn stop(self: *REPLThread) void {
        self.running = false;
    }
};

/// Main entry point for asyncio module
/// CPython: if __name__ == '__main__':
pub fn main(allocator: std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("asyncio REPL\n", .{});
    try stdout.print("Use 'await' directly instead of 'asyncio.run()'\n", .{});
    try stdout.print("Type 'exit()' to exit\n", .{});

    // Create event loop
    var runner = runners.Runner.init(allocator);
    defer runner.close();

    _ = try runner.enter();

    // Simple REPL loop would go here
    // In practice, we'd need Python interpreter integration
}

/// Print asyncio version info
pub fn printVersion(writer: anytype) !void {
    try writer.print("asyncio module for metal0\n", .{});
    try writer.print("Based on CPython asyncio\n", .{});
}

/// Check if running as main module
pub fn isMain() bool {
    return false; // In Zig, check would be different
}

// Tests
test "REPLThread creation" {
    const allocator = std.testing.allocator;

    var repl = REPLThread.init(allocator);
    try std.testing.expect(!repl.running);

    repl.start();
    try std.testing.expect(repl.running);

    repl.stop();
    try std.testing.expect(!repl.running);
}
