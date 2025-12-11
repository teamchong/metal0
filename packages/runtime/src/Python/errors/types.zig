/// types - New Exception Type Creation
/// Mirrors cpython/Python/errors.c exception type creation
///
/// This module provides functions for creating new exception types.
/// In AOT compiled code, exception types are static.

/// Create a new exception class (returns type name for now)
/// Mirrors: PyErr_NewException
pub fn newException(name: []const u8, base: ?[]const u8, doc: ?[]const u8) []const u8 {
    _ = base;
    _ = doc;
    // In AOT compiled code, exception types are static
    // Just return the name for registration
    return name;
}

/// Create new exception with docstring
/// Mirrors: PyErr_NewExceptionWithDoc
pub fn newExceptionWithDoc(name: []const u8, doc: []const u8, base: ?[]const u8, dict: anytype) []const u8 {
    _ = dict;
    _ = base;
    _ = doc;
    return name;
}
