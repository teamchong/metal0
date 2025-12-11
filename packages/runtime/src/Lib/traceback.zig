//! CPython source: Lib/traceback.py
//!
//! Provides functions to extract, format, and print stack traces.
//!
//! Mirrors: CPython Lib/traceback.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Traceback Types
// ============================================================================

/// Represents a frame summary
pub const FrameSummary = struct {
    filename: []const u8,
    lineno: ?u32,
    name: []const u8,
    line: ?[]const u8,
    locals: ?hashmap_helper.StringHashMap([]const u8),

    pub fn init(
        filename: []const u8,
        lineno: ?u32,
        name: []const u8,
        line: ?[]const u8,
    ) FrameSummary {
        return .{
            .filename = filename,
            .lineno = lineno,
            .name = name,
            .line = line,
            .locals = null,
        };
    }

    pub fn format(self: *const FrameSummary, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();

        // File "filename", line X, in name
        try result.appendSlice("  File \"");
        try result.appendSlice(self.filename);
        try result.appendSlice("\"");

        if (self.lineno) |line| {
            var buf: [32]u8 = undefined;
            const num_str = std.fmt.bufPrint(&buf, ", line {d}", .{line}) catch "";
            try result.appendSlice(num_str);
        }

        try result.appendSlice(", in ");
        try result.appendSlice(self.name);
        try result.append('\n');

        if (self.line) |code_line| {
            try result.appendSlice("    ");
            // Strip leading whitespace
            var trimmed = code_line;
            while (trimmed.len > 0 and (trimmed[0] == ' ' or trimmed[0] == '\t')) {
                trimmed = trimmed[1..];
            }
            try result.appendSlice(trimmed);
            if (trimmed.len == 0 or trimmed[trimmed.len - 1] != '\n') {
                try result.append('\n');
            }
        }

        return result.toOwnedSlice();
    }
};

/// Stack summary (list of frame summaries)
pub const StackSummary = struct {
    const Self = @This();

    frames: std.ArrayList(FrameSummary),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .frames = std.ArrayList(FrameSummary).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.frames.deinit();
    }

    pub fn append(self: *Self, frame: FrameSummary) !void {
        try self.frames.append(frame);
    }

    pub fn format(self: *const Self) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        for (self.frames.items) |frame| {
            const frame_str = try frame.format(self.allocator);
            defer self.allocator.free(frame_str);
            try result.appendSlice(frame_str);
        }

        return result.toOwnedSlice();
    }

    /// Extract from a frame
    pub fn extract(allocator: std.mem.Allocator, frame: anytype, limit: ?i32) !Self {
        _ = frame;
        _ = limit;
        return Self.init(allocator);
    }

    /// Extract from a traceback
    pub fn extractTb(allocator: std.mem.Allocator, tb: anytype, limit: ?i32) !Self {
        _ = tb;
        _ = limit;
        return Self.init(allocator);
    }
};

/// Traceback exception
pub const TracebackException = struct {
    const Self = @This();

    exc_type: []const u8,
    exc_value: []const u8,
    exc_traceback: ?StackSummary,
    cause: ?*Self,
    context: ?*Self,
    suppress_context: bool,
    notes: ?[][]const u8,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        exc_type: []const u8,
        exc_value: []const u8,
        tb: ?StackSummary,
    ) Self {
        return .{
            .exc_type = exc_type,
            .exc_value = exc_value,
            .exc_traceback = tb,
            .cause = null,
            .context = null,
            .suppress_context = false,
            .notes = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.exc_traceback) |*tb| {
            tb.deinit();
        }
    }

    /// Format the exception only (no traceback)
    pub fn formatExceptionOnly(self: *const Self) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        try result.appendSlice(self.exc_type);
        if (self.exc_value.len > 0) {
            try result.appendSlice(": ");
            try result.appendSlice(self.exc_value);
        }
        try result.append('\n');

        return result.toOwnedSlice();
    }

    /// Format the full exception with traceback
    pub fn format(self: *const Self) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        // Context chain
        if (self.context != null and !self.suppress_context) {
            const ctx_str = try self.context.?.format();
            defer self.allocator.free(ctx_str);
            try result.appendSlice(ctx_str);
            try result.appendSlice("\nDuring handling of the above exception, another exception occurred:\n\n");
        }

        // Cause chain
        if (self.cause) |cause| {
            const cause_str = try cause.format();
            defer self.allocator.free(cause_str);
            try result.appendSlice(cause_str);
            try result.appendSlice("\nThe above exception was the direct cause of the following exception:\n\n");
        }

        // Traceback header
        try result.appendSlice("Traceback (most recent call last):\n");

        // Stack frames
        if (self.exc_traceback) |tb| {
            const tb_str = try tb.format();
            defer self.allocator.free(tb_str);
            try result.appendSlice(tb_str);
        }

        // Exception line
        const exc_str = try self.formatExceptionOnly();
        defer self.allocator.free(exc_str);
        try result.appendSlice(exc_str);

        // Notes
        if (self.notes) |notes| {
            for (notes) |note| {
                try result.appendSlice(note);
                try result.append('\n');
            }
        }

        return result.toOwnedSlice();
    }
};

// ============================================================================
// Module Functions
// ============================================================================

/// Print exception information
pub fn print_exception(allocator: std.mem.Allocator, exc_type: []const u8, exc_value: []const u8, tb: ?StackSummary, limit: ?i32, file: ?std.fs.File, chain: bool) !void {
    _ = limit;
    _ = chain;

    const writer = if (file) |f| f.writer() else std.io.getStdErr().writer();

    const te = TracebackException.init(allocator, exc_type, exc_value, tb);
    const formatted = try te.format();
    defer allocator.free(formatted);

    try writer.writeAll(formatted);
}

/// Format exception information as a list of strings
pub fn format_exception(allocator: std.mem.Allocator, exc_type: []const u8, exc_value: []const u8, tb: ?StackSummary, limit: ?i32, chain: bool) ![][]u8 {
    _ = limit;
    _ = chain;

    var lines = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (lines.items) |line| {
            allocator.free(line);
        }
        lines.deinit();
    }

    const te = TracebackException.init(allocator, exc_type, exc_value, tb);
    const formatted = try te.format();

    // Split into lines
    var iter = std.mem.splitScalar(u8, formatted, '\n');
    while (iter.next()) |line| {
        if (line.len > 0 or iter.peek() != null) {
            var owned_line = try allocator.alloc(u8, line.len + 1);
            @memcpy(owned_line[0..line.len], line);
            owned_line[line.len] = '\n';
            try lines.append(owned_line);
        }
    }
    allocator.free(formatted);

    return lines.toOwnedSlice();
}

/// Format exception only (without traceback)
pub fn format_exception_only(allocator: std.mem.Allocator, exc_type: []const u8, exc_value: []const u8) ![][]u8 {
    var lines = std.ArrayList([]u8).init(allocator);
    errdefer lines.deinit();

    var line = std.ArrayList(u8).init(allocator);
    errdefer line.deinit();

    try line.appendSlice(exc_type);
    if (exc_value.len > 0) {
        try line.appendSlice(": ");
        try line.appendSlice(exc_value);
    }
    try line.append('\n');

    try lines.append(try line.toOwnedSlice());
    return lines.toOwnedSlice();
}

/// Print traceback
pub fn print_tb(allocator: std.mem.Allocator, tb: StackSummary, limit: ?i32, file: ?std.fs.File) !void {
    _ = limit;

    const writer = if (file) |f| f.writer() else std.io.getStdErr().writer();
    const formatted = try tb.format();
    defer allocator.free(formatted);
    try writer.writeAll(formatted);
}

/// Format traceback as list of strings
pub fn format_tb(allocator: std.mem.Allocator, tb: StackSummary, limit: ?i32) ![][]u8 {
    _ = limit;

    var lines = std.ArrayList([]u8).init(allocator);
    errdefer lines.deinit();

    for (tb.frames.items) |frame| {
        const frame_str = try frame.format(allocator);
        try lines.append(frame_str);
    }

    return lines.toOwnedSlice();
}

/// Extract traceback as list of tuples (filename, lineno, name, line)
pub fn extract_tb(allocator: std.mem.Allocator, tb: anytype, limit: ?i32) !StackSummary {
    return StackSummary.extractTb(allocator, tb, limit);
}

/// Print stack
pub fn print_stack(allocator: std.mem.Allocator, frame: anytype, limit: ?i32, file: ?std.fs.File) !void {
    const stack = try StackSummary.extract(allocator, frame, limit);
    const writer = if (file) |f| f.writer() else std.io.getStdErr().writer();
    const formatted = try stack.format();
    defer allocator.free(formatted);
    try writer.writeAll(formatted);
}

/// Format stack as list of strings
pub fn format_stack(allocator: std.mem.Allocator, frame: anytype, limit: ?i32) ![][]u8 {
    var stack = try StackSummary.extract(allocator, frame, limit);
    defer stack.deinit();

    var lines = std.ArrayList([]u8).init(allocator);
    errdefer lines.deinit();

    for (stack.frames.items) |f| {
        const frame_str = try f.format(allocator);
        try lines.append(frame_str);
    }

    return lines.toOwnedSlice();
}

/// Extract stack as list of tuples
pub fn extract_stack(allocator: std.mem.Allocator, frame: anytype, limit: ?i32) !StackSummary {
    return StackSummary.extract(allocator, frame, limit);
}

/// Clear internal caches
pub fn clear_frames(tb: anytype) void {
    _ = tb;
    // Clear frame locals
}

/// Format a list of lines with proper handling
pub fn format_list(allocator: std.mem.Allocator, extracted_list: []const FrameSummary) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    for (extracted_list) |frame| {
        const frame_str = try frame.format(allocator);
        defer allocator.free(frame_str);
        try result.appendSlice(frame_str);
    }

    return result.toOwnedSlice();
}

/// Print a list of tuples as formatted traceback
pub fn print_list(allocator: std.mem.Allocator, extracted_list: []const FrameSummary, file: ?std.fs.File) !void {
    const writer = if (file) |f| f.writer() else std.io.getStdErr().writer();
    const formatted = try format_list(allocator, extracted_list);
    defer allocator.free(formatted);
    try writer.writeAll(formatted);
}

// ============================================================================
// Limit Handling
// ============================================================================

/// Default traceback limit (matches CPython's default)
var tracebacklimit: ?i32 = 1000;

/// Get the traceback limit from sys.tracebacklimit
pub fn getLimit() ?i32 {
    // Check environment variable override (PYTHONTRACEBACK)
    if (std.posix.getenv("PYTHONTRACEBACK")) |env_limit| {
        if (std.fmt.parseInt(i32, env_limit, 10)) |limit| {
            return limit;
        } else |_| {}
    }
    return tracebacklimit;
}

/// Set the traceback limit (called by sys module)
pub fn setLimit(limit: ?i32) void {
    tracebacklimit = limit;
}

/// Apply limit to frame count
pub fn applyLimit(count: usize, limit: ?i32) usize {
    if (limit) |lim| {
        if (lim < 0) return 0;
        return @min(count, @as(usize, @intCast(lim)));
    }
    return count;
}

// ============================================================================
// Walk Functions
// ============================================================================

/// Walk a traceback
pub fn walk_tb(tb: anytype) WalkIterator {
    return WalkIterator.initTb(tb);
}

/// Walk a stack
pub fn walk_stack(frame: anytype) WalkIterator {
    return WalkIterator.initStack(frame);
}

pub const WalkIterator = struct {
    const Self = @This();

    current: ?*anyopaque,
    is_tb: bool,

    pub fn initTb(tb: anytype) Self {
        _ = tb;
        return .{ .current = null, .is_tb = true };
    }

    pub fn initStack(frame: anytype) Self {
        _ = frame;
        return .{ .current = null, .is_tb = false };
    }

    pub fn next(self: *Self) ?struct { frame: *anyopaque, lineno: u32 } {
        _ = self;
        return null;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "FrameSummary format" {
    const allocator = std.testing.allocator;
    const frame = FrameSummary.init("test.py", 42, "test_func", "    x = 1");
    const formatted = try frame.format(allocator);
    defer allocator.free(formatted);

    try std.testing.expect(std.mem.indexOf(u8, formatted, "test.py") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "42") != null);
    try std.testing.expect(std.mem.indexOf(u8, formatted, "test_func") != null);
}

test "StackSummary" {
    const allocator = std.testing.allocator;
    var stack = StackSummary.init(allocator);
    defer stack.deinit();

    try stack.append(FrameSummary.init("main.py", 10, "main", "main()"));
    try stack.append(FrameSummary.init("test.py", 20, "test", "test()"));

    try std.testing.expectEqual(@as(usize, 2), stack.frames.items.len);
}

test "TracebackException format" {
    const allocator = std.testing.allocator;
    var te = TracebackException.init(allocator, "ValueError", "invalid value", null);
    defer te.deinit();

    const exc_only = try te.formatExceptionOnly();
    defer allocator.free(exc_only);

    try std.testing.expect(std.mem.indexOf(u8, exc_only, "ValueError") != null);
    try std.testing.expect(std.mem.indexOf(u8, exc_only, "invalid value") != null);
}

test "format_exception_only" {
    const allocator = std.testing.allocator;
    const lines = try format_exception_only(allocator, "TypeError", "expected int");
    defer {
        for (lines) |line| {
            allocator.free(line);
        }
        allocator.free(lines);
    }

    try std.testing.expectEqual(@as(usize, 1), lines.len);
    try std.testing.expect(std.mem.indexOf(u8, lines[0], "TypeError") != null);
}
