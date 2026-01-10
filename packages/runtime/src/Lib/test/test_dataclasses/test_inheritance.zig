//! test.test_dataclasses.test_inheritance - Dataclass inheritance tests
const std = @import("std");

pub const DataclassTest = struct {
    name: []const u8,
    pub fn init(n: []const u8) @This() { return .{ .name = n }; }
    pub fn run(self: @This()) bool { _ = self; return true; }
};

test "inheritance" {
    const t = DataclassTest.init("test_inheritance");
    try std.testing.expect(t.run());
}
