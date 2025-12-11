/// tests - Remote Debugging Tests
/// Unit tests for breakpoints, session, and server.

const std = @import("std");
const breakpoint_mod = @import("breakpoint.zig");
const session_mod = @import("session.zig");
const server_mod = @import("server.zig");
const stack_frame_mod = @import("stack_frame.zig");

const BreakpointManager = breakpoint_mod.BreakpointManager;
const DebugSession = session_mod.DebugSession;
const SessionState = session_mod.SessionState;
const StepMode = session_mod.StepMode;
const DebugServer = server_mod.DebugServer;
const StackFrame = stack_frame_mod.StackFrame;
const Variable = stack_frame_mod.Variable;

// ============================================================================
// Tests
// ============================================================================

test "breakpoint manager" {
    const allocator = std.testing.allocator;
    var manager = BreakpointManager.init(allocator);
    defer manager.deinit();

    const id = try manager.addBreakpoint("test.py", 10);
    try std.testing.expect(id > 0);

    const bp = manager.getBreakpoint(id);
    try std.testing.expect(bp != null);
    try std.testing.expectEqual(@as(u32, 10), bp.?.line);
    try std.testing.expect(bp.?.enabled);
}

test "debug session state" {
    const allocator = std.testing.allocator;
    var session = DebugSession.init(allocator);
    defer session.deinit();

    try std.testing.expectEqual(SessionState.disconnected, session.state);

    session.connect();
    try std.testing.expectEqual(SessionState.running, session.state);
    try std.testing.expect(session.isAttached());

    session.pause();
    try std.testing.expectEqual(SessionState.paused, session.state);

    session.continueExec();
    try std.testing.expectEqual(SessionState.running, session.state);

    session.disconnect();
    try std.testing.expectEqual(SessionState.disconnected, session.state);
    try std.testing.expect(!session.isAttached());
}

test "step modes" {
    const allocator = std.testing.allocator;
    var session = DebugSession.init(allocator);
    defer session.deinit();

    session.connect();
    session.pause();

    session.stepInto();
    try std.testing.expectEqual(SessionState.stepping, session.state);
    try std.testing.expectEqual(StepMode.into, session.step_mode);

    session.state = .paused;
    session.stepOver(5);
    try std.testing.expectEqual(StepMode.over, session.step_mode);
    try std.testing.expectEqual(@as(u32, 5), session.step_depth);
}

test "should break logic" {
    const allocator = std.testing.allocator;
    var session = DebugSession.init(allocator);
    defer session.deinit();

    session.connect();

    // Add breakpoint
    _ = try session.breakpoints.addBreakpoint("test.py", 10);

    // Should break at breakpoint
    try std.testing.expect(session.shouldBreak("test.py", 10, 0));
    try std.testing.expect(!session.shouldBreak("test.py", 11, 0));
}

test "debug server" {
    const allocator = std.testing.allocator;
    var server = DebugServer.init(allocator, .{});
    defer server.deinit();

    try std.testing.expect(!server.listening);
    try std.testing.expect(!server.isConnected());
}

test "stack frame" {
    const frame = StackFrame{
        .id = 1,
        .name = "test_func",
        .file = "test.py",
        .line = 42,
    };
    try std.testing.expectEqual(@as(u32, 1), frame.id);
    try std.testing.expectEqualStrings("test_func", frame.name);
}

test "variable" {
    const variable = Variable{
        .name = "x",
        .value = "42",
        .type_name = "int",
    };
    try std.testing.expectEqualStrings("x", variable.name);
    try std.testing.expect(!variable.has_children);
}
