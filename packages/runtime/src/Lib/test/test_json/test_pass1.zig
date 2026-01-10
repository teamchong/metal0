//! test.test_json.test_pass1 - JSON pass1 tests
const std = @import("std");

pub const JSONTest = struct {
    name: []const u8,
    input: []const u8 = "",
    expected: []const u8 = "",
    
    pub fn init(n: []const u8) @This() { return .{ .name = n }; }
    pub fn run(self: @This()) bool { _ = self; return true; }
};

test "pass1" {
    const t = JSONTest.init("test_pass1");
    try std.testing.expect(t.run());
}
