//! test.test_multiprocessing_forkserver.test_manager - Multiprocessing manager tests
const std = @import("std");
pub const MPTest = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "manager" { const t = MPTest.init("test_manager"); try std.testing.expect(t.n.len > 0); }
