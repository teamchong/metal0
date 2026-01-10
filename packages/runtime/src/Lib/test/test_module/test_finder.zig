//! test.test_module.test_finder
const std = @import("std");
pub const T = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "finder" { const t = T.init("test_finder"); try std.testing.expect(t.n.len > 0); }
