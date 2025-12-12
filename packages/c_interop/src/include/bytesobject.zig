/// CPython Bytes Operations
///
/// This file now re-exports the full implementation from pyobject_bytes.zig
const std = @import("std");
const cpython = @import("object.zig");

// Re-export full implementation (explicit exports for Zig 0.15 compatibility)
const bytesobject = @import("../objects/bytesobject.zig");
pub const PyBytesObject = bytesobject.PyBytesObject;
pub const PyBytes_Type = bytesobject.PyBytes_Type;
pub const PyBytes_FromString = bytesobject.PyBytes_FromString;
pub const PyBytes_FromStringAndSize = bytesobject.PyBytes_FromStringAndSize;
pub const PyBytes_Size = bytesobject.PyBytes_Size;
pub const PyBytes_AsString = bytesobject.PyBytes_AsString;
pub const PyBytes_Check = bytesobject.PyBytes_Check;

test "PyBytes delegation" {
    // Test that re-export works
    const bytes = PyBytes_FromString("hello");
    try std.testing.expect(bytes != null);
    try std.testing.expectEqual(@as(isize, 5), PyBytes_Size(bytes.?));
}
