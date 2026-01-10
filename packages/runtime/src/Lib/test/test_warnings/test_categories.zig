//! test.test_warnings.test_categories - Warnings categories tests
const std = @import("std");
pub const WarningTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "categories" { const t = WarningTest.init("test_categories"); try std.testing.expect(t.name.len > 0); }
