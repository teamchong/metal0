/// stack_frame - Stack Frame and Variable Types
/// Debug information for stack frames and variables.

const std = @import("std");

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
