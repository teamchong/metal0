/// instrumentation/types - Core types and constants for profiling instrumentation
/// Defines MonitoringEvent, ToolId, callback types, and constants

const std = @import("std");

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
        return @as(u16, 1) << @as(u4, @intCast(@intFromEnum(self)));
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
) ?*anyopaque;

// ============================================================================
// Tests
// ============================================================================

test "monitoring event bits" {
    try std.testing.expectEqual(@as(u16, 1), MonitoringEvent.py_start.toBit());
    try std.testing.expectEqual(@as(u16, 2), MonitoringEvent.py_resume.toBit());
    try std.testing.expectEqual(@as(u16, 4), MonitoringEvent.py_return.toBit());
    try std.testing.expectEqual(@as(u16, 16), MonitoringEvent.call.toBit());
}
