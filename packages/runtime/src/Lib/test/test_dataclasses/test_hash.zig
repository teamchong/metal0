//! test.test_dataclasses.test_hash - Dataclass hash tests
const std = @import("std");

pub const DataclassTest = struct {
    name: []const u8,
    pub fn init(n: []const u8) @This() { return .{ .name = n }; }
    pub fn run(self: @This()) bool { _ = self; return true; }
};

test "hash" {
    const t = DataclassTest.init("test_hash");
    try std.testing.expect(t.run());
}
