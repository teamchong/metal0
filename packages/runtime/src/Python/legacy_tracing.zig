/// legacy_tracing - Legacy Tracing Support
/// Mirrors cpython/Python/legacy_tracing.c
///
/// This module provides legacy tracing callbacks (sys.settrace/setprofile):
/// - Frame tracing (call/return/line/exception)
/// - Profile hooks
/// - Integration with sys module
/// - Thread-local tracing state

const std = @import("std");
const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Value;

// ============================================================================
// Trace Event Types
// ============================================================================

/// Trace event types
pub const TraceEvent = enum(i32) {
    call = 0, // Function call
    exception = 1, // Exception raised
    line = 2, // Line executed
    return_event = 3, // Function return
    c_call = 4, // C function call
    c_exception = 5, // C function exception
    c_return = 6, // C function return
    opcode = 7, // Opcode executed (per-opcode tracing)

    pub fn fromInt(val: i32) ?TraceEvent {
        return switch (val) {
            0 => .call,
            1 => .exception,
            2 => .line,
            3 => .return_event,
            4 => .c_call,
            5 => .c_exception,
            6 => .c_return,
            7 => .opcode,
            else => null,
        };
    }

    pub fn name(self: TraceEvent) []const u8 {
        return switch (self) {
            .call => "call",
            .exception => "exception",
            .line => "line",
            .return_event => "return",
            .c_call => "c_call",
            .c_exception => "c_exception",
            .c_return => "c_return",
            .opcode => "opcode",
        };
    }
};

// ============================================================================
// Frame Info (simplified)
// ============================================================================

/// Information about a stack frame
pub const FrameInfo = struct {
    /// Filename
    filename: []const u8,
    /// Function name
    funcname: []const u8,
    /// Line number
    lineno: u32,
    /// Local variables (simplified)
    locals: ?*anyopaque,
    /// Global variables (simplified)
    globals: ?*anyopaque,

    const Self = @This();

    pub fn init(filename: []const u8, funcname: []const u8, lineno: u32) Self {
        return .{
            .filename = filename,
            .funcname = funcname,
            .lineno = lineno,
            .locals = null,
            .globals = null,
        };
    }
};

// ============================================================================
// Trace Callback Types
// ============================================================================

/// Trace function callback type
pub const TraceFn = *const fn (frame: *FrameInfo, event: TraceEvent, arg: ?*anyopaque) callconv(.C) i32;

/// Profile function callback type (same signature)
pub const ProfileFn = TraceFn;

// ============================================================================
// Trace State
// ============================================================================

/// Per-thread tracing state
pub const TraceState = struct {
    /// Trace function (sys.settrace)
    trace_fn: ?TraceFn = null,
    /// Profile function (sys.setprofile)
    profile_fn: ?ProfileFn = null,
    /// User data for trace function
    trace_arg: ?*anyopaque = null,
    /// User data for profile function
    profile_arg: ?*anyopaque = null,
    /// Whether tracing is active
    tracing: bool = false,
    /// Current trace depth (to prevent recursion)
    trace_depth: u32 = 0,
    /// Maximum trace depth
    max_trace_depth: u32 = 100,
    /// Use opcode tracing
    use_opcode_tracing: bool = false,
    /// Line number tracing enabled
    line_tracing: bool = true,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    /// Set trace function
    pub fn setTrace(self: *Self, func: ?TraceFn, arg: ?*anyopaque) void {
        self.trace_fn = func;
        self.trace_arg = arg;
    }

    /// Set profile function
    pub fn setProfile(self: *Self, func: ?ProfileFn, arg: ?*anyopaque) void {
        self.profile_fn = func;
        self.profile_arg = arg;
    }

    /// Clear trace function
    pub fn clearTrace(self: *Self) void {
        self.trace_fn = null;
        self.trace_arg = null;
    }

    /// Clear profile function
    pub fn clearProfile(self: *Self) void {
        self.profile_fn = null;
        self.profile_arg = null;
    }

    /// Check if tracing is enabled
    pub fn isTracing(self: *const Self) bool {
        return self.trace_fn != null;
    }

    /// Check if profiling is enabled
    pub fn isProfiling(self: *const Self) bool {
        return self.profile_fn != null;
    }

    /// Check if any callback is active
    pub fn isActive(self: *const Self) bool {
        return self.isTracing() or self.isProfiling();
    }
};

// ============================================================================
// Thread-Local State
// ============================================================================

threadlocal var tls_trace_state: TraceState = TraceState.init();

/// Get thread-local trace state
pub fn getTraceState() *TraceState {
    return &tls_trace_state;
}

// ============================================================================
// Tracing Functions
// ============================================================================

/// Call the trace function for an event
pub fn callTrace(frame: *FrameInfo, event: TraceEvent, arg: ?*anyopaque) i32 {
    const state = getTraceState();

    // Check for recursion
    if (state.tracing) return 0;
    if (state.trace_depth >= state.max_trace_depth) return 0;

    const trace_fn = state.trace_fn orelse return 0;

    // Skip line events if line tracing is disabled
    if (event == .line and !state.line_tracing) return 0;

    // Skip opcode events if opcode tracing is disabled
    if (event == .opcode and !state.use_opcode_tracing) return 0;

    state.tracing = true;
    state.trace_depth += 1;
    defer {
        state.tracing = false;
        state.trace_depth -= 1;
    }

    return trace_fn(frame, event, arg orelse state.trace_arg);
}

/// Call the profile function for an event
pub fn callProfile(frame: *FrameInfo, event: TraceEvent, arg: ?*anyopaque) i32 {
    const state = getTraceState();

    // Profile only traces call/return/exception
    switch (event) {
        .call, .return_event, .exception, .c_call, .c_return, .c_exception => {},
        else => return 0,
    }

    const profile_fn = state.profile_fn orelse return 0;

    // Prevent recursion
    if (state.tracing) return 0;

    state.tracing = true;
    defer state.tracing = false;

    return profile_fn(frame, event, arg orelse state.profile_arg);
}

/// Dispatch trace event
pub fn dispatchTrace(frame: *FrameInfo, event: TraceEvent, arg: ?*anyopaque) i32 {
    var result: i32 = 0;

    // Call trace function first
    result = callTrace(frame, event, arg);
    if (result != 0) return result;

    // Then profile function
    result = callProfile(frame, event, arg);
    return result;
}

// ============================================================================
// sys.settrace / sys.setprofile Interface
// ============================================================================

/// Set the trace function (sys.settrace)
pub fn sysSetTrace(func: ?TraceFn, arg: ?*anyopaque) void {
    getTraceState().setTrace(func, arg);
}

/// Get the trace function (sys.gettrace)
pub fn sysGetTrace() ?TraceFn {
    return getTraceState().trace_fn;
}

/// Set the profile function (sys.setprofile)
pub fn sysSetProfile(func: ?ProfileFn, arg: ?*anyopaque) void {
    getTraceState().setProfile(func, arg);
}

/// Get the profile function (sys.getprofile)
pub fn sysGetProfile() ?ProfileFn {
    return getTraceState().profile_fn;
}

// ============================================================================
// Event Helper Functions
// ============================================================================

/// Trace a function call
pub fn traceCall(frame: *FrameInfo) i32 {
    return dispatchTrace(frame, .call, null);
}

/// Trace a function return
pub fn traceReturn(frame: *FrameInfo, return_value: ?*anyopaque) i32 {
    return dispatchTrace(frame, .return_event, return_value);
}

/// Trace a line execution
pub fn traceLine(frame: *FrameInfo) i32 {
    return dispatchTrace(frame, .line, null);
}

/// Trace an exception
pub fn traceException(frame: *FrameInfo, exc_info: ?*anyopaque) i32 {
    return dispatchTrace(frame, .exception, exc_info);
}

/// Trace a C function call
pub fn traceCCall(frame: *FrameInfo, cfunc: ?*anyopaque) i32 {
    return dispatchTrace(frame, .c_call, cfunc);
}

/// Trace a C function return
pub fn traceCReturn(frame: *FrameInfo, cfunc: ?*anyopaque) i32 {
    return dispatchTrace(frame, .c_return, cfunc);
}

/// Trace a C function exception
pub fn traceCException(frame: *FrameInfo, cfunc: ?*anyopaque) i32 {
    return dispatchTrace(frame, .c_exception, cfunc);
}

/// Trace an opcode
pub fn traceOpcode(frame: *FrameInfo, opcode: i32) i32 {
    var opcode_ptr: i32 = opcode;
    return dispatchTrace(frame, .opcode, @ptrCast(&opcode_ptr));
}

// ============================================================================
// Configuration
// ============================================================================

/// Enable opcode-level tracing
pub fn enableOpcodeTracing() void {
    getTraceState().use_opcode_tracing = true;
}

/// Disable opcode-level tracing
pub fn disableOpcodeTracing() void {
    getTraceState().use_opcode_tracing = false;
}

/// Enable line tracing
pub fn enableLineTracing() void {
    getTraceState().line_tracing = true;
}

/// Disable line tracing
pub fn disableLineTracing() void {
    getTraceState().line_tracing = false;
}

/// Set maximum trace depth
pub fn setMaxTraceDepth(depth: u32) void {
    getTraceState().max_trace_depth = depth;
}

// ============================================================================
// Debug Trace Function
// ============================================================================

/// Simple debug trace function that prints events
pub fn debugTraceFn(frame: *FrameInfo, event: TraceEvent, arg: ?*anyopaque) callconv(.C) i32 {
    _ = arg;
    const stderr = std.io.getStdErr().writer();
    stderr.print("[TRACE] {s}:{d} {s}() - {s}\n", .{
        frame.filename,
        frame.lineno,
        frame.funcname,
        event.name(),
    }) catch {};
    return 0;
}

/// Install debug trace function
pub fn installDebugTrace() void {
    sysSetTrace(debugTraceFn, null);
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "trace event names" {
    try std.testing.expectEqualStrings("call", TraceEvent.call.name());
    try std.testing.expectEqualStrings("return", TraceEvent.return_event.name());
    try std.testing.expectEqualStrings("line", TraceEvent.line.name());
    try std.testing.expectEqualStrings("exception", TraceEvent.exception.name());
}

test "trace event from int" {
    try std.testing.expectEqual(TraceEvent.call, TraceEvent.fromInt(0).?);
    try std.testing.expectEqual(TraceEvent.exception, TraceEvent.fromInt(1).?);
    try std.testing.expect(TraceEvent.fromInt(100) == null);
}

test "frame info" {
    const frame = FrameInfo.init("test.py", "test_func", 42);
    try std.testing.expectEqualStrings("test.py", frame.filename);
    try std.testing.expectEqualStrings("test_func", frame.funcname);
    try std.testing.expectEqual(@as(u32, 42), frame.lineno);
}

test "trace state init" {
    var state = TraceState.init();
    try std.testing.expect(!state.isTracing());
    try std.testing.expect(!state.isProfiling());
    try std.testing.expect(!state.isActive());
}

test "trace state set/clear" {
    var state = TraceState.init();

    state.setTrace(debugTraceFn, null);
    try std.testing.expect(state.isTracing());
    try std.testing.expect(state.isActive());

    state.clearTrace();
    try std.testing.expect(!state.isTracing());

    state.setProfile(debugTraceFn, null);
    try std.testing.expect(state.isProfiling());

    state.clearProfile();
    try std.testing.expect(!state.isProfiling());
}

test "trace depth" {
    var state = TraceState.init();
    try std.testing.expectEqual(@as(u32, 0), state.trace_depth);
    try std.testing.expectEqual(@as(u32, 100), state.max_trace_depth);
}
