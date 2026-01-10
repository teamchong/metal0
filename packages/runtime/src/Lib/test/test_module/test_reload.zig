//! test.test_module.test_reload
const std = @import("std");
pub const T = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "reload" { const t = T.init("test_reload"); try std.testing.expect(t.n.len > 0); }
