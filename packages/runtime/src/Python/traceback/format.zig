/// traceback/format - Traceback Formatting
/// Mirrors cpython/Python/traceback.c
///
/// This module provides:
/// - Format traceback as string
/// - Format stack entries as string
/// - Format exception with traceback

const std = @import("std");
const types = @import("types.zig");
const stack = @import("stack.zig");

/// Format traceback as string
pub fn formatTraceback(allocator: std.mem.Allocator, tb: *const types.PyTracebackObject) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.appendSlice(types.EXCEPTION_TB_HEADER);
    try result.append('\n');

    // Collect entries
    var entries: [types.MAX_FRAME_DEPTH]*const types.PyTracebackObject = undefined;
    var count: usize = 0;
    var current: ?*const types.PyTracebackObject = tb;
    while (current) |t| {
        if (count < types.MAX_FRAME_DEPTH) {
            entries[count] = t;
            count += 1;
        }
        current = t.tb_next;
    }

    // Format in reverse order
    var i = count;
    while (i > 0) {
        i -= 1;
        const t = entries[i];
        const lineno = t.getLineno();
        const line = try std.fmt.allocPrint(
            allocator,
            "  File \"<unknown>\", line {d}, in <module>\n",
            .{lineno},
        );
        defer allocator.free(line);
        try result.appendSlice(line);
    }

    return result.toOwnedSlice();
}

/// Format traceback stack entries as string
pub fn formatStack(allocator: std.mem.Allocator) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.appendSlice(types.EXCEPTION_TB_HEADER);
    try result.append('\n');

    const stack_entries = stack.getStack();
    // Print oldest first (reverse order)
    var i = stack_entries.len;
    while (i > 0) {
        i -= 1;
        const entry = stack_entries[i];
        const line = try entry.format(allocator);
        defer allocator.free(line);
        try result.appendSlice(line);
        try result.append('\n');
    }

    return result.toOwnedSlice();
}

/// Format exception with traceback
pub fn formatException(
    allocator: std.mem.Allocator,
    exc_type: []const u8,
    exc_value: []const u8,
    tb: ?*const types.PyTracebackObject,
) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    // Format traceback if present
    if (tb) |t| {
        const tb_str = try formatTraceback(allocator, t);
        defer allocator.free(tb_str);
        try result.appendSlice(tb_str);
    }

    // Format exception
    if (exc_value.len > 0) {
        const exc_line = try std.fmt.allocPrint(
            allocator,
            "{s}: {s}\n",
            .{ exc_type, exc_value },
        );
        defer allocator.free(exc_line);
        try result.appendSlice(exc_line);
    } else {
        const exc_line = try std.fmt.allocPrint(
            allocator,
            "{s}\n",
            .{exc_type},
        );
        defer allocator.free(exc_line);
        try result.appendSlice(exc_line);
    }

    return result.toOwnedSlice();
}

/// Print exception to stderr
pub fn printException(exc_type: []const u8, exc_value: []const u8, tb: ?*const types.PyTracebackObject) void {
    const stderr = std.io.getStdErr().writer();

    if (tb) |t| {
        const print_mod = @import("print.zig");
        print_mod.printToStderr(t);
    }

    if (exc_value.len > 0) {
        stderr.print("{s}: {s}\n", .{ exc_type, exc_value }) catch {};
    } else {
        stderr.print("{s}\n", .{exc_type}) catch {};
    }
}
