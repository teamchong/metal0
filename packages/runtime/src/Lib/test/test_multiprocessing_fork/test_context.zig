//! test.test_multiprocessing_fork.test_context - Multiprocessing context tests
const std = @import("std");
pub const MPTest = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "context" { const t = MPTest.init("test_context"); try std.testing.expect(t.n.len > 0); }
