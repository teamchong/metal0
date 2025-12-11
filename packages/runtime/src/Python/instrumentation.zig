/// instrumentation - Profiling Instrumentation
/// Mirrors cpython/Python/instrumentation.c
///
/// This module provides PEP 669 monitoring/instrumentation API:
/// - Per-code-object monitoring events
/// - Tool registration and callbacks
/// - Event filtering
/// - Low-overhead instrumentation

const std = @import("std");

// ============================================================================
// Module Exports
// ============================================================================

pub const types = @import("instrumentation/types.zig");
pub const tool_state = @import("instrumentation/tool_state.zig");
pub const monitoring_state = @import("instrumentation/monitoring_state.zig");
pub const code_instrumentation = @import("instrumentation/code_instrumentation.zig");
pub const coverage = @import("instrumentation/coverage.zig");

// Re-export core types
pub const MAX_TOOLS = types.MAX_TOOLS;
pub const NUM_EVENTS = types.NUM_EVENTS;
pub const MonitoringEvent = types.MonitoringEvent;
pub const ToolId = types.ToolId;
pub const MonitoringCallback = types.MonitoringCallback;
pub const ToolState = tool_state.ToolState;
pub const MonitoringState = monitoring_state.MonitoringState;
pub const CodeInstrumentation = code_instrumentation.CodeInstrumentation;
pub const CoverageData = coverage.CoverageData;

// ============================================================================
// Global State
// ============================================================================

var g_monitoring: MonitoringState = MonitoringState.init();

/// Get global monitoring state
pub fn getMonitoring() *MonitoringState {
    return &g_monitoring;
}

/// Get current monitoring version
fn getMonitoringVersion() u64 {
    return g_monitoring.version.load(.acquire);
}

// Set up version getter for code instrumentation
comptime {
    _ = &code_instrumentation.setVersionGetter;
}

pub fn initVersionGetter() void {
    code_instrumentation.setVersionGetter(&getMonitoringVersion);
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
// Initialization
// ============================================================================

pub fn init() void {
    initVersionGetter();
}

// ============================================================================
// Tests
// ============================================================================

test {
    std.testing.refAllDecls(@This());
}
