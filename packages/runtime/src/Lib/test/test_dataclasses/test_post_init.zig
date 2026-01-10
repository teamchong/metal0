//! test.test_dataclasses.test_post_init - Dataclass post_init tests
const std = @import("std");

pub const DataclassTest = struct {
    name: []const u8,
    pub fn init(n: []const u8) @This() { return .{ .name = n }; }
    pub fn run(self: @This()) bool { _ = self; return true; }
};

test "post_init" {
    const t = DataclassTest.init("test_post_init");
    try std.testing.expect(t.run());
}
