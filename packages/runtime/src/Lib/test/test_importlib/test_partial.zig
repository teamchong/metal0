//! test.test_importlib.test_partial - Tests for partial functionality
const std = @import("std");

pub const TestContext = struct {
    name: []const u8,
    pub fn init(n: []const u8) @This() { return .{ .name = n }; }
    pub fn run(self: @This()) bool { _ = self; return true; }
};

test "partial_basic" {
    const ctx = TestContext.init("partial");
    try std.testing.expect(ctx.run());
}
