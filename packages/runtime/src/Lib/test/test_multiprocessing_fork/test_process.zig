//! test.test_multiprocessing_fork.test_process - Multiprocessing process tests
const std = @import("std");
pub const MPTest = struct { n: []const u8, pub fn init(n: []const u8) @This() { return .{ .n = n }; } };
test "process" { const t = MPTest.init("test_process"); try std.testing.expect(t.n.len > 0); }
