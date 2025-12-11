/// traceback/types - Traceback Type Definitions
/// Mirrors cpython/Python/traceback.c
///
/// This module provides:
/// - PyTracebackObject: Main traceback object with chain support
/// - TracebackEntry: Simplified entry for storage/display
/// - Constants: MAX_STRING_LENGTH, MAX_FRAME_DEPTH, etc.

const std = @import("std");
const frame_mod = @import("../frame.zig");

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

/// Maximum stack entries for capture
pub const MAX_STACK_ENTRIES = 128;

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
