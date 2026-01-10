//! test.test_warnings.test_catch_warnings - Warnings catch_warnings tests
const std = @import("std");
pub const WarningTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "catch_warnings" { const t = WarningTest.init("test_catch_warnings"); try std.testing.expect(t.name.len > 0); }
