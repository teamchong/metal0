/// objects - Object Protocol Functions
/// getattr(), setattr(), delattr(), hasattr() implementations.

const std = @import("std");
const errors = @import("../errors.zig");

// ============================================================================
// Object Protocol
// ============================================================================

/// Get attribute
/// Mirrors: builtin getattr()
pub fn getattr_builtin(obj: anytype, name: []const u8, default: anytype) @TypeOf(default) {
    _ = obj;
    _ = name;
    return default;
}

/// Set attribute
/// Mirrors: builtin setattr()
pub fn setattr_builtin(obj: anytype, name: []const u8, value: anytype) !void {
    _ = obj;
    _ = name;
    _ = value;
    errors.setString("AttributeError", "cannot set attribute");
    return error.AttributeError;
}

/// Delete attribute
/// Mirrors: builtin delattr()
pub fn delattr_builtin(obj: anytype, name: []const u8) !void {
    _ = obj;
    _ = name;
    errors.setString("AttributeError", "cannot delete attribute");
    return error.AttributeError;
}

/// Check if attribute exists
/// Mirrors: builtin hasattr()
pub fn hasattr_builtin(obj: anytype, name: []const u8) bool {
    _ = obj;
    _ = name;
    return false;
}

// ============================================================================
// Vars and Globals (AOT: compile-time only)
// ============================================================================

/// Get local variables - AOT limitation
/// Mirrors: builtin locals()
/// In AOT compilation, local variables are compiled to registers/stack
/// and not accessible as a dictionary at runtime
pub fn locals_builtin() void {
    // Local variable introspection requires interpreter - not available in AOT
    // Codegen handles locals() calls by generating compile-time dict if possible
}

/// Get global variables - AOT limitation
/// Mirrors: builtin globals()
/// In AOT compilation, module globals are compiled as static constants
pub fn globals_builtin() void {
    // Global variable introspection requires module dict - handled by codegen
    // Runtime globals() returns empty dict in pure AOT context
}

/// Get variables dictionary - AOT limitation
/// Mirrors: builtin vars()
/// Returns __dict__ of an object, or locals() if no argument
pub fn vars_builtin(_: anytype) void {
    // Object __dict__ access handled by codegen for known types
    // For dynamic objects, returns empty dict
}

// ============================================================================
// Class Building
// ============================================================================

/// Build a class (used by class statement)
/// Mirrors: builtin __build_class__
pub fn __build_class__(func: anytype, name: []const u8, bases: anytype, kwds: anytype) !type {
    _ = func;
    _ = name;
    _ = bases;
    _ = kwds;
    // Class construction is handled at compile time in AOT
    @compileError("__build_class__ is compile-time in AOT");
}
