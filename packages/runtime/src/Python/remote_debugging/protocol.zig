/// protocol - Debug Protocol Types
/// Debug message types, notifications, and protocol version.

const std = @import("std");

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
