/// instrumentation/tool_state - Per-tool monitoring state
/// Manages registration, event masks, and callbacks for individual tools

const std = @import("std");
const types = @import("types.zig");

const MonitoringEvent = types.MonitoringEvent;
const MonitoringCallback = types.MonitoringCallback;
const NUM_EVENTS = types.NUM_EVENTS;

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
// Tests
// ============================================================================

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
