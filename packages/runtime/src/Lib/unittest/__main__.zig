//! unittest.__main__ - Entry point for python -m unittest
//! Reference: cpython/Lib/unittest/__main__.py
//!
//! Provides entry point for running unittest as a module:
//!   python -m unittest [options] [tests]
//!
//! This module is executed when unittest is run from command line.

const std = @import("std");
const main_mod = @import("main.zig");
const runner = @import("runner.zig");

// ============================================================================
// Entry Point
// ============================================================================

/// Main entry point for `python -m unittest`
/// CPython: if __name__ == '__main__': main(module=None)
pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Get command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Run with arguments
    try main_mod.mainWithArgs(allocator, args);
}

/// Entry point that takes an allocator (for embedding)
pub fn mainWithAllocator(allocator: std.mem.Allocator) !void {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    try main_mod.mainWithArgs(allocator, args);
}

/// Entry point with explicit arguments (for testing)
pub fn mainWithArgs(allocator: std.mem.Allocator, args: []const []const u8) !void {
    try main_mod.mainWithArgs(allocator, args);
}

// ============================================================================
// Usage Information
// ============================================================================

/// Print usage information
pub fn printUsage() void {
    const writer = std.io.getStdErr().writer();
    writer.print(
        \\usage: metal0 -m unittest [options] [tests]
        \\
        \\positional arguments:
        \\  tests           a list of any number of test modules, classes and test
        \\                  methods.
        \\
        \\options:
        \\  -h, --help      show this help message and exit
        \\  -v, --verbose   Verbose output
        \\  -q, --quiet     Quiet output
        \\  -f, --failfast  Stop on first fail or error
        \\  -c, --catch     Catch Ctrl-C and display results so far
        \\  -b, --buffer    Buffer stdout and stderr during tests
        \\  -k TESTNAMEPATTERNS
        \\                  Only run tests which match the given substring
        \\  --locals        Show local variables in tracebacks
        \\  --durations N   Show N slowest test cases (N=0 for all)
        \\
        \\Examples:
        \\  metal0 -m unittest test_module                 - run tests from test_module
        \\  metal0 -m unittest module.TestClass            - run tests from TestClass
        \\  metal0 -m unittest module.Class.test_method    - run specified test
        \\  metal0 -m unittest discover                    - discover and run tests
        \\
        \\For test discovery all test modules must be importable from the top level
        \\directory of the project.
        \\
    , .{}) catch {};
}

/// Print version information
pub fn printVersion() void {
    const writer = std.io.getStdOut().writer();
    writer.print("unittest - metal0 test framework\n", .{}) catch {};
}

// ============================================================================
// Discover Command
// ============================================================================

/// Run test discovery
/// CPython: python -m unittest discover [options]
pub fn discover(
    allocator: std.mem.Allocator,
    start_dir: []const u8,
    pattern: []const u8,
    top_level_dir: ?[]const u8,
) !void {
    var program = main_mod.TestProgram.init(allocator);
    defer program.deinit();

    program.start_dir = start_dir;
    program.pattern = pattern;
    program.top_level_dir = top_level_dir;

    var suite = program.createTests(true);
    defer suite.deinit();

    var test_runner = runner.TextTestRunner.init(allocator);
    _ = test_runner.run(&suite);
}

// ============================================================================
// Tests
// ============================================================================

test "printUsage" {
    // Just ensure it doesn't crash
    printUsage();
}

test "printVersion" {
    // Just ensure it doesn't crash
    printVersion();
}
