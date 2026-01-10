//! test.test_warnings.test_filters - Warnings filters tests
const std = @import("std");
pub const WarningTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "filters" { const t = WarningTest.init("test_filters"); try std.testing.expect(t.name.len > 0); }
