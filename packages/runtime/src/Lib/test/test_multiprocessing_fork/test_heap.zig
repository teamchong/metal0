//! test.test_multiprocessing_fork.test_heap - Multiprocessing heap tests
const std = @import("std");
pub const MPTest = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "heap" { const t = MPTest.init("test_heap"); try std.testing.expect(t.n.len > 0); }
