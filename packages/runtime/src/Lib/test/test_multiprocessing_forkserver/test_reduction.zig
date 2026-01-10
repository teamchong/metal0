//! test.test_multiprocessing_forkserver.test_reduction - Multiprocessing reduction tests
const std = @import("std");
pub const MPTest = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "reduction" { const t = MPTest.init("test_reduction"); try std.testing.expect(t.n.len > 0); }
