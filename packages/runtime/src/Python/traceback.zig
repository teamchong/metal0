/// traceback - Traceback Object Implementation
/// Mirrors cpython/Python/traceback.c
///
/// This module provides:
/// - PyTracebackObject: Traceback entries for exception handling
/// - Traceback printing and formatting
/// - Stack trace capture from frames
/// - Source line extraction and display
///
/// Modular structure:
/// - traceback/types.zig - PyTracebackObject, TracebackEntry, constants
/// - traceback/stack.zig - Thread-local stack management
/// - traceback/print.zig - Print to writer/stderr
/// - traceback/capture.zig - Capture from frames
/// - traceback/format.zig - Format as string, exception display
/// - traceback/source.zig - Source line extraction
/// - traceback/repeat.zig - Repeated entry tracking
/// - traceback/init.zig - Initialization/finalization

const std = @import("std");

// Re-export submodules
pub const types = @import("traceback/types.zig");
pub const stack = @import("traceback/stack.zig");
pub const print_mod = @import("traceback/print.zig");
pub const capture = @import("traceback/capture.zig");
pub const format_mod = @import("traceback/format.zig");
pub const source = @import("traceback/source.zig");
pub const repeat = @import("traceback/repeat.zig");
pub const init_mod = @import("traceback/init.zig");

// Re-export commonly used types and constants
pub const PyTracebackObject = types.PyTracebackObject;
pub const TracebackEntry = types.TracebackEntry;
pub const MAX_STRING_LENGTH = types.MAX_STRING_LENGTH;
pub const MAX_FRAME_DEPTH = types.MAX_FRAME_DEPTH;
pub const MAX_NTHREADS = types.MAX_NTHREADS;
pub const DEFAULT_LIMIT = types.DEFAULT_LIMIT;
pub const EXCEPTION_TB_HEADER = types.EXCEPTION_TB_HEADER;

// Re-export stack functions
pub const pushEntry = stack.pushEntry;
pub const popEntry = stack.popEntry;
pub const getStack = stack.getStack;
pub const clearStack = stack.clearStack;

// Re-export print functions
pub const print = print_mod.print;
pub const printWithLimit = print_mod.printWithLimit;
pub const printToStderr = print_mod.printToStderr;

// Re-export capture functions
pub const fromFrame = capture.fromFrame;
pub const captureStack = capture.captureStack;

// Re-export format functions
pub const formatTraceback = format_mod.formatTraceback;
pub const formatStack = format_mod.formatStack;
pub const formatException = format_mod.formatException;
pub const printException = format_mod.printException;

// Re-export source functions
pub const getSourceLine = source.getSourceLine;
pub const isValidFilename = source.isValidFilename;

// Re-export repeat functions
pub const checkRepeat = repeat.checkRepeat;
pub const getAndResetRepeatCount = repeat.getAndResetRepeatCount;

// Re-export init/fini functions
pub const init = init_mod.init;
pub const fini = init_mod.fini;

// ============================================================================
// Tests
// ============================================================================

test "traceback object creation" {
    const allocator = std.testing.allocator;

    const tb = try PyTracebackObject.create(allocator, null, null, 10, 5);
    defer tb.destroy();

    try std.testing.expectEqual(@as(i32, 10), tb.tb_lasti);
    try std.testing.expectEqual(@as(i32, 5), tb.getLineno());
    try std.testing.expect(tb.tb_next == null);
}

test "traceback chain" {
    const allocator = std.testing.allocator;

    const tb1 = try PyTracebackObject.create(allocator, null, null, 10, 1);
    const tb2 = try PyTracebackObject.create(allocator, tb1, null, 20, 2);
    const tb3 = try PyTracebackObject.create(allocator, tb2, null, 30, 3);
    defer tb3.destroyChain();

    try std.testing.expectEqual(@as(usize, 3), tb3.length());
    try std.testing.expect(tb3.tb_next == tb2);
    try std.testing.expect(tb2.tb_next == tb1);
}

test "traceback stack" {
    clearStack();

    pushEntry("test.py", 10, "foo");
    pushEntry("test.py", 20, "bar");

    const stack_entries = getStack();
    try std.testing.expectEqual(@as(usize, 2), stack_entries.len);
    try std.testing.expectEqual(@as(i32, 10), stack_entries[0].lineno);
    try std.testing.expectEqual(@as(i32, 20), stack_entries[1].lineno);

    popEntry();
    try std.testing.expectEqual(@as(usize, 1), getStack().len);

    clearStack();
    try std.testing.expectEqual(@as(usize, 0), getStack().len);
}

test "traceback entry format" {
    const allocator = std.testing.allocator;

    const entry = TracebackEntry{
        .filename = "test.py",
        .lineno = 42,
        .name = "my_function",
    };

    const formatted = try entry.format(allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "test.py") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "42") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "my_function") != null);
}

test "repeat detection" {
    repeat.reset();

    try std.testing.expect(!checkRepeat("test.py", 10, "foo"));
    try std.testing.expect(checkRepeat("test.py", 10, "foo"));
    try std.testing.expect(checkRepeat("test.py", 10, "foo"));
    try std.testing.expectEqual(@as(usize, 2), getAndResetRepeatCount());

    try std.testing.expect(!checkRepeat("test.py", 20, "bar"));
    try std.testing.expectEqual(@as(usize, 0), getAndResetRepeatCount());
}
