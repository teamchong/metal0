//! test.test_module.test_loader
const std = @import("std");
pub const T = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "loader" { const t = T.init("test_loader"); try std.testing.expect(t.n.len > 0); }
