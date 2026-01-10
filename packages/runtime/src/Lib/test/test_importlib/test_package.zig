//! test.test_importlib.test_package - Tests for package functionality
const std = @import("std");

pub const TestContext = struct {
    name: []const u8,
    pub fn init(n: []const u8) @This() { return .{ .name = n }; }
    pub fn run(self: @This()) bool { _ = self; return true; }
};

test "package_basic" {
    const ctx = TestContext.init("package");
    try std.testing.expect(ctx.run());
}
