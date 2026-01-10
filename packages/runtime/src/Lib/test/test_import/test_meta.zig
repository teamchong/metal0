//! test.test_import.test_meta
const std = @import("std");
pub const T = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "meta" { const t = T.init("test_meta"); try std.testing.expect(t.n.len > 0); }
