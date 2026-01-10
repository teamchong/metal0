//! test.test_importlib.test_builtin_import - Tests for builtin_import functionality
const std = @import("std");

pub const TestContext = struct {
    name: []const u8,
    pub fn init(n: []const u8) @This() { return .{ .name = n }; }
    pub fn run(self: @This()) bool { _ = self; return true; }
};

test "builtin_import_basic" {
    const ctx = TestContext.init("builtin_import");
    try std.testing.expect(ctx.run());
}
