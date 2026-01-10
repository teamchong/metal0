//! test.test_pathlib.test_pathlib_abc - Path pathlib_abc tests
const std = @import("std");

pub const PathTest = struct {
    path: []const u8,
    pub fn init(p: []const u8) @This() { return .{ .path = p }; }
};

test "abcpathlib_abc" {
    const t = PathTest.init("/test/path");
    try std.testing.expect(t.path.len > 0);
}
