/// Line Number Computation
/// Maps bytecode offsets to source line numbers

const InterpreterFrame = @import("interpreter_frame.zig").InterpreterFrame;

// ============================================================================
// Line Number Computation
// ============================================================================

/// Line table entry for mapping bytecode offsets to source lines
pub const LineTableEntry = struct {
    start_offset: u32,
    end_offset: u32,
    line: i32,
};

/// Thread-local line table for current frame (set during execution)
threadlocal var current_line_table: ?[]const LineTableEntry = null;

/// Set line table for current frame (called when entering function)
pub fn setLineTable(table: []const LineTableEntry) void {
    current_line_table = table;
}

/// Clear line table (called when exiting function)
pub fn clearLineTable() void {
    current_line_table = null;
}

/// Get line number for a frame using instruction pointer and line table
/// Mirrors: PyUnstable_InterpreterFrame_GetLine
pub fn getFrameLine(frame: *InterpreterFrame) i32 {
    const instr_offset = frame.instr_ptr;

    // Check thread-local line table
    if (current_line_table) |table| {
        // Binary search for the line entry containing this offset
        for (table) |entry| {
            if (instr_offset >= entry.start_offset and instr_offset < entry.end_offset) {
                return entry.line;
            }
        }
    }

    // If no line table is available, try to extract from debug info
    // stored in the frame's executable (code object)
    if (frame.f_executable) |_| {
        // Code object might have embedded line info
        // For AOT compiled code, this is typically in debug symbols
        return -1; // Unknown line
    }

    return 0; // No line information available
}
