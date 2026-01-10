//! test.test_module.test_circular
const std = @import("std");
pub const T = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "circular" { const t = T.init("test_circular"); try std.testing.expect(t.n.len > 0); }
