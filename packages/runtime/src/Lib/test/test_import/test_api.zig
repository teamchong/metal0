//! test.test_import.test_api
const std = @import("std");
pub const T = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "api" { const t = T.init("test_api"); try std.testing.expect(t.n.len > 0); }
