/// instrumentation/monitoring_state - Global monitoring state management
/// Manages tool registration, event masks, and event firing

const std = @import("std");
const types = @import("types.zig");
const tool_state = @import("tool_state.zig");

const MonitoringEvent = types.MonitoringEvent;
const ToolId = types.ToolId;
const MonitoringCallback = types.MonitoringCallback;
const MAX_TOOLS = types.MAX_TOOLS;
const ToolState = tool_state.ToolState;
const Atomic = std.atomic.Value;

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

        for (&self.tools, 0..) |*tool, idx| {
            if (tool.isMonitoring(event)) {
                if (tool.getCallback(event)) |callback| {
                    _ = callback(@enumFromInt(idx), event, code_object, instruction_offset, arg);
                }
            }
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

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
