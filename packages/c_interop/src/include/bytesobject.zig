/// CPython Bytes Operations
///
/// This file now re-exports the full implementation from pyobject_bytes.zig
const std = @import("std");
const cpython = @import("object.zig");

// Re-export full implementation
pub usingnamespace @import("../objects/bytesobject.zig");

test "PyBytes delegation" {
    // Test that re-export works
    const bytes = PyBytes_FromString("hello");
    try std.testing.expect(bytes != null);
    try std.testing.expectEqual(@as(isize, 5), PyBytes_Size(bytes.?));
}
