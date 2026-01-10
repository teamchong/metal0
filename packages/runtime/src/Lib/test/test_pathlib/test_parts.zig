//! test.test_pathlib.test_parts - Path parts tests
const std = @import("std");

pub const PathTest = struct {
    path: []const u8,
    pub fn init(p: []const u8) @This() { return .{ .path = p }; }
};

test "test_partsparts" {
    const t = PathTest.init("/test/path");
    try std.testing.expect(t.path.len > 0);
}
