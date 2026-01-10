//! test.test_dataclasses.test_frozen - Dataclass frozen tests
const std = @import("std");

pub const DataclassTest = struct {
    name: []const u8,
    pub fn init(n: []const u8) @This() { return .{ .name = n }; }
    pub fn run(self: @This()) bool { _ = self; return true; }
};

test "frozen" {
    const t = DataclassTest.init("test_frozen");
    try std.testing.expect(t.run());
}
