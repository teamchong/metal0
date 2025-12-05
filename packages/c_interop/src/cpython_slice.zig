/// CPython Slice Protocol
///
/// Re-exports slice functions from pyobject_slice.zig for API compatibility.
/// The canonical implementation is in pyobject_slice.zig.

const std = @import("std");
const pyslice = @import("pyobject_slice.zig");

// Re-export types
pub const PySliceObject = pyslice.PySliceObject;
pub const PySlice_Type = pyslice.PySlice_Type;
pub const PyEllipsis_Type = pyslice.PyEllipsis_Type;

// Note: The actual export functions are in pyobject_slice.zig
// This file just provides type re-exports for internal use.

// Tests
test "slice exports" {
    _ = pyslice.PySlice_New;
    _ = pyslice.PySlice_GetIndices;
}
