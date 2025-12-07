/// instrumentation - Profiling Instrumentation
/// Mirrors cpython/Python/instrumentation.c
///
/// This module provides PEP 669 monitoring/instrumentation API:
/// - Per-code-object monitoring events
/// - Tool registration and callbacks
/// - Event filtering
/// - Low-overhead instrumentation

const std = @import("std");
const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Value;

// ============================================================================
// Constants
// ============================================================================

/// Maximum number of monitoring tools
pub const MAX_TOOLS: usize = 8;

/// Number of event types
pub const NUM_EVENTS: usize = 16;

// ============================================================================
// Monitoring Events (PEP 669)
// ============================================================================

/// Monitoring event types
pub const MonitoringEvent = enum(u8) {
    py_start = 0, // Start of Python function
    py_resume = 1, // Resume after yield/await
    py_return = 2, // Return from Python function
    py_yield = 3, // Yield value
    call = 4, // Call any callable
    line = 5, // Line event
    instruction = 6, // Bytecode instruction
    jump = 7, // Jump (conditional or unconditional)
    branch = 8, // Branch taken/not taken
    stop_iteration = 9, // StopIteration raised
    raise_event = 10, // Exception raised
    exception_handled = 11, // Exception handled
    py_unwind = 12, // Unwinding Python frame
    py_throw = 13, // Throw into generator
    reraise = 14, // Re-raise exception
    c_raise = 15, // C function raised

    pub fn name(self: MonitoringEvent) []const u8 {
        return switch (self) {
            .py_start => "PY_START",
            .py_resume => "PY_RESUME",
            .py_return => "PY_RETURN",
            .py_yield => "PY_YIELD",
            .call => "CALL",
            .line => "LINE",
            .instruction => "INSTRUCTION",
            .jump => "JUMP",
            .branch => "BRANCH",
            .stop_iteration => "STOP_ITERATION",
            .raise_event => "RAISE",
            .exception_handled => "EXCEPTION_HANDLED",
            .py_unwind => "PY_UNWIND",
            .py_throw => "PY_THROW",
            .reraise => "RERAISE",
            .c_raise => "C_RAISE",
        };
    }

    pub fn toBit(self: MonitoringEvent) u16 {
        return @as(u16, 1) << @intFromEnum(self);
    }
};

// ============================================================================
// Tool IDs (PEP 669)
// ============================================================================

/// Standard tool IDs
pub const ToolId = enum(u8) {
    debugger = 0,
    coverage = 1,
    profiler = 2,
    optimizer = 3,
    // 4-5 reserved for stdlib
    // 6-7 for third-party tools
    reserved_4 = 4,
    reserved_5 = 5,
    third_party_1 = 6,
    third_party_2 = 7,

    pub fn isReserved(self: ToolId) bool {
        return @intFromEnum(self) >= 4 and @intFromEnum(self) <= 5;
    }

    pub fn isThirdParty(self: ToolId) bool {
        return @intFromEnum(self) >= 6;
    }
};

// ============================================================================
// Callback Types
// ============================================================================

/// Monitoring callback function type
pub const MonitoringCallback = *const fn (
    tool_id: ToolId,
    event: MonitoringEvent,
    code_object: ?*anyopaque,
    instruction_offset: i32,
    arg: ?*anyopaque,
) callconv(.C) ?*anyopaque;

// ============================================================================
// Tool State
// ============================================================================

/// State for a single monitoring tool
pub const ToolState = struct {
    /// Tool is registered
    registered: bool = false,
    /// Events this tool is monitoring
    events: u16 = 0,
    /// Callback for each event type
    callbacks: [NUM_EVENTS]?MonitoringCallback = [_]?MonitoringCallback{null} ** NUM_EVENTS,
    /// User data for callbacks
    user_data: ?*anyopaque = null,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    /// Register tool
    pub fn register(self: *Self) void {
        self.registered = true;
    }

    /// Unregister tool
    pub fn unregister(self: *Self) void {
        self.registered = false;
        self.events = 0;
        for (&self.callbacks) |*cb| {
            cb.* = null;
        }
        self.user_data = null;
    }

    /// Set events to monitor
    pub fn setEvents(self: *Self, events: u16) void {
        self.events = events;
    }

    /// Add events to monitor
    pub fn addEvents(self: *Self, events: u16) void {
        self.events |= events;
    }

    /// Remove events from monitoring
    pub fn removeEvents(self: *Self, events: u16) void {
        self.events &= ~events;
    }

    /// Check if monitoring an event
    pub fn isMonitoring(self: *const Self, event: MonitoringEvent) bool {
        return self.registered and (self.events & event.toBit()) != 0;
    }

    /// Set callback for an event
    pub fn setCallback(self: *Self, event: MonitoringEvent, callback: ?MonitoringCallback) void {
        self.callbacks[@intFromEnum(event)] = callback;
    }

    /// Get callback for an event
    pub fn getCallback(self: *const Self, event: MonitoringEvent) ?MonitoringCallback {
        return self.callbacks[@intFromEnum(event)];
    }
};

// ============================================================================
// Global Monitoring State
// ============================================================================

/// Global monitoring state
pub const MonitoringState = struct {
    /// Tool states
    tools: [MAX_TOOLS]ToolState = undefined,
    /// Global event mask (OR of all tool event masks)
    global_events: Atomic(u16) = Atomic(u16).init(0),
    /// Version counter for cache invalidation
    version: Atomic(u64) = Atomic(u64).init(0),
    /// Lock for registration
    lock: std.Thread.Mutex = .{},

    const Self = @This();

    pub fn init() Self {
        var self = Self{};
        for (&self.tools) |*tool| {
            tool.* = ToolState.init();
        }
        return self;
    }

    /// Register a tool
    pub fn registerTool(self: *Self, tool_id: ToolId) !void {
        self.lock.lock();
        defer self.lock.unlock();

        const idx = @intFromEnum(tool_id);
        if (idx >= MAX_TOOLS) return error.InvalidToolId;
        if (self.tools[idx].registered) return error.ToolAlreadyRegistered;

        self.tools[idx].register();
        _ = self.version.fetchAdd(1, .release);
    }

    /// Unregister a tool
    pub fn unregisterTool(self: *Self, tool_id: ToolId) void {
        self.lock.lock();
        defer self.lock.unlock();

        const idx = @intFromEnum(tool_id);
        if (idx >= MAX_TOOLS) return;

        self.tools[idx].unregister();
        self.updateGlobalEvents();
        _ = self.version.fetchAdd(1, .release);
    }

    /// Set events for a tool
    pub fn setToolEvents(self: *Self, tool_id: ToolId, events: u16) void {
        const idx = @intFromEnum(tool_id);
        if (idx >= MAX_TOOLS) return;

        self.tools[idx].setEvents(events);
        self.updateGlobalEvents();
        _ = self.version.fetchAdd(1, .release);
    }

    /// Set callback for a tool/event
    pub fn setCallback(self: *Self, tool_id: ToolId, event: MonitoringEvent, callback: ?MonitoringCallback) void {
        const idx = @intFromEnum(tool_id);
        if (idx >= MAX_TOOLS) return;

        self.tools[idx].setCallback(event, callback);
    }

    /// Update global event mask
    fn updateGlobalEvents(self: *Self) void {
        var events: u16 = 0;
        for (self.tools) |tool| {
            if (tool.registered) {
                events |= tool.events;
            }
        }
        self.global_events.store(events, .release);
    }

    /// Check if any tool is monitoring an event
    pub fn isMonitored(self: *const Self, event: MonitoringEvent) bool {
        return (self.global_events.load(.acquire) & event.toBit()) != 0;
    }

    /// Fire event to all registered tools
    pub fn fireEvent(
        self: *Self,
        event: MonitoringEvent,
        code_object: ?*anyopaque,
        instruction_offset: i32,
        arg: ?*anyopaque,
    ) void {
        if (!self.isMonitored(event)) return;

        for (self.tools, 0..) |*tool, idx| {
            if (tool.isMonitoring(event)) {
                if (tool.getCallback(event)) |callback| {
                    _ = callback(@enumFromInt(idx), event, code_object, instruction_offset, arg);
                }
            }
        }
    }
};

// ============================================================================
// Global State
// ============================================================================

var g_monitoring: MonitoringState = MonitoringState.init();

/// Get global monitoring state
pub fn getMonitoring() *MonitoringState {
    return &g_monitoring;
}

// ============================================================================
// Public API (sys.monitoring compatible)
// ============================================================================

/// Register a monitoring tool
pub fn registerTool(tool_id: ToolId) !void {
    return g_monitoring.registerTool(tool_id);
}

/// Free/unregister a monitoring tool
pub fn freeTool(tool_id: ToolId) void {
    g_monitoring.unregisterTool(tool_id);
}

/// Set events for a tool to monitor
pub fn setEvents(tool_id: ToolId, events: u16) void {
    g_monitoring.setToolEvents(tool_id, events);
}

/// Get events a tool is monitoring
pub fn getEvents(tool_id: ToolId) u16 {
    const idx = @intFromEnum(tool_id);
    if (idx >= MAX_TOOLS) return 0;
    return g_monitoring.tools[idx].events;
}

/// Set a local callback for a tool/event combination
pub fn setLocalCallback(tool_id: ToolId, event: MonitoringEvent, callback: ?MonitoringCallback) void {
    g_monitoring.setCallback(tool_id, event, callback);
}

/// Fire an event
pub fn fireEvent(event: MonitoringEvent, code_object: ?*anyopaque, offset: i32, arg: ?*anyopaque) void {
    g_monitoring.fireEvent(event, code_object, offset, arg);
}

/// Check if an event is being monitored
pub fn isEventMonitored(event: MonitoringEvent) bool {
    return g_monitoring.isMonitored(event);
}

// ============================================================================
// Code Object Instrumentation
// ============================================================================

/// Per-code-object instrumentation state
pub const CodeInstrumentation = struct {
    /// Instrumented bytecode (if modified)
    instrumented_code: ?[]u8 = null,
    /// Per-instruction monitoring
    instruction_events: ?[]u16 = null,
    /// Version when instrumentation was last updated
    version: u64 = 0,
    /// Allocator
    allocator: ?Allocator = null,

    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn deinit(self: *Self) void {
        if (self.allocator) |alloc| {
            if (self.instrumented_code) |code| {
                alloc.free(code);
            }
            if (self.instruction_events) |events| {
                alloc.free(events);
            }
        }
    }

    /// Check if instrumentation needs update
    pub fn needsUpdate(self: *const Self) bool {
        return self.version != g_monitoring.version.load(.acquire);
    }

    /// Mark as updated
    pub fn markUpdated(self: *Self) void {
        self.version = g_monitoring.version.load(.acquire);
    }
};

// ============================================================================
// Coverage Support
// ============================================================================

/// Simple coverage tracking
pub const CoverageData = struct {
    /// Lines executed (line number -> count)
    lines: std.AutoHashMap(u32, u64),
    /// Branches taken
    branches: std.AutoHashMap(u64, u64),
    /// Allocator
    allocator: Allocator,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .lines = std.AutoHashMap(u32, u64).init(allocator),
            .branches = std.AutoHashMap(u64, u64).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.lines.deinit();
        self.branches.deinit();
    }

    pub fn recordLine(self: *Self, lineno: u32) !void {
        const entry = try self.lines.getOrPut(lineno);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    pub fn recordBranch(self: *Self, from: u32, to: u32) !void {
        const key = (@as(u64, from) << 32) | @as(u64, to);
        const entry = try self.branches.getOrPut(key);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
    }

    pub fn getLineCount(self: *const Self, lineno: u32) u64 {
        return self.lines.get(lineno) orelse 0;
    }

    pub fn wasLineExecuted(self: *const Self, lineno: u32) bool {
        return self.lines.contains(lineno);
    }
};

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "monitoring event bits" {
    try std.testing.expectEqual(@as(u16, 1), MonitoringEvent.py_start.toBit());
    try std.testing.expectEqual(@as(u16, 2), MonitoringEvent.py_resume.toBit());
    try std.testing.expectEqual(@as(u16, 4), MonitoringEvent.py_return.toBit());
    try std.testing.expectEqual(@as(u16, 16), MonitoringEvent.call.toBit());
}

test "tool state basic" {
    var tool = ToolState.init();
    try std.testing.expect(!tool.registered);

    tool.register();
    try std.testing.expect(tool.registered);

    tool.setEvents(MonitoringEvent.call.toBit() | MonitoringEvent.line.toBit());
    try std.testing.expect(tool.isMonitoring(.call));
    try std.testing.expect(tool.isMonitoring(.line));
    try std.testing.expect(!tool.isMonitoring(.py_start));

    tool.removeEvents(MonitoringEvent.call.toBit());
    try std.testing.expect(!tool.isMonitoring(.call));
    try std.testing.expect(tool.isMonitoring(.line));

    tool.unregister();
    try std.testing.expect(!tool.registered);
    try std.testing.expect(!tool.isMonitoring(.line));
}

test "monitoring state" {
    var state = MonitoringState.init();

    // Register debugger
    try state.registerTool(.debugger);
    try std.testing.expect(state.tools[0].registered);

    // Can't register twice
    try std.testing.expectError(error.ToolAlreadyRegistered, state.registerTool(.debugger));

    // Set events
    state.setToolEvents(.debugger, MonitoringEvent.line.toBit() | MonitoringEvent.call.toBit());
    try std.testing.expect(state.isMonitored(.line));
    try std.testing.expect(state.isMonitored(.call));
    try std.testing.expect(!state.isMonitored(.py_start));

    // Unregister
    state.unregisterTool(.debugger);
    try std.testing.expect(!state.isMonitored(.line));
}

test "coverage data" {
    var cov = CoverageData.init(std.testing.allocator);
    defer cov.deinit();

    try cov.recordLine(10);
    try cov.recordLine(10);
    try cov.recordLine(20);

    try std.testing.expectEqual(@as(u64, 2), cov.getLineCount(10));
    try std.testing.expectEqual(@as(u64, 1), cov.getLineCount(20));
    try std.testing.expectEqual(@as(u64, 0), cov.getLineCount(30));

    try std.testing.expect(cov.wasLineExecuted(10));
    try std.testing.expect(!cov.wasLineExecuted(30));
}
