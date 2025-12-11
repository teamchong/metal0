/// introspection - Object Size, Reference Count, and Interning
/// Runtime introspection functions

const std = @import("std");

// ============================================================================
// Object Size and Reference Count
// ============================================================================

/// Get the size of an object in bytes
/// Mirrors: sys.getsizeof()
pub fn getsizeof(comptime T: type) usize {
    return @sizeOf(T);
}

/// Get the reference count of an object (always 1 in AOT Zig)
/// Mirrors: sys.getrefcount()
pub fn getrefcount(_: anytype) u64 {
    // In AOT compiled code without GC, everything is either
    // stack-allocated or has a single owner
    return 1;
}

// ============================================================================
// String Interning
// ============================================================================

/// Intern a string (no-op in AOT - strings are compile-time)
/// Mirrors: sys.intern()
pub fn intern(s: []const u8) []const u8 {
    return s;
}
