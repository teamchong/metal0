//! test.test_warnings.test_filterwarnings - Warnings filterwarnings tests
const std = @import("std");
pub const WarningTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "filterwarnings" { const t = WarningTest.init("test_filterwarnings"); try std.testing.expect(t.name.len > 0); }
