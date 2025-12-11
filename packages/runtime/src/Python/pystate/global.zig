/// global - Global State
/// Thread-local storage and global interpreter list.

const std = @import("std");
const types = @import("types.zig");
const interpreter = @import("interpreter.zig");

pub const ThreadState = types.ThreadState;
pub const InterpreterState = interpreter.InterpreterState;

// ============================================================================
// Thread-Local Storage
// ============================================================================

/// Current thread state (thread-local)
pub threadlocal var _tss_tstate: ?*ThreadState = null;

/// Current interpreter (thread-local, for faster access)
pub threadlocal var _tss_interp: ?*InterpreterState = null;

/// GILState thread state (thread-local)
pub threadlocal var _tss_gilstate: ?*ThreadState = null;

// ============================================================================
// Global State
// ============================================================================

/// Interpreter list structure
pub const InterpreterList = struct {
    head: ?*InterpreterState = null,
    main: ?*InterpreterState = null,
    count: u64 = 0,
};

/// Global interpreter list
pub var interpreters: InterpreterList = .{};

/// Next interpreter ID
pub var next_interp_id: i64 = 0;
