//! test.test_import.test_path
const std = @import("std");
pub const T = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "path" { const t = T.init("test_path"); try std.testing.expect(t.n.len > 0); }
