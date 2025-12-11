/// Frame Utilities
/// Helper functions and types for frame operations

const InterpreterFrame = @import("interpreter_frame.zig").InterpreterFrame;

// ============================================================================
// Executable Kinds
// ============================================================================

/// Types of executables that can be in a frame
pub const ExecutableKind = enum(u8) {
    skip = 0, // Skip this frame (None)
    py_function = 1, // Python function (code object)
    builtin_function = 2, // Built-in function
    method_descriptor = 3, // Method descriptor
};

// ============================================================================
// Frame Utilities
// ============================================================================

/// Calculate number of slots needed for a code object
pub fn numSlotsForCode(code_framesize: usize) usize {
    const specials_size = @sizeOf(InterpreterFrame) / @sizeOf(?*anyopaque);
    if (code_framesize < specials_size) return 0;
    return code_framesize - specials_size;
}

/// Get the locals array from a frame
pub fn getLocalsArray(frame: *InterpreterFrame) []?*anyopaque {
    return frame.localsplus[0..frame.nlocalsplus];
}

/// Get the stack base pointer
pub fn getStackbase(frame: *InterpreterFrame) []?*anyopaque {
    const base = frame.stackBase();
    return frame.localsplus[base..frame.stackpointer];
}

/// Set the stack pointer
pub fn setStackPointer(frame: *InterpreterFrame, sp: usize) void {
    frame.stackpointer = sp;
}
