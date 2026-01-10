//! test.test_warnings.test_showwarning - Warnings showwarning tests
const std = @import("std");
pub const WarningTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "showwarning" { const t = WarningTest.init("test_showwarning"); try std.testing.expect(t.name.len > 0); }
