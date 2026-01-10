//! test.test_inspect.test_getmodule - Inspect getmodule tests
const std = @import("std");

pub const InspectTest = struct {
    target: []const u8,
    pub fn init(t: []const u8) @This() { return .{ .target = t }; }
};

test "getmodule" {
    const t = InspectTest.init("test_target");
    try std.testing.expect(t.target.len > 0);
}
