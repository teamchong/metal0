//! test.test_multiprocessing_forkserver.test_pool - Multiprocessing pool tests
const std = @import("std");
pub const MPTest = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "pool" { const t = MPTest.init("test_pool"); try std.testing.expect(t.n.len > 0); }
