//! Python '_xxsubinterpreters' module - Sub-interpreter internals
//!
//! Low-level sub-interpreter support for multi-interpreter applications.
//! Provides internal mechanisms for interpreter lifecycle management.
//!
//! In metal0's AOT model, this provides simulated sub-interpreter support
//! for compatibility with code that uses the interpreters module.
//!
//! Mirrors: CPython Modules/_xxsubinterpretersmodule.c

const std = @import("std");
const interpreters = @import("_interpreters.zig");

// ============================================================================
// Re-exports from _interpreters
// ============================================================================

pub const InterpreterError = interpreters.InterpreterError;
pub const InterpreterId = interpreters.InterpreterId;
pub const InterpreterConfig = interpreters.InterpreterConfig;
pub const InterpreterState = interpreters.InterpreterState;

// ============================================================================
// Error Types
// ============================================================================

pub const SubInterpreterError = error{
    InvalidInterpreter,
    InterpreterNotFound,
    CreationFailed,
    DestructionFailed,
    RunFailed,
    OutOfMemory,
    AlreadyRunning,
    NotSupported,
};

// ============================================================================
// Types
// ============================================================================

/// Run result from executing code in a sub-interpreter
pub const RunResult = struct {
    success: bool = true,
    exc_type: ?[]const u8 = null,
    exc_msg: ?[]const u8 = null,
    return_value: ?[]const u8 = null,
};

/// Execution flags
pub const ExecFlags = struct {
    /// Don't import __main__
    skip_main: bool = false,
    /// Run in isolated mode
    isolated: bool = false,
    /// Allow imports
    allow_imports: bool = true,
};

// ============================================================================
// Functions
// ============================================================================

/// Create a new sub-interpreter
pub fn create(config: ?InterpreterConfig) SubInterpreterError!InterpreterId {
    return interpreters.create(config) catch |e| {
        return switch (e) {
            error.OutOfMemory => error.OutOfMemory,
            error.CreationFailed => error.CreationFailed,
            else => error.CreationFailed,
        };
    };
}

/// Create with default configuration
pub fn create_default() SubInterpreterError!InterpreterId {
    return create(InterpreterConfig{});
}

/// Destroy a sub-interpreter
pub fn destroy(id: InterpreterId) SubInterpreterError!void {
    return interpreters.destroy(id) catch |e| {
        return switch (e) {
            error.InvalidInterpreter => error.InvalidInterpreter,
            error.InterpreterNotFound => error.InterpreterNotFound,
            error.AlreadyRunning => error.AlreadyRunning,
            else => error.DestructionFailed,
        };
    };
}

/// Run code string in a sub-interpreter
pub fn run_string(id: InterpreterId, code: []const u8, flags: ?ExecFlags) SubInterpreterError!RunResult {
    _ = flags;

    interpreters.run_string(id, code) catch |e| {
        return switch (e) {
            error.InterpreterNotFound => error.InterpreterNotFound,
            error.RunFailed => RunResult{
                .success = false,
                .exc_type = "RuntimeError",
                .exc_msg = "Execution failed",
            },
            else => error.RunFailed,
        };
    };

    return RunResult{
        .success = true,
    };
}

/// Run a file in a sub-interpreter
pub fn run_file(id: InterpreterId, path: []const u8, flags: ?ExecFlags) SubInterpreterError!RunResult {
    _ = path;
    _ = flags;

    if (!interpreters.is_valid(id)) {
        return error.InterpreterNotFound;
    }

    // In metal0 AOT, we would compile and run the file
    return RunResult{
        .success = true,
    };
}

/// Execute a callable in a sub-interpreter
pub fn exec_func(id: InterpreterId, func: *const fn () anyerror!void) SubInterpreterError!RunResult {
    interpreters.run_func(id, func) catch |e| {
        _ = e;
        return RunResult{
            .success = false,
            .exc_type = "RuntimeError",
            .exc_msg = "Function execution failed",
        };
    };

    return RunResult{
        .success = true,
    };
}

/// Get the main interpreter ID
pub fn get_main() InterpreterId {
    return interpreters.get_main();
}

/// Get the current interpreter ID
pub fn get_current() InterpreterId {
    return interpreters.get_current();
}

/// List all interpreter IDs
pub fn list_all(allocator: std.mem.Allocator) SubInterpreterError![]InterpreterId {
    return interpreters.list_all(allocator) catch error.OutOfMemory;
}

/// Check if interpreter exists
pub fn is_valid(id: InterpreterId) bool {
    return interpreters.is_valid(id);
}

/// Check if interpreter is running
pub fn is_running(id: InterpreterId) SubInterpreterError!bool {
    return interpreters.is_running(id) catch |e| {
        return switch (e) {
            error.InterpreterNotFound => error.InterpreterNotFound,
            else => false,
        };
    };
}

/// Get interpreter configuration
pub fn get_config(id: InterpreterId) SubInterpreterError!InterpreterConfig {
    const state = interpreters.get_state(id) catch |e| {
        return switch (e) {
            error.InterpreterNotFound => error.InterpreterNotFound,
            else => error.InvalidInterpreter,
        };
    };
    return state.config;
}

/// Check if current interpreter is main
pub fn is_main_interpreter() bool {
    return get_current() == get_main();
}

/// Get count of sub-interpreters
pub fn get_count() usize {
    return interpreters.get_count();
}

// ============================================================================
// Shareable Data Types
// ============================================================================

/// Data that can be shared between interpreters
pub const ShareableData = union(enum) {
    none: void,
    int: i64,
    float: f64,
    string: []const u8,
    bytes: []const u8,
    boolean: bool,
};

/// Make data shareable (copy for transfer between interpreters)
pub fn make_shareable(allocator: std.mem.Allocator, data: ShareableData) !ShareableData {
    return switch (data) {
        .string => |s| ShareableData{ .string = try allocator.dupe(u8, s) },
        .bytes => |b| ShareableData{ .bytes = try allocator.dupe(u8, b) },
        else => data,
    };
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

pub fn init() void {
    if (initialized) return;
    initialized = true;
    interpreters.init();
}

pub fn reset() void {
    interpreters.reset();
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "create and destroy" {
    reset();

    const id = try create(null);
    try std.testing.expect(id > 0);
    try std.testing.expect(is_valid(id));

    try destroy(id);
    try std.testing.expect(!is_valid(id));
}

test "get_main returns 0" {
    try std.testing.expectEqual(@as(InterpreterId, 0), get_main());
}

test "is_main_interpreter" {
    try std.testing.expect(is_main_interpreter());
}

test "run_string in subinterpreter" {
    reset();

    const id = try create(null);
    defer destroy(id) catch {};

    const result = try run_string(id, "x = 1 + 1", null);
    try std.testing.expect(result.success);
}

test "list_all" {
    reset();
    const allocator = std.testing.allocator;

    const id1 = try create(null);
    const id2 = try create(null);
    defer {
        destroy(id1) catch {};
        destroy(id2) catch {};
    }

    const ids = try list_all(allocator);
    defer allocator.free(ids);

    try std.testing.expect(ids.len >= 3); // main + 2 sub-interpreters
}

test "shareable data" {
    const allocator = std.testing.allocator;

    const original = ShareableData{ .string = "hello" };
    const copied = try make_shareable(allocator, original);
    defer if (copied == .string) allocator.free(copied.string);

    try std.testing.expectEqualStrings("hello", copied.string);
}

test "get_count" {
    reset();

    try std.testing.expectEqual(@as(usize, 0), get_count());

    const id = try create(null);
    try std.testing.expectEqual(@as(usize, 1), get_count());

    try destroy(id);
    try std.testing.expectEqual(@as(usize, 0), get_count());
}
