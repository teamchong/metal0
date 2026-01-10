//! test.test_module.test_relative
const std = @import("std");
pub const T = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "relative" { const t = T.init("test_relative"); try std.testing.expect(t.n.len > 0); }
