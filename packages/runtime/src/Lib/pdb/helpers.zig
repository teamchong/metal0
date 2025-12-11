//! Helper functions for the Python debugger
//!
//! Provides utilities for parsing commands, printing output, etc.

const std = @import("std");
const types = @import("types.zig");
const Frame = types.Frame;

/// Parse breakpoint argument
pub fn parseBreakArg(arg: []const u8) struct { filename: []const u8, lineno: usize, condition: ?[]const u8 } {
    // Simple parsing: filename:lineno or just lineno
    if (std.mem.indexOf(u8, arg, ":")) |colon| {
        const filename = arg[0..colon];
        const rest = arg[colon + 1 ..];
        const lineno = std.fmt.parseInt(usize, rest, 10) catch 1;
        return .{ .filename = filename, .lineno = lineno, .condition = null };
    } else {
        const lineno = std.fmt.parseInt(usize, arg, 10) catch 1;
        return .{ .filename = "<stdin>", .lineno = lineno, .condition = null };
    }
}

/// Print stack trace
pub fn printStack(stack: *std.ArrayList(Frame), curindex: usize, writer: anytype) !void {
    for (stack.items, 0..) |frame, i| {
        const marker = if (i == curindex) ">" else " ";
        try writer.print("{s} {s}({d}){s}()\n", .{ marker, frame.filename, frame.lineno, frame.function });
    }
}

/// Print current frame info
pub fn printFrameInfo(curframe: ?*Frame, writer: anytype) !void {
    if (curframe) |frame| {
        try writer.print("> {s}({d}){s}()\n", .{ frame.filename, frame.lineno, frame.function });
    }
}

/// Print a message
pub fn message(writer: anytype, msg: []const u8) !void {
    try writer.print("{s}\n", .{msg});
}

/// Print an error message
pub fn error_msg(writer: anytype, msg: []const u8) !void {
    try writer.print("*** {s}\n", .{msg});
}
