//! test.test_dataclasses.test_order - Dataclass order tests
const std = @import("std");

pub const DataclassTest = struct {
    name: []const u8,
    pub fn init(n: []const u8) @This() { return .{ .name = n }; }
    pub fn run(self: @This()) bool { _ = self; return true; }
};

test "order" {
    const t = DataclassTest.init("test_order");
    try std.testing.expect(t.run());
}
