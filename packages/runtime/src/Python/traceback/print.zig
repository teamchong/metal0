/// traceback/print - Traceback Printing
/// Mirrors cpython/Python/traceback.c
///
/// This module provides:
/// - Print traceback to writer (stdout/stderr)
/// - Print with depth limits
/// - Print single traceback entries

const std = @import("std");
const types = @import("types.zig");
const frame_mod = @import("../frame.zig");

/// Print traceback to writer
pub fn print(tb: *const types.PyTracebackObject, writer: anytype) !void {
    try printWithLimit(tb, writer, types.DEFAULT_LIMIT);
}

/// Print traceback with limit
pub fn printWithLimit(tb: *const types.PyTracebackObject, writer: anytype, limit: i64) !void {
    try writer.writeAll(types.EXCEPTION_TB_HEADER);
    try writer.writeAll("\n");

    // Count entries to respect limit
    const total = tb.length();
    var skip: usize = 0;
    if (limit > 0 and total > @as(usize, @intCast(limit))) {
        skip = total - @as(usize, @intCast(limit));
    }

    // Walk the chain (oldest to newest)
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

    // Print in reverse order (oldest first)
    var printed: usize = 0;
    var skipped: usize = 0;
    var i = count;
    while (i > 0) {
        i -= 1;
        if (skipped < skip) {
            skipped += 1;
            continue;
        }

        const t = entries[i];
        try printEntry(t, writer);
        printed += 1;
    }

    if (skip > 0) {
        try writer.print("  ... {d} more entries\n", .{skip});
    }
}

/// Print a single traceback entry
fn printEntry(tb: *const types.PyTracebackObject, writer: anytype) !void {
    const lineno = tb.getLineno();

    // Get filename and name from frame's code object
    var filename: []const u8 = "<unknown>";
    var name: []const u8 = "<module>";

    if (tb.tb_frame) |frame| {
        if (frame.f_frame) |iframe| {
            if (iframe.f_executable) |code_ptr| {
                // Cast to CodeObject and extract filename/name
                const builtins = @import("../../runtime/builtins.zig");
                const code: *const builtins.CodeObject = @ptrCast(@alignCast(code_ptr));
                if (code.co_filename.len > 0) {
                    filename = code.co_filename;
                }
                if (code.co_name.len > 0) {
                    name = code.co_name;
                }
            }
        }
    }

    try writer.print("  File \"{s}\", line {d}, in {s}\n", .{ filename, lineno, name });
}

/// Print traceback to stderr
pub fn printToStderr(tb: *const types.PyTracebackObject) void {
    const stderr = std.io.getStdErr().writer();
    print(tb, stderr) catch {};
}
