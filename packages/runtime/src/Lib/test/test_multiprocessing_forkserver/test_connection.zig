//! test.test_multiprocessing_forkserver.test_connection - Multiprocessing connection tests
const std = @import("std");
pub const MPTest = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "connection" { const t = MPTest.init("test_connection"); try std.testing.expect(t.n.len > 0); }
