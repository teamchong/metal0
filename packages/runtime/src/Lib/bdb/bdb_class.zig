//! Bdb - Base Debugger Class.
//!
//! Provides the main debugger class with:
//! - Breakpoint management (setBreak, clearBreak, getBreaks)
//! - Execution control (setContinue, setStep, setNext, setReturn)
//! - Frame operations (setup, frameUp, frameDown)
//! - Trace functions (dispatchCall, dispatchLine, dispatchReturn, dispatchException)
//! - Stack display (formatStackEntry, printStack)

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");
const breakpoint_mod = @import("breakpoint.zig");

const FrameInfo = types.FrameInfo;
const StopReason = types.StopReason;
const Breakpoint = breakpoint_mod.Breakpoint;

// ============================================================================
// Bdb - Base Debugger Class
// ============================================================================

/// Base debugger class
pub const Bdb = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    // Breakpoint management
    breakpoints: std.ArrayList(Breakpoint),
    bp_by_file: hashmap_helper.StringHashMap(std.ArrayList(usize)),
    next_bp_number: usize,

    // Execution state
    stop_here: bool,
    return_frame: ?*FrameInfo,
    stop_reason: ?StopReason,

    // Step control
    skip: ?hashmap_helper.StringHashMap(void),
    stopframe: ?*FrameInfo,
    returnframe: ?*FrameInfo,
    quitting: bool,

    // Current frame
    curframe: ?*FrameInfo,
    curindex: usize,
    stack: std.ArrayList(*FrameInfo),

    // Callbacks (can be set by subclasses)
    on_stop: ?*const fn (*Self) void,
    on_breakpoint: ?*const fn (*Self, *const Breakpoint) void,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .breakpoints = .{},
            .bp_by_file = hashmap_helper.StringHashMap(std.ArrayList(usize)).init(allocator),
            .next_bp_number = 1,
            .stop_here = false,
            .return_frame = null,
            .stop_reason = null,
            .skip = null,
            .stopframe = null,
            .returnframe = null,
            .quitting = false,
            .curframe = null,
            .curindex = 0,
            .stack = .{},
            .on_stop = null,
            .on_breakpoint = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.breakpoints.deinit(self.allocator);

        var it = self.bp_by_file.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.bp_by_file.deinit();

        self.stack.deinit(self.allocator);
    }

    /// Reset the debugger state
    pub fn reset(self: *Self) void {
        self.stop_here = false;
        self.return_frame = null;
        self.stop_reason = null;
        self.stopframe = null;
        self.returnframe = null;
        self.quitting = false;
    }

    // ========================================================================
    // Breakpoint Management
    // ========================================================================

    /// Set a breakpoint
    pub fn setBreak(
        self: *Self,
        filename: []const u8,
        lineno: usize,
        temporary: bool,
        cond: ?[]const u8,
        funcname: ?[]const u8,
    ) !*Breakpoint {
        const bp = Breakpoint.init(
            self.next_bp_number,
            filename,
            lineno,
            temporary,
            cond,
            funcname,
        );
        self.next_bp_number += 1;

        try self.breakpoints.append(self.allocator, bp);

        // Add to file index
        if (self.bp_by_file.getPtr(filename)) |list| {
            try list.append(self.allocator, self.breakpoints.items.len - 1);
        } else {
            var list: std.ArrayList(usize) = .{};
            try list.append(self.allocator, self.breakpoints.items.len - 1);
            try self.bp_by_file.put(filename, list);
        }

        return &self.breakpoints.items[self.breakpoints.items.len - 1];
    }

    /// Clear a breakpoint by number
    pub fn clearBreak(self: *Self, number: usize) bool {
        for (self.breakpoints.items, 0..) |*bp, i| {
            if (bp.number == number) {
                bp.enabled = false; // Mark as disabled (could also remove)
                _ = i;
                return true;
            }
        }
        return false;
    }

    /// Clear breakpoints at a specific file:line
    pub fn clearBreakpoint(self: *Self, filename: []const u8, lineno: usize) usize {
        var cleared: usize = 0;
        for (self.breakpoints.items) |*bp| {
            if (std.mem.eql(u8, bp.file, filename) and bp.line == lineno) {
                bp.enabled = false;
                cleared += 1;
            }
        }
        return cleared;
    }

    /// Get breakpoints at a location
    pub fn getBreaks(self: *Self, filename: []const u8, lineno: usize) std.ArrayList(*Breakpoint) {
        var result: std.ArrayList(*Breakpoint) = .{};
        for (self.breakpoints.items) |*bp| {
            if (std.mem.eql(u8, bp.file, filename) and bp.line == lineno and bp.enabled) {
                result.append(self.allocator, bp) catch unreachable;
            }
        }
        return result;
    }

    /// Get all breakpoints
    pub fn getAllBreaks(self: *Self) []Breakpoint {
        return self.breakpoints.items;
    }

    /// Check if there's a breakpoint at location
    pub fn breakHere(self: *Self, filename: []const u8, lineno: usize) bool {
        for (self.breakpoints.items) |bp| {
            if (bp.enabled and std.mem.eql(u8, bp.file, filename) and bp.line == lineno) {
                return true;
            }
        }
        return false;
    }

    /// Check breakpoint condition and handle hit
    /// If frame is provided, uses it for condition evaluation context
    pub fn effectiveBreakpoint(self: *Self, filename: []const u8, lineno: usize) ?*Breakpoint {
        return self.effectiveBreakpointWithFrame(filename, lineno, null);
    }

    /// Check breakpoint condition and handle hit with optional frame context
    pub fn effectiveBreakpointWithFrame(self: *Self, filename: []const u8, lineno: usize, frame: ?*FrameInfo) ?*Breakpoint {
        for (self.breakpoints.items) |*bp| {
            if (!bp.enabled) continue;
            if (!std.mem.eql(u8, bp.file, filename)) continue;
            if (bp.line != lineno) continue;

            bp.hits += 1;

            // Check ignore count
            if (bp.ignore > 0) {
                bp.ignore -= 1;
                return null;
            }

            // Check condition
            if (bp.cond) |cond| {
                if (!Breakpoint.evaluateCondition(cond, frame)) {
                    // Condition is false, don't break
                    continue;
                }
            }

            return bp;
        }
        return null;
    }

    // ========================================================================
    // Execution Control
    // ========================================================================

    /// Continue execution until next breakpoint
    pub fn setContinue(self: *Self) void {
        self.stopframe = null;
        self.returnframe = null;
        self.quitting = false;
        self.stop_here = false;
    }

    /// Step to next line (into functions)
    pub fn setStep(self: *Self) void {
        self.stop_here = true;
        self.stop_reason = .step;
    }

    /// Step to next line (over functions)
    pub fn setNext(self: *Self, frame: *FrameInfo) void {
        self.stop_here = true;
        self.stopframe = frame;
        self.stop_reason = .next;
    }

    /// Continue until return from current function
    pub fn setReturn(self: *Self, frame: *FrameInfo) void {
        self.stop_here = true;
        self.returnframe = frame;
        self.stop_reason = .return_;
    }

    /// Stop execution
    pub fn setQuit(self: *Self) void {
        self.quitting = true;
        self.stop_reason = .quit;
    }

    /// Check if should stop at this frame
    pub fn stopHere(self: *Self, frame: *FrameInfo) bool {
        if (self.stop_here) return true;
        if (self.stopframe) |sf| {
            return sf == frame;
        }
        return false;
    }

    // ========================================================================
    // Frame Operations
    // ========================================================================

    /// Set up stack from current frame
    pub fn setup(self: *Self, frame: *FrameInfo) void {
        self.curframe = frame;
        self.stack.clearRetainingCapacity();
        self.stack.append(frame) catch unreachable;
        self.curindex = 0;
    }

    /// Move up one frame
    pub fn frameUp(self: *Self) ?*FrameInfo {
        if (self.curindex + 1 < self.stack.items.len) {
            self.curindex += 1;
            self.curframe = self.stack.items[self.curindex];
            return self.curframe;
        }
        return null;
    }

    /// Move down one frame
    pub fn frameDown(self: *Self) ?*FrameInfo {
        if (self.curindex > 0) {
            self.curindex -= 1;
            self.curframe = self.stack.items[self.curindex];
            return self.curframe;
        }
        return null;
    }

    // ========================================================================
    // Trace Functions (callbacks from execution)
    // ========================================================================

    /// Called on function call
    pub fn dispatchCall(self: *Self, frame: *FrameInfo) void {
        if (self.quitting) return;

        // Check if we should stop
        if (self.stopframe != null or self.returnframe != null) {
            // Stepping through, might need to stop
        }

        self.stack.append(self.allocator, frame) catch unreachable;
    }

    /// Called on line execution
    pub fn dispatchLine(self: *Self, frame: *FrameInfo) void {
        if (self.quitting) return;

        // Check for breakpoint
        if (self.effectiveBreakpoint(frame.filename, frame.lineno)) |bp| {
            self.stop_reason = .breakpoint;
            if (self.on_breakpoint) |cb| {
                cb(self, bp);
            }
            // If temporary, clear it
            if (bp.temporary) {
                bp.enabled = false;
            }
        }

        // Check if we should stop
        if (self.stopHere(frame)) {
            self.curframe = frame;
            if (self.on_stop) |cb| {
                cb(self);
            }
        }
    }

    /// Called on function return
    pub fn dispatchReturn(self: *Self, frame: *FrameInfo, retval: ?*anyopaque) void {
        _ = retval;
        if (self.quitting) return;

        if (self.returnframe) |rf| {
            if (rf == frame) {
                self.stop_reason = .return_;
                self.curframe = frame;
                if (self.on_stop) |cb| {
                    cb(self);
                }
            }
        }

        _ = self.stack.popOrNull();
    }

    /// Called on exception
    pub fn dispatchException(self: *Self, frame: *FrameInfo, exc_info: anytype) void {
        _ = exc_info;
        if (self.quitting) return;

        self.stop_reason = .exception;
        self.curframe = frame;
        if (self.on_stop) |cb| {
            cb(self);
        }
    }

    // ========================================================================
    // Source Code Helpers
    // ========================================================================

    /// Format a stack entry for display
    pub fn formatStackEntry(self: *Self, frame: *FrameInfo) ![]u8 {
        var buf: [512]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "  File \"{s}\", line {d}, in {s}", .{
            frame.filename,
            frame.lineno,
            frame.function,
        }) catch return "";

        return self.allocator.dupe(u8, str) catch return "";
    }

    /// Print stack trace
    pub fn printStack(self: *Self, writer: anytype) !void {
        try writer.writeAll("Traceback (most recent call last):\n");
        for (self.stack.items) |frame| {
            const entry = try self.formatStackEntry(frame);
            defer self.allocator.free(entry);
            try writer.print("{s}\n", .{entry});
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Bdb init and deinit" {
    const allocator = std.testing.allocator;
    var bdb = Bdb.init(allocator);
    defer bdb.deinit();

    try std.testing.expect(!bdb.quitting);
    try std.testing.expect(bdb.curframe == null);
}

test "Bdb setBreak" {
    const allocator = std.testing.allocator;
    var bdb = Bdb.init(allocator);
    defer bdb.deinit();

    const bp = try bdb.setBreak("test.py", 10, false, null, null);
    try std.testing.expectEqual(@as(usize, 1), bp.number);
    try std.testing.expectEqual(@as(usize, 1), bdb.breakpoints.items.len);
}

test "Bdb clearBreak" {
    const allocator = std.testing.allocator;
    var bdb = Bdb.init(allocator);
    defer bdb.deinit();

    _ = try bdb.setBreak("test.py", 10, false, null, null);
    try std.testing.expect(bdb.clearBreak(1));
    try std.testing.expect(!bdb.clearBreak(999));
}

test "Bdb breakHere" {
    const allocator = std.testing.allocator;
    var bdb = Bdb.init(allocator);
    defer bdb.deinit();

    _ = try bdb.setBreak("test.py", 10, false, null, null);
    try std.testing.expect(bdb.breakHere("test.py", 10));
    try std.testing.expect(!bdb.breakHere("test.py", 20));
    try std.testing.expect(!bdb.breakHere("other.py", 10));
}

test "Bdb control methods" {
    const allocator = std.testing.allocator;
    var bdb = Bdb.init(allocator);
    defer bdb.deinit();

    bdb.setStep();
    try std.testing.expect(bdb.stop_here);
    try std.testing.expectEqual(StopReason.step, bdb.stop_reason.?);

    bdb.setContinue();
    try std.testing.expect(!bdb.stop_here);

    bdb.setQuit();
    try std.testing.expect(bdb.quitting);
}

test "Bdb reset" {
    const allocator = std.testing.allocator;
    var bdb = Bdb.init(allocator);
    defer bdb.deinit();

    bdb.setQuit();
    try std.testing.expect(bdb.quitting);

    bdb.reset();
    try std.testing.expect(!bdb.quitting);
    try std.testing.expect(bdb.stop_reason == null);
}
