//! CPython source: Modules/_interpretersmodule.c
//!
//! Low-level access to the interpreter-related runtime machinery.
//! Provides mechanisms for creating and managing sub-interpreters.
//!
//! In metal0's AOT compilation model, sub-interpreters are simulated
//! as isolated execution contexts rather than full Python interpreters.
//!
//! Mirrors: CPython Modules/_interpretersmodule.c

const std = @import("std");

// ============================================================================
// Error Types
// ============================================================================

pub const InterpreterError = error{
    InvalidInterpreter,
    InterpreterNotFound,
    CreationFailed,
    DestructionFailed,
    RunFailed,
    ChannelError,
    OutOfMemory,
    AlreadyRunning,
};

// ============================================================================
// Types
// ============================================================================

pub const InterpreterId = i64;

/// Interpreter configuration
pub const InterpreterConfig = struct {
    /// Whether to initialize the GIL (simulated in metal0)
    use_main_obmalloc: bool = false,
    /// Allow fork
    allow_fork: bool = true,
    /// Allow exec
    allow_exec: bool = true,
    /// Allow threads
    allow_threads: bool = true,
    /// Allow daemon threads
    allow_daemon_threads: bool = false,
    /// Check multi-interp extensions
    check_multi_interp_extensions: bool = true,
    /// GIL mode: "shared", "own", or "default"
    gil: []const u8 = "default",
};

/// Interpreter state
pub const InterpreterState = struct {
    id: InterpreterId,
    is_running: bool = false,
    created_time: i64,
    config: InterpreterConfig,
};

// ============================================================================
// Interpreter Registry
// ============================================================================

const max_interpreters = 256;
var interpreters: [max_interpreters]?InterpreterState = [_]?InterpreterState{null} ** max_interpreters;
var interpreter_count: usize = 0;
var next_id: InterpreterId = 1; // 0 is reserved for main interpreter

// ============================================================================
// Functions
// ============================================================================

/// Get the main interpreter ID
pub fn get_main() InterpreterId {
    return 0;
}

/// Get the current interpreter ID
pub fn get_current() InterpreterId {
    // In metal0 AOT, we always return main interpreter
    return 0;
}

/// Create a new sub-interpreter
pub fn create(config: ?InterpreterConfig) InterpreterError!InterpreterId {
    if (interpreter_count >= max_interpreters) {
        return error.OutOfMemory;
    }

    const cfg = config orelse InterpreterConfig{};
    const id = next_id;
    next_id += 1;

    // Find empty slot
    for (&interpreters) |*slot| {
        if (slot.* == null) {
            slot.* = InterpreterState{
                .id = id,
                .is_running = false,
                .created_time = std.time.timestamp(),
                .config = cfg,
            };
            interpreter_count += 1;
            return id;
        }
    }

    return error.CreationFailed;
}

/// Destroy a sub-interpreter
pub fn destroy(id: InterpreterId) InterpreterError!void {
    if (id == 0) {
        return error.InvalidInterpreter; // Cannot destroy main interpreter
    }

    for (&interpreters) |*slot| {
        if (slot.*) |interp| {
            if (interp.id == id) {
                if (interp.is_running) {
                    return error.AlreadyRunning;
                }
                slot.* = null;
                interpreter_count -= 1;
                return;
            }
        }
    }

    return error.InterpreterNotFound;
}

/// List all interpreter IDs
pub fn list_all(alloc: std.mem.Allocator) InterpreterError![]InterpreterId {
    var ids: std.ArrayList(InterpreterId) = .{};
    errdefer ids.deinit(alloc);

    // Always include main interpreter
    ids.append(alloc, 0) catch return error.OutOfMemory;

    // Add sub-interpreters
    for (interpreters) |slot| {
        if (slot) |interp| {
            ids.append(alloc, interp.id) catch return error.OutOfMemory;
        }
    }

    return ids.toOwnedSlice(alloc) catch error.OutOfMemory;
}

/// Check if interpreter exists
pub fn is_valid(id: InterpreterId) bool {
    if (id == 0) return true; // Main interpreter always exists

    for (interpreters) |slot| {
        if (slot) |interp| {
            if (interp.id == id) return true;
        }
    }
    return false;
}

/// Get interpreter state
pub fn get_state(id: InterpreterId) InterpreterError!InterpreterState {
    if (id == 0) {
        // Return main interpreter state
        return InterpreterState{
            .id = 0,
            .is_running = true,
            .created_time = 0,
            .config = InterpreterConfig{},
        };
    }

    for (interpreters) |slot| {
        if (slot) |interp| {
            if (interp.id == id) return interp;
        }
    }

    return error.InterpreterNotFound;
}

/// Check if interpreter is running
pub fn is_running(id: InterpreterId) InterpreterError!bool {
    const state = try get_state(id);
    return state.is_running;
}

/// Run code in an interpreter (simulated)
pub fn run_string(id: InterpreterId, code: []const u8) InterpreterError!void {
    _ = code;
    if (!is_valid(id)) {
        return error.InterpreterNotFound;
    }

    // Mark interpreter as running
    if (id != 0) {
        for (&interpreters) |*slot| {
            if (slot.*) |*interp| {
                if (interp.id == id) {
                    interp.is_running = true;
                    // Metal0 AOT: Sub-interpreters share the same native code
                    // Code execution happens via compiled function calls
                    interp.is_running = false;
                    return;
                }
            }
        }
    }

    // Main interpreter - already running
}

/// Run a function in an interpreter (simulated)
pub fn run_func(id: InterpreterId, func: *const fn () anyerror!void) InterpreterError!void {
    if (!is_valid(id)) {
        return error.InterpreterNotFound;
    }

    // Execute the function
    func() catch return error.RunFailed;
}

/// Get count of sub-interpreters (excluding main)
pub fn get_count() usize {
    return interpreter_count;
}

// ============================================================================
// Whence constants (for channel operations)
// ============================================================================

pub const WHENCE_UNKNOWN: i32 = 0;
pub const WHENCE_RUNTIME: i32 = 1;
pub const WHENCE_LEGACY_CAPI: i32 = 2;
pub const WHENCE_CAPI: i32 = 3;
pub const WHENCE_XI: i32 = 4;

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
    interpreter_count = 0;
    next_id = 1;
    for (&interpreters) |*slot| {
        slot.* = null;
    }
}

pub fn reset() void {
    initialized = false;
    interpreter_count = 0;
    next_id = 1;
    for (&interpreters) |*slot| {
        slot.* = null;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "get_main returns 0" {
    try std.testing.expectEqual(@as(InterpreterId, 0), get_main());
}

test "get_current returns main" {
    try std.testing.expectEqual(@as(InterpreterId, 0), get_current());
}

test "main interpreter is always valid" {
    try std.testing.expect(is_valid(0));
}

test "create and destroy interpreter" {
    reset();

    const id = try create(null);
    try std.testing.expect(id > 0);
    try std.testing.expect(is_valid(id));

    try destroy(id);
    try std.testing.expect(!is_valid(id));
}

test "cannot destroy main interpreter" {
    const result = destroy(0);
    try std.testing.expectError(error.InvalidInterpreter, result);
}

test "list_all includes main" {
    reset();
    const allocator = std.testing.allocator;

    const ids = try list_all(allocator);
    defer allocator.free(ids);

    try std.testing.expect(ids.len >= 1);
    try std.testing.expectEqual(@as(InterpreterId, 0), ids[0]);
}

test "whence constants" {
    try std.testing.expectEqual(@as(i32, 0), WHENCE_UNKNOWN);
    try std.testing.expectEqual(@as(i32, 1), WHENCE_RUNTIME);
}
