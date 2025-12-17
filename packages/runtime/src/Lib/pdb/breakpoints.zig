//! Breakpoint management for the Python debugger
//!
//! Handles setting, clearing, and querying breakpoints.

const std = @import("std");
const types = @import("types.zig");
const Breakpoint = types.Breakpoint;

/// Breakpoint management methods for Pdb
pub const BreakpointManager = struct {
    /// Set a breakpoint
    pub fn setBreak(
        breakpoints: *std.ArrayList(Breakpoint),
        bp_counter: *u32,
        filename: []const u8,
        lineno: usize,
        temporary: bool,
        cond: ?[]const u8,
    ) !u32 {
        bp_counter.* += 1;
        var bp = Breakpoint.init(bp_counter.*, filename, lineno, temporary);
        bp.condition = cond;
        try breakpoints.append(bp);
        return bp_counter.*;
    }

    /// Clear a breakpoint by number
    pub fn clearBreak(breakpoints: *std.ArrayList(Breakpoint), number: u32) bool {
        for (breakpoints.items, 0..) |bp, i| {
            if (bp.number == number) {
                _ = breakpoints.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Clear all breakpoints
    pub fn clearAllBreaks(breakpoints: *std.ArrayList(Breakpoint)) void {
        breakpoints.clearRetainingCapacity();
    }

    /// Get breakpoint by number
    pub fn getBreak(breakpoints: *std.ArrayList(Breakpoint), number: u32) ?*Breakpoint {
        for (breakpoints.items) |*bp| {
            if (bp.number == number) {
                return bp;
            }
        }
        return null;
    }

    /// Get all breakpoints at a location
    pub fn getBreaks(breakpoints: *std.ArrayList(Breakpoint), allocator: std.mem.Allocator, filename: []const u8, lineno: usize) []Breakpoint {
        var result: std.ArrayList(Breakpoint) = .{};
        for (breakpoints.items) |bp| {
            if (std.mem.eql(u8, bp.file, filename) and bp.line == lineno) {
                result.append(allocator, bp) catch unreachable;
            }
        }
        return result.toOwnedSlice(allocator) catch &[_]Breakpoint{};
    }

    /// Check if there's a breakpoint at given location
    pub fn hasBreakpoint(breakpoints: *std.ArrayList(Breakpoint), filename: []const u8, lineno: usize) bool {
        for (breakpoints.items) |bp| {
            if (bp.enabled and bp.line == lineno and std.mem.eql(u8, bp.file, filename)) {
                return true;
            }
        }
        return false;
    }
};
