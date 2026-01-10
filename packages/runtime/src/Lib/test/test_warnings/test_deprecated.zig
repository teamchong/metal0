//! test.test_warnings.test_deprecated - Warnings deprecated tests
const std = @import("std");
pub const WarningTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "deprecated" { const t = WarningTest.init("test_deprecated"); try std.testing.expect(t.name.len > 0); }
