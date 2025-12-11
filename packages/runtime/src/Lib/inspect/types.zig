//! Core types for the inspect module
//!
//! Defines the fundamental data structures used for runtime inspection:
//! - Parameter and ParameterKind for function signatures
//! - Signature for function type information
//! - FrameInfo for stack frame inspection
//! - MemberInfo for type member information

const std = @import("std");

// ============================================================================
// Signature inspection types
// ============================================================================

/// Parameter kind enum
pub const ParameterKind = enum {
    POSITIONAL_ONLY,
    POSITIONAL_OR_KEYWORD,
    VAR_POSITIONAL,
    KEYWORD_ONLY,
    VAR_KEYWORD,
};

/// Parameter representation
pub const Parameter = struct {
    name: []const u8,
    kind: ParameterKind = .POSITIONAL_OR_KEYWORD,
    default: ?[]const u8 = null,
    annotation: ?[]const u8 = null,

    pub const empty = Parameter{ .name = "" };
};

/// Function signature
pub const Signature = struct {
    parameters: []const Parameter,
    return_annotation: ?[]const u8 = null,

    pub fn init(params: []const Parameter) Signature {
        return .{ .parameters = params };
    }

    pub fn withReturn(self: Signature, ret: []const u8) Signature {
        return .{ .parameters = self.parameters, .return_annotation = ret };
    }
};

// ============================================================================
// Stack frame inspection types
// ============================================================================

/// Frame information structure
pub const FrameInfo = struct {
    filename: []const u8,
    lineno: usize,
    function: []const u8,
    code_context: ?[]const u8,
    index: ?usize,
};

// ============================================================================
// Member inspection types
// ============================================================================

/// Member information
pub const MemberInfo = struct {
    name: []const u8,
    value_type: []const u8,
};
