//! test.test_module.test_pkg
const std = @import("std");
pub const T = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "pkg" { const t = T.init("test_pkg"); try std.testing.expect(t.n.len > 0); }
