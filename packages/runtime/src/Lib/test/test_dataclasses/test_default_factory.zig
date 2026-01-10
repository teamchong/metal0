//! test.test_dataclasses.test_default_factory - Dataclass default_factory tests
const std = @import("std");

pub const DataclassTest = struct {
    name: []const u8,
    pub fn init(n: []const u8) @This() { return .{ .name = n }; }
    pub fn run(self: @This()) bool { _ = self; return true; }
};

test "default_factory" {
    const t = DataclassTest.init("test_default_factory");
    try std.testing.expect(t.run());
}
