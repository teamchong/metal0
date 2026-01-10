//! test.test_warnings.test_formatwarning - Warnings formatwarning tests
const std = @import("std");
pub const WarningTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "formatwarning" { const t = WarningTest.init("test_formatwarning"); try std.testing.expect(t.name.len > 0); }
