//! test.test_module.test_spec
const std = @import("std");
pub const T = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "spec" { const t = T.init("test_spec"); try std.testing.expect(t.n.len > 0); }
