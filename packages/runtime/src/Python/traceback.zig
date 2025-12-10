/// traceback - Traceback Object Implementation
/// Mirrors cpython/Python/traceback.c
///
/// This module provides:
/// - PyTracebackObject: Traceback entries for exception handling
/// - Traceback printing and formatting
/// - Stack trace capture from frames
/// - Source line extraction and display

const std = @import("std");
const frame_mod = @import("frame.zig");

// ============================================================================
// Constants
// ============================================================================

/// Maximum string length for truncation
pub const MAX_STRING_LENGTH = 500;

/// Maximum frame depth for traceback
pub const MAX_FRAME_DEPTH = 100;

/// Maximum number of threads to display
pub const MAX_NTHREADS = 100;

/// Default traceback print limit
pub const DEFAULT_LIMIT: i64 = 1000;

/// Header for exception tracebacks
pub const EXCEPTION_TB_HEADER = "Traceback (most recent call last):";

// ============================================================================
// Traceback Object
// ============================================================================

/// Python traceback object
/// Mirrors: PyTracebackObject
pub const PyTracebackObject = struct {
    /// Next traceback entry (older frame)
    tb_next: ?*PyTracebackObject = null,

    /// Associated frame object
    tb_frame: ?*frame_mod.PyFrameObject = null,

    /// Last instruction index
    tb_lasti: i32 = 0,

    /// Line number
    tb_lineno: i32 = 0,

    /// Allocator used for this traceback
    allocator: std.mem.Allocator,

    /// Create a new traceback object
    pub fn create(
        allocator: std.mem.Allocator,
        next: ?*PyTracebackObject,
        frame: ?*frame_mod.PyFrameObject,
        lasti: i32,
        lineno: i32,
    ) !*PyTracebackObject {
        const tb = try allocator.create(PyTracebackObject);
        tb.* = .{
            .tb_next = next,
            .tb_frame = frame,
            .tb_lasti = lasti,
            .tb_lineno = lineno,
            .allocator = allocator,
        };
        return tb;
    }

    /// Create from frame (captures current state)
    pub fn fromFrame(allocator: std.mem.Allocator, frame: *frame_mod.PyFrameObject) !*PyTracebackObject {
        return create(
            allocator,
            null,
            frame,
            frame.getLasti(),
            frame.getLineNo(),
        );
    }

    /// Destroy traceback object (doesn't free linked entries)
    pub fn destroy(self: *PyTracebackObject) void {
        self.allocator.destroy(self);
    }

    /// Destroy entire traceback chain
    pub fn destroyChain(self: *PyTracebackObject) void {
        var current: ?*PyTracebackObject = self;
        while (current) |tb| {
            const next = tb.tb_next;
            tb.destroy();
            current = next;
        }
    }

    /// Get the next traceback entry
    pub fn getNext(self: *const PyTracebackObject) ?*PyTracebackObject {
        return self.tb_next;
    }

    /// Set the next traceback entry
    pub fn setNext(self: *PyTracebackObject, next: ?*PyTracebackObject) !void {
        // Check for cycles
        var check: ?*PyTracebackObject = next;
        while (check) |tb| {
            if (tb == self) {
                return error.ValueError; // Would create cycle
            }
            check = tb.tb_next;
        }
        self.tb_next = next;
    }

    /// Get the frame
    pub fn getFrame(self: *const PyTracebackObject) ?*frame_mod.PyFrameObject {
        return self.tb_frame;
    }

    /// Get the line number
    pub fn getLineno(self: *const PyTracebackObject) i32 {
        if (self.tb_lineno == -1) {
            // Would compute from code object and lasti
            return 0;
        }
        return self.tb_lineno;
    }

    /// Count entries in traceback chain
    pub fn length(self: *const PyTracebackObject) usize {
        var count: usize = 0;
        var current: ?*const PyTracebackObject = self;
        while (current) |tb| {
            count += 1;
            current = tb.tb_next;
        }
        return count;
    }
};

// ============================================================================
// Traceback Entry (Simplified for storage)
// ============================================================================

/// Simplified traceback entry for storage/display
pub const TracebackEntry = struct {
    filename: []const u8,
    lineno: i32,
    name: []const u8, // Function/method name
    line: ?[]const u8 = null, // Source line if available

    /// Format as string
    pub fn format(self: *const TracebackEntry, allocator: std.mem.Allocator) ![]const u8 {
        if (self.line) |line| {
            return std.fmt.allocPrint(
                allocator,
                "  File \"{s}\", line {d}, in {s}\n    {s}",
                .{ self.filename, self.lineno, self.name, line },
            );
        } else {
            return std.fmt.allocPrint(
                allocator,
                "  File \"{s}\", line {d}, in {s}",
                .{ self.filename, self.lineno, self.name },
            );
        }
    }
};

// ============================================================================
// Traceback Stack (Thread-local capture)
// ============================================================================

/// Maximum stack entries for capture
const MAX_STACK_ENTRIES = 128;

/// Thread-local traceback stack
threadlocal var traceback_stack: [MAX_STACK_ENTRIES]TracebackEntry = undefined;
threadlocal var traceback_stack_len: usize = 0;

/// Push a traceback entry
pub fn pushEntry(filename: []const u8, lineno: i32, name: []const u8) void {
    if (traceback_stack_len < MAX_STACK_ENTRIES) {
        traceback_stack[traceback_stack_len] = .{
            .filename = filename,
            .lineno = lineno,
            .name = name,
        };
        traceback_stack_len += 1;
    }
}

/// Pop a traceback entry
pub fn popEntry() void {
    if (traceback_stack_len > 0) {
        traceback_stack_len -= 1;
    }
}

/// Get current traceback stack
pub fn getStack() []const TracebackEntry {
    return traceback_stack[0..traceback_stack_len];
}

/// Clear traceback stack
pub fn clearStack() void {
    traceback_stack_len = 0;
}

// ============================================================================
// Traceback Printing
// ============================================================================

/// Print traceback to writer
pub fn print(tb: *const PyTracebackObject, writer: anytype) !void {
    try printWithLimit(tb, writer, DEFAULT_LIMIT);
}

/// Print traceback with limit
pub fn printWithLimit(tb: *const PyTracebackObject, writer: anytype, limit: i64) !void {
    try writer.writeAll(EXCEPTION_TB_HEADER);
    try writer.writeAll("\n");

    // Count entries to respect limit
    const total = tb.length();
    var skip: usize = 0;
    if (limit > 0 and total > @as(usize, @intCast(limit))) {
        skip = total - @as(usize, @intCast(limit));
    }

    // Walk the chain (oldest to newest)
    var entries: [MAX_FRAME_DEPTH]*const PyTracebackObject = undefined;
    var count: usize = 0;
    var current: ?*const PyTracebackObject = tb;
    while (current) |t| {
        if (count < MAX_FRAME_DEPTH) {
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
fn printEntry(tb: *const PyTracebackObject, writer: anytype) !void {
    const lineno = tb.getLineno();

    // Get filename and name from frame's code object
    var filename: []const u8 = "<unknown>";
    var name: []const u8 = "<module>";

    if (tb.tb_frame) |frame| {
        if (frame.f_frame) |iframe| {
            if (iframe.f_executable) |code_ptr| {
                // Cast to CodeObject and extract filename/name
                const builtins = @import("../runtime/builtins.zig");
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
pub fn printToStderr(tb: *const PyTracebackObject) void {
    const stderr = std.io.getStdErr().writer();
    print(tb, stderr) catch {};
}

// ============================================================================
// Traceback Capture from Frames
// ============================================================================

/// Create traceback from interpreter frame
/// Mirrors: _PyTraceBack_FromFrame
pub fn fromFrame(allocator: std.mem.Allocator, frame: *frame_mod.InterpreterFrame) !*PyTracebackObject {
    // Get or create frame object
    const frame_obj = try frame_mod.getFrameObject(allocator, frame);

    return PyTracebackObject.create(
        allocator,
        null,
        frame_obj,
        frame.getLasti(),
        frame_mod.getFrameLine(frame),
    );
}

/// Capture current call stack as traceback
pub fn captureStack(allocator: std.mem.Allocator) !?*PyTracebackObject {
    var frame = frame_mod.getCurrentFrame();
    if (frame == null) return null;

    var tb: ?*PyTracebackObject = null;
    var depth: usize = 0;

    while (frame) |f| : (depth += 1) {
        if (depth >= MAX_FRAME_DEPTH) break;

        const frame_obj = try frame_mod.getFrameObject(allocator, f);
        const entry = try PyTracebackObject.create(
            allocator,
            tb,
            frame_obj,
            f.getLasti(),
            frame_mod.getFrameLine(f),
        );
        tb = entry;

        frame = f.previous;
    }

    return tb;
}

// ============================================================================
// Traceback Formatting
// ============================================================================

/// Format traceback as string
pub fn formatTraceback(allocator: std.mem.Allocator, tb: *const PyTracebackObject) ![]const u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.appendSlice(EXCEPTION_TB_HEADER);
    try result.append('\n');

    // Collect entries
    var entries: [MAX_FRAME_DEPTH]*const PyTracebackObject = undefined;
    var count: usize = 0;
    var current: ?*const PyTracebackObject = tb;
    while (current) |t| {
        if (count < MAX_FRAME_DEPTH) {
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

    try result.appendSlice(EXCEPTION_TB_HEADER);
    try result.append('\n');

    const stack = getStack();
    // Print oldest first (reverse order)
    var i = stack.len;
    while (i > 0) {
        i -= 1;
        const entry = stack[i];
        const line = try entry.format(allocator);
        defer allocator.free(line);
        try result.appendSlice(line);
        try result.append('\n');
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Exception Display
// ============================================================================

/// Format exception with traceback
pub fn formatException(
    allocator: std.mem.Allocator,
    exc_type: []const u8,
    exc_value: []const u8,
    tb: ?*const PyTracebackObject,
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
pub fn printException(exc_type: []const u8, exc_value: []const u8, tb: ?*const PyTracebackObject) void {
    const stderr = std.io.getStdErr().writer();

    if (tb) |t| {
        printToStderr(t);
    }

    if (exc_value.len > 0) {
        stderr.print("{s}: {s}\n", .{ exc_type, exc_value }) catch {};
    } else {
        stderr.print("{s}\n", .{exc_type}) catch {};
    }
}

// ============================================================================
// Source Line Extraction
// ============================================================================

/// Extract source line from file by reading the file and extracting the specific line
/// Returns null if file cannot be read or line number is out of range
/// Uses a thread-local buffer to avoid allocations
pub fn getSourceLine(filename: []const u8, lineno: i32) ?[]const u8 {
    if (lineno <= 0) return null;
    if (!isValidFilename(filename)) return null;

    // Thread-local buffer for source line (avoids allocation per call)
    const Static = struct {
        threadlocal var line_buffer: [4096]u8 = undefined;
        threadlocal var file_buffer: [65536]u8 = undefined;
    };

    // Try to open the file
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        // Also try absolute path if relative failed
        if (err == error.FileNotFound and !std.fs.path.isAbsolute(filename)) {
            return null;
        }
        return null;
    };
    defer file.close();

    // Read file contents into buffer
    const bytes_read = file.readAll(&Static.file_buffer) catch return null;
    const content = Static.file_buffer[0..bytes_read];

    // Find the target line
    var current_line: i32 = 1;
    var line_start: usize = 0;

    for (content, 0..) |c, i| {
        if (c == '\n') {
            if (current_line == lineno) {
                // Found our line
                const line_content = content[line_start..i];
                const len = @min(line_content.len, Static.line_buffer.len - 1);
                @memcpy(Static.line_buffer[0..len], line_content[0..len]);
                return Static.line_buffer[0..len];
            }
            current_line += 1;
            line_start = i + 1;
        }
    }

    // Check last line (file may not end with newline)
    if (current_line == lineno and line_start < content.len) {
        const line_content = content[line_start..];
        const len = @min(line_content.len, Static.line_buffer.len - 1);
        @memcpy(Static.line_buffer[0..len], line_content[0..len]);
        return Static.line_buffer[0..len];
    }

    return null;
}

/// Check if filename is valid for display
pub fn isValidFilename(filename: []const u8) bool {
    return filename.len > 0 and
        filename[0] != '<' and // Skip <stdin>, <string>, etc.
        !std.mem.eql(u8, filename, "?");
}

// ============================================================================
// Repeated Line Handling
// ============================================================================

/// State for tracking repeated lines
const RepeatState = struct {
    last_filename: []const u8 = "",
    last_lineno: i32 = 0,
    last_name: []const u8 = "",
    repeat_count: usize = 0,
};

/// Thread-local repeat state
threadlocal var repeat_state: RepeatState = .{};

/// Check if current entry is same as last
pub fn checkRepeat(filename: []const u8, lineno: i32, name: []const u8) bool {
    if (std.mem.eql(u8, filename, repeat_state.last_filename) and
        lineno == repeat_state.last_lineno and
        std.mem.eql(u8, name, repeat_state.last_name))
    {
        repeat_state.repeat_count += 1;
        return true;
    }

    repeat_state.last_filename = filename;
    repeat_state.last_lineno = lineno;
    repeat_state.last_name = name;
    repeat_state.repeat_count = 0;
    return false;
}

/// Get repeat count and reset
pub fn getAndResetRepeatCount() usize {
    const count = repeat_state.repeat_count;
    repeat_state.repeat_count = 0;
    return count;
}

// ============================================================================
// Initialization
// ============================================================================

/// Initialize traceback subsystem
pub fn init() void {
    clearStack();
    repeat_state = .{};
}

/// Finalize traceback subsystem
pub fn fini() void {
    clearStack();
}

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

    const stack = getStack();
    try std.testing.expectEqual(@as(usize, 2), stack.len);
    try std.testing.expectEqual(@as(i32, 10), stack[0].lineno);
    try std.testing.expectEqual(@as(i32, 20), stack[1].lineno);

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
    repeat_state = .{};

    try std.testing.expect(!checkRepeat("test.py", 10, "foo"));
    try std.testing.expect(checkRepeat("test.py", 10, "foo"));
    try std.testing.expect(checkRepeat("test.py", 10, "foo"));
    try std.testing.expectEqual(@as(usize, 2), repeat_state.repeat_count);

    try std.testing.expect(!checkRepeat("test.py", 20, "bar"));
    try std.testing.expectEqual(@as(usize, 0), repeat_state.repeat_count);
}
