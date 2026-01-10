//! test.test_pathlib.test_resolve - Path resolve tests
const std = @import("std");

pub const PathTest = struct {
    path: []const u8,
    pub fn init(p: []const u8) @This() { return .{ .path = p }; }
};

test "test_resolveresolve" {
    const t = PathTest.init("/test/path");
    try std.testing.expect(t.path.len > 0);
}
