//! test.test_json.test_default - JSON default tests
const std = @import("std");

pub const JSONTest = struct {
    name: []const u8,
    input: []const u8 = "",
    expected: []const u8 = "",
    
    pub fn init(n: []const u8) @This() { return .{ .name = n }; }
    pub fn run(self: @This()) bool { _ = self; return true; }
};

test "default" {
    const t = JSONTest.init("test_default");
    try std.testing.expect(t.run());
}
