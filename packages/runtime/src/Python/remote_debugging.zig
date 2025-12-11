/// remote_debugging - Remote Debugging Support
/// Mirrors cpython/Python/remote_debugging.c
///
/// Support for remote debugging of Python processes.
/// Allows debuggers to attach, set breakpoints, and inspect state.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Submodules
// ============================================================================

pub const protocol = @import("remote_debugging/protocol.zig");
pub const breakpoint = @import("remote_debugging/breakpoint.zig");
pub const stack_frame = @import("remote_debugging/stack_frame.zig");
pub const session = @import("remote_debugging/session.zig");
pub const server = @import("remote_debugging/server.zig");

// ============================================================================
// Re-exports
// ============================================================================

// Protocol types
pub const PROTOCOL_VERSION = protocol.PROTOCOL_VERSION;
pub const MessageType = protocol.MessageType;
pub const Notification = protocol.Notification;

// Breakpoint types
pub const Breakpoint = breakpoint.Breakpoint;
pub const BreakpointManager = breakpoint.BreakpointManager;

// Stack frame types
pub const StackFrame = stack_frame.StackFrame;
pub const Variable = stack_frame.Variable;

// Session types
pub const SessionState = session.SessionState;
pub const StepMode = session.StepMode;
pub const DebugSession = session.DebugSession;

// Server types
pub const ServerConfig = server.ServerConfig;
pub const DebugServer = server.DebugServer;

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;
var global_server: ?DebugServer = null;

/// Initialize the remote_debugging module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Get debug server
pub fn getServer(allocator: Allocator) *DebugServer {
    if (global_server == null) {
        global_server = DebugServer.init(allocator, .{});
    }
    return &global_server.?;
}

/// Enable remote debugging
pub fn enable(allocator: Allocator, config: ServerConfig) !void {
    if (global_server == null) {
        global_server = DebugServer.init(allocator, config);
    }
    try global_server.?.start();
}

/// Disable remote debugging
pub fn disable() void {
    if (global_server) |*srv| {
        srv.stop();
    }
}

/// Reset module state
pub fn reset() void {
    if (global_server) |*srv| {
        srv.deinit();
    }
    global_server = null;
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test {
    _ = @import("remote_debugging/tests.zig");
}
