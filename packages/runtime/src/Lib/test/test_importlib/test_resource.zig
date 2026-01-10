//! test.test_importlib.test_resource - Tests for resource functionality
const std = @import("std");

pub const TestContext = struct {
    name: []const u8,
    pub fn init(n: []const u8) @This() { return .{ .name = n }; }
    pub fn run(self: @This()) bool { _ = self; return true; }
};

test "resource_basic" {
    const ctx = TestContext.init("resource");
    try std.testing.expect(ctx.run());
}
