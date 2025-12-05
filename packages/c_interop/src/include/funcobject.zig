/// CPython Function Objects
///
/// Re-exports PyCFunction_* from pyobject_method.zig for API compatibility.
/// The canonical implementation is in pyobject_method.zig.

const std = @import("std");
const pymethod = @import("../objects/methodobject.zig");

// Re-export types
pub const PyCFunctionObject = pymethod.PyCFunctionObject;
pub const PyCMethodObject = pymethod.PyCMethodObject;
pub const PyCFunction_Type = pymethod.PyCFunction_Type;
pub const PyCMethod_Type = pymethod.PyCMethod_Type;

// Note: The actual export functions are in pyobject_method.zig
// This file just provides type re-exports for internal use.

test "PyCFunctionObject layout" {
    try std.testing.expect(@sizeOf(PyCFunctionObject) > 0);
}
