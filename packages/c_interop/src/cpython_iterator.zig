/// CPython Iterator Protocol Implementation
///
/// Re-exports iterator functions from pyobject_iter.zig for API compatibility.
/// The canonical implementation is in pyobject_iter.zig.

const std = @import("std");
const pyiter = @import("pyobject_iter.zig");

// Re-export types
pub const PySeqIterObject = pyiter.PySeqIterObject;
pub const PyCallIterObject = pyiter.PyCallIterObject;
pub const PySeqIter_Type = pyiter.PySeqIter_Type;
pub const PyCallIter_Type = pyiter.PyCallIter_Type;

// Note: The actual export functions are in pyobject_iter.zig
// This file just provides type re-exports for internal use.

// Tests
test "PyIter function exports" {
    _ = pyiter.PyObject_GetIter;
    _ = pyiter.PyIter_Next;
    _ = pyiter.PyIter_Check;
}
