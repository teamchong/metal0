/// remote_debugging - Remote Debugging Support
/// Mirrors cpython/Python/remote_debugging.c
///
/// Support for remote debugging of Python processes.
/// Allows debuggers to attach, set breakpoints, and inspect state.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Debug Protocol
// ============================================================================

/// Debug protocol version
pub const PROTOCOL_VERSION: u32 = 1;

/// Debug message types
pub const MessageType = enum(u8) {
    /// Connection handshake
    hello = 0,
    /// Set breakpoint
    set_breakpoint = 1,
    /// Remove breakpoint
    remove_breakpoint = 2,
    /// Continue execution
    continue_exec = 3,
    /// Step over
    step_over = 4,
    /// Step into
    step_into = 5,
    /// Step out
    step_out = 6,
    /// Evaluate expression
    evaluate = 7,
    /// Get stack frames
    get_frames = 8,
    /// Get variables
    get_variables = 9,
    /// Pause execution
    pause = 10,
    /// Disconnect
    disconnect = 11,
    /// Notification (server to client)
    notification = 12,
    /// Response
    response = 13,
    /// Error
    err = 14,
};

/// Debug notifications
pub const Notification = enum(u8) {
    /// Hit breakpoint
    breakpoint_hit = 0,
    /// Exception raised
    exception = 1,
    /// Step completed
    step_completed = 2,
    /// Process exited
    exited = 3,
    /// Output (stdout/stderr)
    output = 4,
};

// ============================================================================
// Breakpoint
// ============================================================================

/// Breakpoint entry
pub const Breakpoint = struct {
    /// Unique ID
    id: u32,
    /// Source file
    file: []const u8,
    /// Line number
    line: u32,
    /// Condition expression (optional)
    condition: ?[]const u8 = null,
    /// Hit count threshold (0 = always)
    hit_count_threshold: u32 = 0,
    /// Current hit count
    hit_count: u32 = 0,
    /// Is enabled
    enabled: bool = true,
    /// Log message instead of breaking
    log_message: ?[]const u8 = null,
};

/// Breakpoint manager
pub const BreakpointManager = struct {
    const Self = @This();

    /// Breakpoints by ID
    breakpoints: std.AutoHashMap(u32, Breakpoint),
    /// Breakpoints by file:line
    by_location: hashmap_helper.StringHashMap(std.ArrayList(u32)),
    /// Next breakpoint ID
    next_id: u32 = 1,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .breakpoints = std.AutoHashMap(u32, Breakpoint).init(allocator),
            .by_location = hashmap_helper.StringHashMap(std.ArrayList(u32)).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.by_location.valueIterator();
        while (it.next()) |list| {
            list.deinit();
        }
        self.by_location.deinit();
        self.breakpoints.deinit();
    }

    /// Add a breakpoint
    pub fn addBreakpoint(self: *Self, file: []const u8, line: u32) !u32 {
        const id = self.next_id;
        self.next_id += 1;

        try self.breakpoints.put(id, .{
            .id = id,
            .file = file,
            .line = line,
        });

        // Index by location
        var buf: [512]u8 = undefined;
        const key = try std.fmt.bufPrint(&buf, "{s}:{d}", .{ file, line });
        const key_copy = try self.allocator.dupe(u8, key);

        const result = try self.by_location.getOrPut(key_copy);
        if (!result.found_existing) {
            result.value_ptr.* = std.ArrayList(u32).init(self.allocator);
        }
        try result.value_ptr.append(id);

        return id;
    }

    /// Remove a breakpoint
    pub fn removeBreakpoint(self: *Self, id: u32) bool {
        return self.breakpoints.remove(id);
    }

    /// Check if location has breakpoint
    pub fn hasBreakpoint(self: *const Self, file: []const u8, line: u32) bool {
        var buf: [512]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "{s}:{d}", .{ file, line }) catch return false;
        return self.by_location.contains(key);
    }

    /// Get breakpoint by ID
    pub fn getBreakpoint(self: *Self, id: u32) ?*Breakpoint {
        return self.breakpoints.getPtr(id);
    }

    /// Enable/disable breakpoint
    pub fn setEnabled(self: *Self, id: u32, enabled: bool) void {
        if (self.breakpoints.getPtr(id)) |bp| {
            bp.enabled = enabled;
        }
    }
};

// ============================================================================
// Stack Frame
// ============================================================================

/// Stack frame for debugging
pub const StackFrame = struct {
    /// Frame ID
    id: u32,
    /// Function name
    name: []const u8,
    /// Source file
    file: []const u8,
    /// Current line
    line: u32,
    /// Column
    column: u16 = 0,
    /// Local variables scope ID
    locals_scope: u32 = 0,
    /// Global variables scope ID
    globals_scope: u32 = 0,
};

/// Variable for debugging
pub const Variable = struct {
    /// Variable name
    name: []const u8,
    /// Value as string
    value: []const u8,
    /// Type name
    type_name: []const u8,
    /// Whether expandable (has children)
    has_children: bool = false,
    /// Number of children
    children_count: usize = 0,
    /// Variable reference (for expansion)
    reference: u32 = 0,
};

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

// ============================================================================
// Debug Server
// ============================================================================

/// Debug server configuration
pub const ServerConfig = struct {
    /// Listen address
    address: []const u8 = "127.0.0.1",
    /// Listen port
    port: u16 = 5678,
    /// Wait for debugger on start
    wait_on_start: bool = false,
    /// Break on exception
    break_on_exception: bool = true,
    /// Log level
    log_level: u8 = 0,
};

/// Debug server
pub const DebugServer = struct {
    const Self = @This();

    /// Configuration
    config: ServerConfig,
    /// Active session
    session: ?DebugSession = null,
    /// Is listening
    listening: bool = false,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator, config: ServerConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.session) |*s| {
            s.deinit();
        }
    }

    /// Start server
    pub fn start(self: *Self) !void {
        // Would start TCP server listening on config.address:config.port
        self.listening = true;

        if (self.config.wait_on_start) {
            // Block until debugger connects
            try self.waitForConnection();
        }
    }

    /// Stop server
    pub fn stop(self: *Self) void {
        if (self.session) |*s| {
            s.disconnect();
        }
        self.listening = false;
    }

    /// Wait for debugger connection
    fn waitForConnection(self: *Self) !void {
        // Would block until client connects
        self.session = DebugSession.init(self.allocator);
        self.session.?.connect();
    }

    /// Check if debugger is connected
    pub fn isConnected(self: *const Self) bool {
        if (self.session) |s| {
            return s.isAttached();
        }
        return false;
    }
};

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
    if (global_server) |*server| {
        server.stop();
    }
}

/// Reset module state
pub fn reset() void {
    if (global_server) |*server| {
        server.deinit();
    }
    global_server = null;
    initialized = false;
}

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
