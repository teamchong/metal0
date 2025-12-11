/// io - I/O Built-in Functions
/// print(), input() implementations.

const std = @import("std");

// ============================================================================
// I/O Functions
// ============================================================================

/// Print to stdout
/// Mirrors: builtin print()
pub fn print_builtin(args: anytype, options: struct {
    sep: []const u8 = " ",
    end: []const u8 = "\n",
    flush: bool = false,
}) !void {
    const stdout = std.io.getStdOut().writer();

    inline for (args, 0..) |arg, i| {
        if (i > 0) try stdout.writeAll(options.sep);
        try stdout.print("{any}", .{arg});
    }

    try stdout.writeAll(options.end);

    if (options.flush) {
        // Flush is automatic in Zig
    }
}

/// Read line from stdin
/// Mirrors: builtin input()
pub fn input_builtin(allocator: std.mem.Allocator, prompt: ?[]const u8) ![]const u8 {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn();

    if (prompt) |p| {
        try stdout.writeAll(p);
    }

    return stdin.reader().readUntilDelimiterOrEofAlloc(allocator, '\n', 4096) orelse {
        return error.EOFError;
    };
}
