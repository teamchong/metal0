/// session - Debug Session Management
/// Session state, stepping, breakpoint checking logic.

const std = @import("std");
const Allocator = std.mem.Allocator;
const BreakpointManager = @import("breakpoint.zig").BreakpointManager;

// ============================================================================
// Debug Session
// ============================================================================

/// Debug session state
pub const SessionState = enum {
    /// Not connected
    disconnected,
    /// Connected, running
    running,
    /// Paused at breakpoint
    paused,
    /// Stepping
    stepping,
    /// Terminated
    terminated,
};

/// Step mode
pub const StepMode = enum {
    none,
    over,
    into,
    out,
};

/// Debug session
pub const DebugSession = struct {
    const Self = @This();

    /// Session state
    state: SessionState = .disconnected,
    /// Breakpoint manager
    breakpoints: BreakpointManager,
    /// Current step mode
    step_mode: StepMode = .none,
    /// Step target depth (for step out)
    step_depth: u32 = 0,
    /// Current frame ID
    current_frame: u32 = 0,
    /// Pending evaluation result
    eval_result: ?[]const u8 = null,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .breakpoints = BreakpointManager.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.breakpoints.deinit();
        if (self.eval_result) |r| {
            self.allocator.free(r);
        }
    }

    /// Connect debugger
    pub fn connect(self: *Self) void {
        self.state = .running;
    }

    /// Disconnect debugger
    pub fn disconnect(self: *Self) void {
        self.state = .disconnected;
        self.step_mode = .none;
    }

    /// Pause execution
    pub fn pause(self: *Self) void {
        if (self.state == .running) {
            self.state = .paused;
        }
    }

    /// Continue execution
    pub fn continueExec(self: *Self) void {
        if (self.state == .paused) {
            self.state = .running;
            self.step_mode = .none;
        }
    }

    /// Step over
    pub fn stepOver(self: *Self, depth: u32) void {
        if (self.state == .paused) {
            self.state = .stepping;
            self.step_mode = .over;
            self.step_depth = depth;
        }
    }

    /// Step into
    pub fn stepInto(self: *Self) void {
        if (self.state == .paused) {
            self.state = .stepping;
            self.step_mode = .into;
        }
    }

    /// Step out
    pub fn stepOut(self: *Self, depth: u32) void {
        if (self.state == .paused) {
            self.state = .stepping;
            self.step_mode = .out;
            self.step_depth = depth;
        }
    }

    /// Check if should break at location
    pub fn shouldBreak(self: *Self, file: []const u8, line: u32, depth: u32) bool {
        switch (self.state) {
            .running => {
                // Check breakpoints
                return self.breakpoints.hasBreakpoint(file, line);
            },
            .stepping => {
                switch (self.step_mode) {
                    .into => return true,
                    .over => return depth <= self.step_depth,
                    .out => return depth < self.step_depth,
                    .none => return false,
                }
            },
            else => return false,
        }
    }

    /// Notify breakpoint hit
    pub fn notifyBreakpointHit(self: *Self, _: u32) void {
        self.state = .paused;
        self.step_mode = .none;
    }

    /// Is debugger attached
    pub fn isAttached(self: *const Self) bool {
        return self.state != .disconnected and self.state != .terminated;
    }
};
