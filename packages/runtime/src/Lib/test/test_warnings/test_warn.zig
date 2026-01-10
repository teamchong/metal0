//! test.test_warnings.test_warn - Warnings warn tests
const std = @import("std");
pub const WarningTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "warn" { const t = WarningTest.init("test_warn"); try std.testing.expect(t.name.len > 0); }
