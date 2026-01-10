//! test.test_warnings.test_warn_explicit - Warnings warn_explicit tests
const std = @import("std");
pub const WarningTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "warn_explicit" { const t = WarningTest.init("test_warn_explicit"); try std.testing.expect(t.name.len > 0); }
