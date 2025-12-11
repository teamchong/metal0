//! Core types for the debugger.
//!
//! Defines the fundamental types used throughout the debugger:
//! - BpType: Breakpoint types (breakpoint, temporary, conditional)
//! - StopReason: Reasons for stopping execution (step, next, breakpoint, etc.)
//! - FrameInfo: Frame information for debugging context

const std = @import("std");

// ============================================================================
// Breakpoint Types
// ============================================================================

/// Breakpoint types
pub const BpType = enum {
    breakpoint,
    temporary,
    conditional,
};

// ============================================================================
// Stop Reasons
// ============================================================================

/// Reasons for stopping execution
pub const StopReason = enum {
    step,
    next,
    return_,
    call,
    line,
    breakpoint,
    exception,
    quit,
};

/// Frame information for debugging
pub const FrameInfo = struct {
    filename: []const u8,
    lineno: usize,
    function: []const u8,
    code_context: ?[]const u8,
    locals: ?*anyopaque, // Frame locals (PyDict in CPython)
};

/// Comparison operators for condition evaluation
pub const CompareOp = enum { eq, ne, gt, lt, ge, le };
