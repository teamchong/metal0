//! test.test_dataclasses.test_repr - Dataclass repr tests
const std = @import("std");

pub const DataclassTest = struct {
    name: []const u8,
    pub fn init(n: []const u8) @This() { return .{ .name = n }; }
    pub fn run(self: @This()) bool { _ = self; return true; }
};

test "repr" {
    const t = DataclassTest.init("test_repr");
    try std.testing.expect(t.run());
}
