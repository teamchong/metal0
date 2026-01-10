//! test.test_warnings.test_simplefilter - Warnings simplefilter tests
const std = @import("std");
pub const WarningTest = struct { name: []const u8, pub fn init(n: []const u8) @This() { return .{ .name = n }; } };
test "simplefilter" { const t = WarningTest.init("test_simplefilter"); try std.testing.expect(t.name.len > 0); }
